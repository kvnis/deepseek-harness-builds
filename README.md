# DeepSeek Harness — unofficial builds

Unofficial, automated builds of
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

The repository is named for all future targets rather than today's single one.
Currently it produces **Linux x86_64 AppImages**; other formats and platforms
can be added without renaming anything.

DeepSeek does not publish a Linux build. This private repository keeps the Linux
packaging changes as a patch, watches upstream releases (including prereleases),
and publishes a verified AppImage for each new tag.

## How it works

- `.github/workflows/build.yml` runs every six hours and on manual dispatch.
- It reads the newest non-draft release from `deepseek-ai/deepseek-harness`.
- If this repository already has a release with that tag, it exits.
- Otherwise it shallow-clones the tag, applies `patches/0001-linux-appimage.patch`,
  installs dependencies, and runs the Desktop packaging command.
- The resulting AppImage is launched under Xvfb; the job fails unless the app
  prints its local `dsh web: http://127.0.0.1…` URL.
- The AppImage and its SHA-256 file are attached to a private release named
  after the upstream tag.

## Downloading a build

Private release assets need authentication:

```sh
gh release download dsh-v0.2.1-rc.3 -R kvnis/deepseek-harness-builds
chmod +x deepseek-harness-*.AppImage
./deepseek-harness-*.AppImage
```

If Chromium's sandbox refuses to start, add `--no-sandbox`.

### Managing AppImages with Gear Lever

[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) is the recommended
way to manage the AppImage on a desktop. It integrates the file into the
application menu, extracts the icon and metadata, and keeps multiple versions
around instead of leaving an executable in the download folder.

Install it from Flathub (`flatpak install flathub it.mijorus.gearlever`), then
open the downloaded AppImage with Gear Lever and choose **Integrate**.

Gear Lever's automatic update check needs a public download URL. Release assets
in this private repository require GitHub authentication, so updates remain a
manual `gh release download` followed by re-integrating the new file. A public
mirror would be needed for automatic updates.

## Triggering manually

```sh
gh workflow run build.yml -R kvnis/deepseek-harness-builds
# or a specific tag
gh workflow run build.yml -R kvnis/deepseek-harness-builds -f tag=dsh-v0.2.1-rc.3
```

## What the patch changes

Upstream supports `mac-arm64`, `mac-x64` and `win-x64`; Linux is deliberately
unsupported. The patch adds a `linux-x64` unsigned build target and fixes the
two Linux-specific runtime problems found while building it:

- **sharp:** the native Linux libvips prebuild crashes under Electron because
  Electron leaks GLib symbols into its Node process
  ([electron#46323](https://github.com/electron/electron/issues/46323)). The
  patch ships the official `@img/sharp-wasm32` build instead.
- **LibreOfficeKit:** its engine probe treats asar's `null` return from
  `lstatSync` as "installed", so it demands a native Linux engine that does not
  exist. The patch makes the probe use a null-safe check and fall back to the
  bundled WASM engine.

It also disables release policy, update feeds and release records for the local
unsigned Linux target, and teaches the packaging scripts the Linux Electron
binary path, CLI permissions and artifact layout.

## Maintaining the patch

Upstream is pre-stable, so files can move between releases. When a build fails
at "Apply Linux patch", rebase the patch:

```sh
git clone --depth 1 --branch <new-tag> https://github.com/deepseek-ai/deepseek-harness.git work
cd work
git apply --3way /path/to/patches/0001-linux-appimage.patch
# resolve conflicts, then regenerate including new files
git add -N apps/desktop/scripts/linux-sharp.ts apps/desktop/scripts/linux-office-kit.ts
git diff --binary > /path/to/patches/0001-linux-appimage.patch
```

Verify the result applies to a clean tree before pushing:

```sh
git apply --check patches/0001-linux-appimage.patch
```

## Caveats

- Unofficial and **unsigned**. There is no code-signing or notarization step.
- **No in-app updates.** Update feeds are disabled for unsigned builds, and
  private release assets cannot be used by the updater without shipping a
  credential.
- Private-repository Actions minutes count against the account plan. Scheduled
  checks that find no new tag finish in seconds; real builds take tens of
  minutes.
- Upstream is MIT licensed. Its license is reproduced in `LICENSE`; builds
  remain subject to it.

## Upstream

- Repository: <https://github.com/deepseek-ai/deepseek-harness>
- Product page: <https://deepseek.com/harness>
