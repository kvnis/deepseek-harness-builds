# Maintaining the builds

The public surface is [README.md](README.md); this file is for whoever maintains
the automation.

## Automation

`.github/workflows/build.yml` runs every six hours and on `workflow_dispatch`.

1. `resolve` reads the newest non-draft release from upstream and stops if this
   repository already has a release for that tag. `force=true` rebuilds and
   replaces it.
2. `build` checks out the tag, applies `patches/0001-linux-appimage.patch`,
   installs dependencies, and runs
   `pnpm --filter @deepseek-ai/dsh-desktop run package:linux:x64:unsigned`.
3. The AppImage is launched under Xvfb; the job fails unless it prints its
   `dsh web: http://127.0.0.1…` URL.
4. `.upd_info` is checked for
   `gh-releases-zsync|kvnis|deepseek-harness-builds|latest-pre|…`.
5. The asset and `.sha256` are created or replaced on the release.

Manual runs:

```sh
gh workflow run build.yml -R kvnis/deepseek-harness-builds
gh workflow run build.yml -R kvnis/deepseek-harness-builds -f tag=dsh-v0.2.1-rc.3 -f force=true
```

## The patch

Upstream supports only `mac-arm64`, `mac-x64`, and `win-x64`. The patch adds an
unsigned `linux-x64` target and works around three Linux-only problems:

- **sharp:** Electron leaks GLib symbols, which crashes the native libvips
  prebuild. The patch ships `@img/sharp-wasm32` and removes the native Linux
  prebuilds.
- **LibreOfficeKit:** its engine probe mistakes asar's `null` from `lstatSync`
  for an installed package. The patch makes the probe null-safe so it falls back
  to the WASM engine.
- **Desktop identity:** the icon, `StartupWMClass`, and `desktopName` are aligned
  so the running window matches the launcher.

It also disables release policy, update feeds, and release records for the local
unsigned target and writes the Gear Lever update source into `.upd_info`.

## Rebuilding the patch

Upstream is pre-stable. If "Apply Linux patch" fails on a new tag:

```sh
git clone --depth 1 --branch <tag> https://github.com/deepseek-ai/deepseek-harness.git work
cd work
git apply --3way /path/to/patches/0001-linux-appimage.patch
# resolve conflicts, then
git add -A
git diff --cached --binary > /path/to/patches/0001-linux-appimage.patch
```

Check it against a clean tree before pushing:

```sh
git apply --check patches/0001-linux-appimage.patch
```

## Visibility

Gear Lever's GitHub updater is unauthenticated. While this repository is
private, Gear Lever cannot check for updates; download builds with
`gh release download`. Make the repository public before advertising Gear
Lever updates.
