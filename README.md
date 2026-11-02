# DeepSeek Harness — Linux AppImage

Unofficial Linux x86_64 builds of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

DeepSeek ships desktop apps for macOS and Windows but no Linux build. This
repository rebuilds every upstream desktop release — alpha, beta, release
candidate and final alike — as an AppImage, so a Linux build exists for each
version upstream publishes. The result is unsigned and not supported by
DeepSeek, and it does not update itself.

## Requirements

- 64-bit Linux (x86_64) with a running graphical desktop, X11 or Wayland.
- FUSE 2 to mount AppImages. Most distributions include it; on Fedora install
  `fuse-libs`, on Debian/Ubuntu `libfuse2` or `libfuse2t64`.
- Network access to your model provider and whatever credentials it requires.
- At least 1 GB of free disk space; 8 GB of RAM is recommended for larger
  sessions.

Tested and working on **Fedora 44 KDE Plasma**.

## Download

Grab the newest AppImage and its checksum from
[Releases](https://github.com/kvnis/deepseek-harness-builds/releases):

```sh
sha256sum -c deepseek-harness-*.AppImage.sha256
chmod +x deepseek-harness-*.AppImage
./deepseek-harness-*.AppImage
```

If Chromium's sandbox refuses to start, run it with `--no-sandbox`.

The release marked **Latest** is the newest release-candidate or final build.
Alpha and beta builds are marked as pre-releases; open a specific release page
to get that exact version.

## Updating

Nothing in the AppImage points at this repository, so it never checks for or
installs a new version on its own. Updating is a download: get the AppImage of a
newer release and replace the one you have, or open the new file in Gear Lever
and integrate it.

Your settings, sessions and installed plugins live in `~/.dsh`, outside the
AppImage, so replacing the file leaves them untouched. Keep the old AppImage if
you want to fall back without downloading it again.

This repository checks `deepseek-ai/deepseek-harness` every six hours and builds
each release published since it started tracking, so a new upstream version
usually has a build within six hours of its release.

## Quitting and reloading

Closing the window does **not** quit. The window hides, the page and its Host
process keep running, and the Linux build has no tray icon to bring it back — so
the app looks gone while it still holds the profile. Launching the AppImage
again does not start a second copy either: it re-shows the instance already
running.

- **Quit:** menu **Application → Quit**.
- **Reload the page:** menu **Application → Reload Page** (`Ctrl+R`). Use it
  after installing a plugin, and whenever the UI looks wrong afterwards: the
  page keeps the code it loaded at start, so an error it showed earlier can stay
  on screen after the cause is gone. Plugins installed with the dshmarket plugin
  may need a reload, or a quit and restart, before they work.

If the menu has no reload item, the build predates it: quit and start the
AppImage again instead.

## Optional: Gear Lever

[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) adds the AppImage to
your menu, extracts its icon and metadata, and keeps older versions around.
It is optional: `chmod +x` and running the file works too.

```sh
flatpak install flathub it.mijorus.gearlever
```

Open the AppImage in Gear Lever and choose **Integrate**.

These builds carry no update source, so Gear Lever will not offer updates for
them. To have it check this repository for you, add the source by hand: choose
**GitHub**, enter repository `kvnis/deepseek-harness-builds` and release file
`deepseek-harness-*-linux-x86_64-unsigned.AppImage`, with **Allow pre-releases**
enabled. Gear Lever then reports a new release when you ask it to, and installs
it only when you confirm.

That source is optional. Adding it is the one way an integrated copy ever gets
updated for you; leave it out and updates stay a manual download.

## What is included

- The upstream Electron desktop app and web UI.
- A bundled Node runtime and the full harness package set.
- Terminal, image processing, and LibreOffice-based document conversion.

## Caveats

- **Unofficial and unsigned.** The AppImage has no code signature, so your
  desktop may warn on first launch.
- **Linux x86_64 only.**
- **No updates of any kind.** **Application → Check for Updates…** fails, and
  nothing in the file points at this repository, so the app never checks for or
  installs a new version. Updating is a download; see [Updating](#updating).
- **Prereleases.** Most upstream releases are alphas and release candidates, and
  each one gets a build here. Alpha and beta builds are marked pre-release; the
  newest release-candidate or final build is marked Latest.
- **Lower version numbers are possible.** When upstream publishes a hotfix on an
  older release line after a newer preview, the newest build can carry a lower
  version number than the one you have. Nothing reorders them for you, so go by
  the release date rather than the version.

## Disclaimer

This is an unofficial community project, not affiliated with or endorsed by
DeepSeek. DeepSeek, DeepSeek Harness, and the whale logo are trademarks of
their respective owners.

## License

DeepSeek Harness is MIT licensed. See [LICENSE](LICENSE). The packaging patch in
this repository is provided under the same license.

## Links

- [Upstream repository](https://github.com/deepseek-ai/deepseek-harness)
- [Product page](https://deepseek.com/harness)
- [Maintainer notes](MAINTAINING.md)
