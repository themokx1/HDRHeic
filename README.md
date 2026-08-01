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
- **Never overwrites:** a JPEG that already has a `.heic` (or `.heif`) sibling is
  skipped — no double conversion.
- **HDR only:** plain (non-gain-map) JPEGs are skipped.
- Output goes next to the source: `photo.jpg` → `photo.heic`.

## The app

`~/Applications/HDRHeic.app` — double-click for a small menu:

| Menu item | Action |
|---|---|
| **Convert now** | One pass over the configured folder (on demand). |
| **Settings…** | Choose the watched folder and set the delay (seconds). |
| **Install / Remove background watcher** | Turn the automatic login agent on/off. |
| **Show log** | Open the log in Console. |

## Config

`~/Library/Application Support/HDRHeic/config.json`

```json
{ "debounceSeconds": 5, "recursive": true, "watchFolder": "~/Pictures/Exported" }
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

## Command line (the engine)

`~/Applications/HDRHeic.app/Contents/Resources/hdrheic`

```
hdrheic scan                 one conversion pass over the configured folder
hdrheic watch                stay resident and convert new HDR JPEGs (debounced)
hdrheic get <key>            watchFolder | debounceSeconds | recursive
hdrheic set <key> <value>
hdrheic config-path
hdrheic version
```

## Re-doing an earlier low-quality HEIC

Because existing `.heic` files are never overwritten, a photo that already has a
poor HEIC next to it (e.g. an 8-bit sRGB one from Finder's Quick Action) is skipped.
To regenerate it: delete that `.heic` and run **Convert now** (or just re-drop the
JPEG while the watcher is on).

## Layout

```
Sources/hdrheic/main.swift   the engine (convert + scan + watch + config)
app/HDRHeic.applescript      the control-panel app
build.sh                     build + install
```
