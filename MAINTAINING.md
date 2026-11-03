# Maintaining the builds

The public surface is [README.md](README.md); this file is for whoever maintains
the automation.

## Automation

`.github/workflows/build.yml` runs every 15 minutes and on `workflow_dispatch`.
The interval is short because GitHub's scheduler is best-effort: it has delayed
ticks by six hours and dropped them outright, which with a six-hourly cron meant
a published release could sit unbuilt for a day. A tick with nothing to build
costs one ~10s `resolve` job, so frequent polling is cheap.

Polling that often would also retry a build that cannot succeed — a patch
upstream moved out from under — every quarter hour, so a scheduled tick that sees
a failed run from the last hour reports nothing to build and lets the next tick
try again. A manual dispatch ignores that backoff: dispatching is the retry.

1. `resolve` lists upstream's non-draft releases newest first and this
   repository's own releases. The oldest upstream release that already has a
   release here is the anchor: every upstream release published after it that has
   no release here is queued, at most five per run, newest first, and the jobs
   then run oldest first. Anything from before the anchor is history and is
   never built, so a fresh start cannot backfill the whole archive. The rule
   uses dates rather than versions on purpose: upstream publishes hotfixes on
   older lines, and those must still get a build. The dates are publication
   dates, not creation dates, because upstream drafts a release and publishes it
   later; a release drafted before the anchor but published after it would
   otherwise be skipped forever. A release here counts as built only when its
   AppImage is attached, so a release left without assets is rebuilt.
2. `build` runs once per queued tag, one at a time (`max-parallel: 1`), so the
   newest release is created last and GitHub's Latest pointer lands on it. Each
   job checks out the tag and runs `scripts/apply-linux-patch.sh`, which applies
   every `patches/*.patch` in file-name order, each strictly, falls back to
   `patch --fuzz=2` when upstream only moved context lines (replaying the earlier
   patches on the reset checkout), and then verifies that every line each patch
   adds is present and no `.rej` or conflict markers remain. It installs
   dependencies (three attempts, for registry flakiness) and runs
   `pnpm --filter @deepseek-ai/dsh-desktop run package:linux:x64:unsigned`.
3. `DSH_LINUX_APPIMAGE_UPDATE_INFO` is deliberately unset, so `.upd_info` stays
   empty, and the job fails if `gh-releases-zsync` turns up in it anyway. A build
   that pointed at this repository would update itself under users who installed
   plugins, so these artifacts must never carry an update source.
4. The AppImage is launched under Xvfb; the job fails unless it prints its
   `dsh web: http://127.0.0.1…` URL.
5. `zsyncmake` writes `<AppImage>.zsync`; the asset, `.zsync`, and `.sha256` are
   created or replaced on the release. Alpha and beta tags are published as
   pre-releases, rc and final tags as normal releases.
6. `resolve` also picks the newest upstream release that this rule publishes as
   a normal release, and only that tag is marked Latest. The marker is passed
   explicitly (`--latest=true`/`--latest=false`) rather than left to GitHub's
   automatic rule, because a backfilled release is created today and would
   otherwise take Latest from a newer build. Both flags are declarative on
   rebuilds, so a release published under the old always-prerelease rule is
   corrected by rebuilding it with `force=true`.

When nothing is newer than the anchor, `resolve` emits `count=0` and the `build`
job is skipped; the matrix carries a `["none"]` sentinel so it is never empty.

Manual runs:

```sh
# everything missing since the anchor
gh workflow run build.yml -R kvnis/deepseek-harness-builds
# one named release, rebuilding it if it exists
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
unsigned target. `DSH_LINUX_APPIMAGE_UPDATE_INFO` still writes its value into
`.upd_info` when set, which is useful for a local test build, but CI leaves it
unset: the published AppImages have no update source at all.

## The patches

Both files are separate so that either can be dropped on its own once upstream
stops needing it; nothing else in the build depends on how many there are.

- `patches/0001-linux-appimage.patch` makes the tree package an AppImage:
  Linux target support in the packaging scripts, window and taskbar icon, a
  reload menu item, and the unsigned `package:linux:x64:unsigned` script.
- `patches/0002-desktop-host-cookie-cleanup.patch` deletes the `dsh-auth-*`
  cookies earlier launches left in the Desktop profile before the Host starts,
  which otherwise pile up until the `Cookie` header exceeds the Host's header
  limit and every start fails (see README troubleshooting).

Adding a patch means dropping another `NNNN-name.patch` in `patches/`; the
script picks it up in name order and it applies on top of the ones before it.

## Rebuilding a patch

Upstream is pre-stable. If "Apply Linux patch" fails on a new tag, rebuild only
the patch that reports the failed hunks; it is applied on top of the earlier ones,
so replay them first:

```sh
git clone --depth 1 --branch <tag> https://github.com/deepseek-ai/deepseek-harness.git work
cd work
git apply /path/to/patches/0001-linux-appimage.patch   # every earlier patch, in order
patch -p1 --fuzz=2 --forward --batch --no-backup-if-mismatch \
  < /path/to/patches/NNNN-the-failing-patch.patch
# apply the hunks it reports FAILED by hand, delete the .rej files, then
git add -A
git diff --cached --binary > /path/to/patches/NNNN-the-failing-patch.patch
```

Not `git apply --3way`: a `--depth 1` clone has no blobs from the previous
release, so the preimages the patch names do not exist and the merge has nothing
to work from. Regenerate *before* running `scripts/linux-target-fixups.py`; its
rewrites belong to that script, and folding them into the patch would put fragile
context back in the file the script exists to keep stable.

Check it against a clean tree before pushing. Strict apply must pass — if it only
passes with fuzz, the patch is not ready:

```sh
git reset --hard && git clean -fd
git apply --check patches/0001-linux-appimage.patch
git apply patches/0001-linux-appimage.patch
git apply --check patches/0002-desktop-host-cookie-cleanup.patch
```

A regenerated patch should change only hunk headers and context lines. Compare
added and removed lines per file against the previous patch to confirm nothing
else moved:

```sh
scripts/apply-linux-patch.sh --verify .    # after applying every patch in order
```

Keep the `apps/desktop/package.json` hunks anchored on lines that do not change
between releases. Upstream rewrites `"version"` in every tag, and a hunk that
uses that line as context fails on the next release; the current hunk inserts
`desktopName` after `"name"` instead, so the patch survives version bumps.

## Visibility

Gear Lever's GitHub updater is unauthenticated, so the manual source described in
the README only works while this repository is public; private assets need
`gh release download`.
