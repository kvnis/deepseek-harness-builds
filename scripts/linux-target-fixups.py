#!/usr/bin/env python3
"""Widen the Desktop build-path modules to a Linux target.

Upstream rewrites `apps/desktop/scripts/desktop-build-paths.{d.mts,mjs}` almost
every release: 0.2.2-alpha.2 added a `pnpmStore` path, an `environment`
parameter and turned `desktopTargetPlatform` into a lookup table. A diff hunk
anchored on those lines fails the moment they move, so the change lives here as
narrow rewrites that match the *current* shape and refuse to run otherwise.

Run after patches/0001-linux-appimage.patch, before the build. It is idempotent
and fails loudly, with the file and pattern, when upstream moves again.

Usage: scripts/linux-target-fixups.py <upstream-dir>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

UNION = "'mac-arm64' | 'mac-x64' | 'win-x64'"
WIDE_UNION = f"{UNION} | 'linux-x64'"
PLATFORM = "'darwin' | 'win32'"
WIDE_PLATFORM = f"{PLATFORM} | 'linux'"


def die(message: str) -> None:
    print(f"linux-target-fixups: {message}", file=sys.stderr)
    sys.exit(1)


def sub(text: str, pattern: str, repl: str, what: str) -> str:
    new, count = re.subn(pattern, repl, text, flags=re.M)
    if count == 0:
        die(f"{what}: no match for /{pattern}/")
    return new


def widen_declaration(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "'linux-x64'" in text:
        return
    if "export type DesktopBuildTarget" not in text:
        text = sub(
            text,
            r"^(import type \{ DesktopAutoUpdateTarget \} from '\./desktop-auto-update-environment\.mjs'\n)",
            r"\1\n/** Release targets the packaging pipeline can prepare; Linux builds are local and unsigned. */\n"
            r"export type DesktopBuildTarget = DesktopAutoUpdateTarget | 'linux-x64'\n",
            f"{path.name}: DesktopAutoUpdateTarget import",
        )
    text = sub(
        text,
        r"\): DesktopAutoUpdateTarget",
        "): DesktopBuildTarget",
        f"{path.name}: resolveDesktopBuildTarget return type",
    )
    text = sub(
        text,
        r"(export function desktopTargetBuildPaths\(target: )DesktopAutoUpdateTarget",
        r"\1DesktopBuildTarget",
        f"{path.name}: desktopTargetBuildPaths target type",
    )
    if "export function desktopTargetPlatform(target: DesktopAutoUpdateTarget" in text:
        text = sub(
            text,
            r"(export function desktopTargetPlatform\(target: )DesktopAutoUpdateTarget",
            r"\1DesktopBuildTarget",
            f"{path.name}: desktopTargetPlatform target type",
        )
    text = sub(text, re.escape(PLATFORM), WIDE_PLATFORM, f"{path.name}: platform union")
    path.write_text(text, encoding="utf-8")


def widen_implementation(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "'linux-x64'" in text:
        return
    text = sub(
        text,
        r"(const SUPPORTED_TARGETS = new Set\(\[[^]]*)\]\)",
        r"\1, 'linux-x64'])",
        f"{path.name}: SUPPORTED_TARGETS",
    )
    text = text.replace(UNION, WIDE_UNION).replace(PLATFORM, WIDE_PLATFORM)

    table = re.compile(r"\n(    'win-x64': \{ platform: 'win32', arch: 'x64' \},\n)")
    if table.search(text):
        text = table.sub(r"\n\1    'linux-x64': { platform: 'linux', arch: 'x64' },\n", text, count=1)
    else:
        ternary = r"\(target === 'win-x64' \? 'win32' : 'darwin'\)"
        if not re.search(ternary, text):
            die(f"{path.name}: desktopTargetPlatform is neither a lookup table nor the known ternary")
        text = re.sub(
            ternary,
            "(target === 'win-x64' ? 'win32' : target === 'linux-x64' ? 'linux' : 'darwin')",
            text,
        )
    path.write_text(text, encoding="utf-8")


def add_linux_package_environment(path: Path) -> None:
    """Export localLinuxPackageEnvironment and accept the Linux platform."""
    text = path.read_text(encoding="utf-8")
    if "localLinuxPackageEnvironment" not in text:
        anchor = re.search(
            r"(?m)^export function (?:localMacOSPackageEnvironment|localUnsignedPackageEnvironment)"
            r"\(environment = process\.env\) \{\n",
            text,
        )
        if anchor is None:
            die(f"{path.name}: no local unsigned defaults function to build on")
        end = text.index("\n}\n", anchor.end()) + len("\n}\n")
        text = (
            text[:end]
            + "\n/**\n"
            + " * Select local Linux defaults; Linux has no release configuration and builds unsigned AppImages only.\n"
            + " * @param {NodeJS.ProcessEnv} environment Parent environment, retained for build tools and networking.\n"
            + " * @returns {NodeJS.ProcessEnv} Unsigned build environment with the standard application identifier and no update policy.\n"
            + " */\n"
            + "export function localLinuxPackageEnvironment(environment = process.env) {\n"
            + "  return localMacOSPackageEnvironment(environment)\n"
            + "}\n"
            + text[end:]
        )
    text = text.replace("'win32' | 'darwin'", "'win32' | 'darwin' | 'linux'")
    if "target.platform === 'linux'" not in text:
        needle = "  resolveNpmRegistry(environment)\n"
        if text.count(needle) != 1:
            die(f"{path.name}: resolveNpmRegistry call is not unique")
        text = text.replace(
            needle,
            needle
            + "  // Linux has no release channel: only the local unsigned AppImage build is supported.\n"
            + "  if (target.platform === 'linux') {\n"
            + "    if (!options.unsigned) throw new Error('desktop package: linux-x64 is available as an unsigned local build only')\n"
            + "    return\n"
            + "  }\n",
            1,
        )
    path.write_text(text, encoding="utf-8")


def guard_linux_release_record(path: Path) -> None:
    """Skip the macOS/Windows signing record for the unsigned Linux build."""
    text = path.read_text(encoding="utf-8")
    if "releaseRecordPath !== undefined" in text:
        return
    pattern = (
        r"(  const buildPaths = desktopTargetBuildPaths\(target\.name(?:, environment)?\)\n)"
        r"  const releaseRecordPath = join\(buildPaths\.artifacts, desktopBuildRecordFilename\(target\.name\)\)\n"
        r"  if \(!invocation\.prepareOnly && !invocation\.unsigned && !invocation\.skipNotarization\) \{\n"
    )
    replacement = (
        r"\1"
        "  const releaseRecordPath = target.name === 'linux-x64'\n"
        "    ? undefined\n"
        "    : join(buildPaths.artifacts, desktopBuildRecordFilename(target.name))\n"
        "  if (releaseRecordPath !== undefined && !invocation.prepareOnly && !invocation.unsigned && !invocation.skipNotarization) {\n"
    )
    text, count = re.subn(pattern, replacement, text)
    if count != 1:
        die(f"{path.name}: packageTarget release-record block not recognised ({count} matches)")
    path.write_text(text, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        die("usage: linux-target-fixups.py <upstream-dir>")
    root = Path(sys.argv[1]) / "apps" / "desktop" / "scripts"
    declaration = root / "desktop-build-paths.d.mts"
    implementation = root / "desktop-build-paths.mjs"
    for path in (declaration, implementation):
        if not path.is_file():
            die(f"{path} is missing; the upstream layout changed")

    widen_declaration(declaration)
    widen_implementation(implementation)
    add_linux_package_environment(root / "desktop-package-environment.mjs")
    guard_linux_release_record(root / "package-target.ts")

    for path, needle in (
        (declaration, WIDE_PLATFORM),
        (implementation, WIDE_UNION),
        (root / "desktop-package-environment.mjs", "localLinuxPackageEnvironment"),
        (root / "package-target.ts", "releaseRecordPath !== undefined"),
    ):
        if needle not in path.read_text(encoding="utf-8"):
            die(f"{path.name}: widening did not land")
    print("linux-target-fixups: desktop build paths accept linux-x64")


if __name__ == "__main__":
    main()
