# DeepSeek Harness — Linux AppImage

Unofficial Linux x86_64 builds of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

DeepSeek ships desktop apps for macOS and Windows but no Linux build. This
repository rebuilds the upstream desktop app as an AppImage whenever upstream
publishes a release. The result is unsigned and not supported by DeepSeek.

## Requirements

- 64-bit Linux (x86_64) with a running graphical desktop, X11 or Wayland.
- FUSE 2 to mount AppImages. Most distributions include it; on Fedora install
  `fuse-libs`, on Debian/Ubuntu `libfuse2` or `libfuse2t64`. Gear Lever is an
  alternative way to manage and launch the file.
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

## Gear Lever

[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) is the recommended
way to install and update the AppImage. It adds the app to your menu, extracts
its icon and metadata, keeps older versions, and reads the update source
embedded in the file.

```sh
flatpak install flathub it.mijorus.gearlever
```

Open the AppImage in Gear Lever and choose **Integrate**. Update checks use this
repository's releases, including prereleases.

To add the source by hand, choose **GitHub** and enter repository
`kvnis/deepseek-harness-builds`, release file
`deepseek-harness-*-linux-x86_64-unsigned.AppImage`, with **Allow pre-releases**
enabled.

## What is included

- The upstream Electron desktop app and web UI.
- A bundled Node runtime and the full harness package set.
- Terminal, image processing, and LibreOffice-based document conversion.

## Caveats

- **Unofficial and unsigned.** The AppImage has no code signature, so your
  desktop may warn on first launch.
- **Linux x86_64 only.**
- **No in-app updates.** The app's own updater has no feed configured; updates
  come from Gear Lever or a new download.
- **Prereleases.** Upstream currently ships prereleases, and these builds follow
  them.

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
