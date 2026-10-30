#!/usr/bin/env bash
# Apply patches/0001-linux-appimage.patch to a checkout of an upstream release tag.
#
# Strict `git apply` first. Upstream occasionally moves the context lines the
# hunks are anchored on without changing the intent (that is what broke every
# scheduled run between 2026-10-28 and 2026-10-30). When strict apply refuses,
# retry with `patch --fuzz=2`, then verify the result before anyone builds on it:
#
#   * every file the patch creates exists,
#   * every line the patch adds is present in the patched tree,
#   * no .rej files and no conflict markers were left behind.
#
# A fuzz apply that lands in the wrong place still fails the build instead of
# shipping a wrong AppImage. Verification is the whole point of the fallback.
#
# Usage: scripts/apply-linux-patch.sh [upstream-dir] [patch-file]
#        scripts/apply-linux-patch.sh --verify [upstream-dir] [patch-file]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

verify_only=false
if [[ ${1:-} == --verify ]]; then
  verify_only=true
  shift
fi

upstream=${1:-upstream}
patch_file=${2:-$root/patches/0001-linux-appimage.patch}

[[ -d $upstream ]] || { echo "apply-linux-patch: no such directory: $upstream" >&2; exit 1; }
[[ -f $patch_file ]] || { echo "apply-linux-patch: no such patch: $patch_file" >&2; exit 1; }
patch_file=$(cd "$(dirname "$patch_file")" && pwd)/$(basename "$patch_file")

# The fuzz retry has to reset the worktree, so a dirty checkout would lose work
# silently. Refuse instead: the workflow always patches a fresh clone.
if [[ $verify_only == false ]] && { ! git -C "$upstream" diff --quiet || ! git -C "$upstream" diff --cached --quiet; }; then
  echo "apply-linux-patch: refusing to patch a checkout with local changes in $upstream" >&2
  exit 1
fi

verify() {
  python3 - "$upstream" "$patch_file" <<'PY'
import os
import sys

upstream, patch = sys.argv[1], sys.argv[2]

current = None
created = set()
added = {}
pending_create = False


def target_of(raw, marker):
    path = raw[len(marker):].rstrip("\n")
    if path == "/dev/null":
        return "/dev/null"
    return path[2:] if path.startswith("b/") or path.startswith("a/") else path


with open(patch, encoding="utf-8", errors="surrogateescape") as handle:
    for raw in handle:
        if raw.startswith("diff --git "):
            current = None
            pending_create = False
        elif raw.startswith("--- "):
            pending_create = target_of(raw, "--- ") == "/dev/null"
        elif raw.startswith("+++ "):
            current = target_of(raw, "+++ ")
            if current == "/dev/null":
                current = None
            else:
                added.setdefault(current, [])
                if pending_create:
                    created.add(current)
        elif current and raw.startswith("+") and not raw.startswith("+++"):
            added[current].append(raw[1:].rstrip("\n"))

problems = []

for name, lines in sorted(added.items()):
    path = os.path.join(upstream, name)
    if name in created and not os.path.isfile(path):
        problems.append(f"{name}: created by the patch but missing")
        continue
    if not os.path.isfile(path):
        problems.append(f"{name}: missing")
        continue
    with open(path, encoding="utf-8", errors="surrogateescape") as handle:
        text = handle.read()
    if "<<<<<<<" in text or ">>>>>>>" in text:
        problems.append(f"{name}: conflict markers left behind")
    for line in lines:
        if not line.strip():
            continue
        if line not in text:
            problems.append(f"{name}: patched line missing: {line.strip()[:100]}")
            break

for base, _, names in os.walk(upstream):
    if "/.git" in base:
        continue
    for name in names:
        if name.endswith(".rej"):
            problems.append(os.path.join(base, name) + ": rejected hunk left behind")

if problems:
    print("apply-linux-patch: verification failed", file=sys.stderr)
    for problem in problems:
        print("  " + problem, file=sys.stderr)
    sys.exit(1)

print(f"apply-linux-patch: verified {len(added)} patched files")
PY
}

report() {
  local mode=$1
  echo "apply-linux-patch: patch applied with $mode"
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    echo "Linux patch applied with **$mode**." >> "$GITHUB_STEP_SUMMARY"
  fi
}

if [[ $verify_only == true ]]; then
  verify
  report "verify-only"
  exit 0
fi

if git -C "$upstream" apply --verbose "$patch_file"; then
  verify
  report strict
  exit 0
fi

echo "apply-linux-patch: strict apply failed, retrying with fuzz" >&2
git -C "$upstream" reset --quiet --hard
git -C "$upstream" clean -fdq

dry_run=$(cd "$upstream" && patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch --dry-run < "$patch_file" 2>&1) || {
  printf '%s\n' "$dry_run" >&2
  echo "apply-linux-patch: fuzz dry run failed; the patch needs updating" >&2
  exit 1
}
printf '%s\n' "$dry_run"

(cd "$upstream" && patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch < "$patch_file")

verify
report "fuzz"

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  echo "Upstream moved context lines; the patch landed with fuzz offsets. Check the release notes before trusting the artifact." >> "$GITHUB_STEP_SUMMARY"
fi
