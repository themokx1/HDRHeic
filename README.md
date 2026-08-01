# HDRHeic

Automatically converts **HDR JPEGs** (Display P3 photos carrying a gain map, e.g.
Lightroom/Camera HDR exports) into **10-bit, maximum-quality HEIC** files that keep
the HDR — the exact same format as macOS Preview's *Export → HEIF → 10-bit → Maximum*
(a `tmap` adaptive-HDR file: SDR base + gain map, so it looks right on both SDR and
HDR displays).

Uses only native Apple frameworks (Core Image / ImageIO) and the hardware HEVC
encoder, so it is fast (~1.5 s per photo) and light on the machine.

## What it does

- Watches `~/Pictures/Exported` (and subfolders) and converts any new HDR JPEG.
- **Debounced:** waits until the folder has been quiet for a few seconds before
  converting, so it never touches a file that is still being written. If more files
  keep appearing, it keeps waiting.
- **Redo policy** for a JPEG that already has a `.heic`/`.heif` sibling:
  *Never* (keep it), *Newer* (re-convert when the JPEG is newer than the HEIC —
  the default), or *Always* (re-convert every time).
- **HDR only:** plain (non-gain-map) JPEGs are skipped.
- Output goes next to the source: `photo.jpg` → `photo.heic`.
- **Delete original** (on by default): after a successful conversion the JPEG is
  moved to the **Trash** (recoverable). Only ever removes a JPEG it just converted.

## The app

`~/Applications/HDRHeic.app` — a small native (SwiftUI) window, all on one page:

- **Settings:** watched folder (with a *Choose…* button), the delay in seconds,
  an *Include subfolders* toggle, the *Redo* policy (Never / Newer / Always), a
  *Move the JPEG to the Trash after converting* toggle, and the `hdrheic` CLI
  toggle. Changes save immediately and restart the watcher if it is running.
- **Background watcher:** a green/red status light (green = running, red = off)
  with a *Turn On / Turn Off* button, plus a *Convert now* button that shows an
  `i / n` progress bar.
- **Recent conversions:** a live list of what was converted and when, plus a
  *Problems* section listing failures (with *Clear*).
- **Banners** for a new version, a missing watch folder, or a watcher pointing at
  an old copy of the app (one-click *Repair*).
- **Hungarian** interface when the system language is Hungarian; a welcome sheet
  asks which folder to watch on first run.

It runs as a **menu-bar app** (no Dock icon): a sun icon with *Convert now*,
*HDRHeic…* and *Quit*. If the menu-bar icon is hidden by a crowded or notched
menu bar, double-click the app in Finder/Launchpad to bring the window back.

## Config

`~/Library/Application Support/HDRHeic/config.json`

```json
{ "debounceSeconds": 5, "deleteSource": true, "recursive": true, "regenerate": "newer", "watchFolder": "~/Pictures/Exported" }
```

Edit via the app's **Settings…**, or by hand. Log: `~/Library/Logs/HDRHeic.log`.

## Background watcher

A launchd LaunchAgent (`~/Library/LaunchAgents/com.zoltanpalotai.hdrheic.plist`)
runs `hdrheic watch` at login and keeps it alive. Install/remove it from the app.

## Rebuild after changing the source

```bash
cd ~/PhpstormProjects/hdrheic-src
./build.sh          # compiles the engine, rebuilds HDRHeic.app, installs to ~/Applications
```

If the watcher is running, remove and re-install it from the app afterwards so it
picks up the new binary.

## Download

Downloads page: **https://themokx1.github.io/HDRHeic/** (GitHub Pages, from `docs/`).
The app ships as a **DMG** (`HDRHeic.dmg`) — open it, drag the app onto the
Applications shortcut. On first launch the app installs the `hdrheic`
command-line tool into `~/.local/bin` (toggleable in the window).

## Cutting a new release

Bump `CFBundleShortVersionString` in `build.sh`, add a `CHANGELOG.md` entry, then:

```bash
git tag -a vX.Y -m "HDRHeic X.Y" && git push origin vX.Y
```

The GitHub Actions workflow (`.github/workflows/release.yml`) builds the app on a
macOS runner and publishes `HDRHeic.dmg` + `HDRHeic.app.zip` to the release.
The downloads page always links to `releases/latest`, so no page change is needed.

To do it by hand instead:

```bash
./build.sh
cd build && ditto -c -k --keepParent HDRHeic.app HDRHeic.app.zip && cd ..
gh release create vX.Y build/HDRHeic.dmg build/HDRHeic.app.zip --title "HDRHeic X.Y" --notes "…"
```

## Not notarized

The app is ad-hoc signed, so the first launch needs right-click → **Open**.
Removing that step requires an Apple Developer account ($99/year): sign with a
Developer ID certificate + hardened runtime, then `notarytool submit` and
`stapler staple` the DMG.

## Command line (the engine)

`build.sh` symlinks the engine to `~/.local/bin/hdrheic`, so once that's on your
PATH you can just run `hdrheic`. (The real binary lives inside the app at
`~/Applications/HDRHeic.app/Contents/Resources/hdrheic`.)

```
hdrheic scan                 one conversion pass over the configured folder
hdrheic watch                stay resident and convert new HDR JPEGs (debounced)
hdrheic get <key>            watchFolder | debounceSeconds | recursive | regenerate | deleteSource
hdrheic set <key> <value>
hdrheic config-path
hdrheic version
```

## Re-doing an earlier low-quality HEIC

With the *Redo* policy set to **Newer** (default) or **Always**, a photo whose JPEG
is newer than its HEIC is re-converted automatically. With **Never**, an existing
HEIC is always kept — so a poor one next to a photo (e.g. an 8-bit sRGB one from
Finder's Quick Action) is only replaced if you delete that `.heic` and run
**Convert now**, or `touch` the JPEG so it's newer under *Newer*.

## Layout

```
Sources/hdrheic/main.swift     the engine (convert + scan + watch + config)
Sources/HDRHeicApp/App.swift   the SwiftUI control-panel app
build.sh                       build + install
```
