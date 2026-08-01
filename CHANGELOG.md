# Changelog

All notable changes to HDRHeic. Versions follow `MAJOR.MINOR`.

## 1.6

- **Update check.** On launch the app asks GitHub for the latest release and
  shows a banner with a download link when a newer version exists.
- **First-run onboarding.** If the watched folder doesn't exist yet, a welcome
  sheet offers a folder picker instead of silently watching nothing.
- **Failures are visible.** A *Problems* section lists conversions that failed
  (and JPEGs that could not be moved to the Trash), with a *Clear* button.
- **Batch progress.** *Convert now* shows an `i / n` progress bar, driven by a
  new `hdrheic scan --progress` machine-readable output mode.
- **Hungarian localization.** The interface follows the system language.
- **Watcher robustness.** If the background watcher points at an old/moved copy
  of the app, a banner offers a one-click *Repair*; the CLI symlink also
  re-points itself automatically.
- **Convert now in the menu bar.** Run a pass without opening the window.
- Added `LICENSE` (MIT), this changelog, and a GitHub Actions release workflow.

## 1.5

- Menu-bar icon rewritten with AppKit `NSStatusItem` (the SwiftUI
  `MenuBarExtra` did not reliably appear).
- Double-clicking the app in Finder/Launchpad reopens the window — a reliable
  way in when the menu-bar icon is hidden by a crowded or notched menu bar.

## 1.4

- Runs as a menu-bar app: no Dock icon.
- Installs the `hdrheic` command-line tool into `~/.local/bin` on first launch,
  with a toggle in the window.
- DMG installer with drag-to-Applications.

## 1.3

- Option to move the source JPEG to the Trash after a successful conversion
  (default on, recoverable).

## 1.2

- App icon.
- *Redo* policy — Never / Newer / Always (default Newer): re-convert when the
  JPEG is newer than its HEIC.
- Downloads page published with GitHub Pages.

## 1.1

- Native SwiftUI control panel: settings, green/red watcher status light and a
  log viewer, replacing the AppleScript menu.

## 1.0

- Converts HDR JPEGs (Display P3 + gain map) to 10-bit Display P3 HEIC that
  keeps the gain map (`tmap`), matching Preview's *HEIF 10-bit Maximum* export.
- Background folder watcher with a debounce delay, so a file is never picked up
  while it is still being written.
- Skips non-HDR JPEGs and never overwrites an existing HEIC.
