# SnapScreen

A native macOS app for screenshots, scrolling long screenshots, and screen recording with system audio.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Author](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)

**English** · [简体中文](README.zh-CN.md)

**SnapScreen** is a modern, lightweight, native menu-bar app that covers the whole screenshot workflow on macOS: region capture with annotation, scrolling long screenshots, pin-to-screen images, an image beautification studio, and screen recording with system audio. It is built with Swift 6, AppKit, SwiftUI, and ScreenCaptureKit, and ships with zero third-party closed-source dependencies.

## Features

### Region Capture

- **Smart window snapping** — press `⌃A` (Control + A) or click the menu bar icon to start. Hovering highlights window boundaries automatically (via `CGWindowListCopyWindowInfo`); a single click selects that window, or drag freely to draw any rectangle.
- **Magnifier and color picker** — before a selection is made, a magnifier follows the cursor with a 4x Retina pixel grid, center crosshair, RGB hex color value (e.g. `#3B82F6`), and precise coordinates and size.
- **Vector annotation toolbar** — rectangle (`1`), circle (`2`), arrow (`3`), line, mosaic / Gaussian blur (`6`), text box (`7`) with background bubble and auto-sizing, auto-incrementing number badges (`8`) for step-by-step instructions, and a preset color palette. Shape annotations use a fixed stroke width for a clean look.
- **Tooltip bubbles** — resting the cursor on a toolbar button shows a floating tooltip with the tool name and its shortcut badge (e.g. `Rectangle [1]`, `Studio [E]`, `Finish & Copy [Enter]`); the bubble glides smoothly between buttons, passes clicks through completely, and respects the system Reduce Motion setting.
- **Fast completion** — `Enter` or double-click finishes and copies to the clipboard; `Cmd + S` saves to your Downloads folder (with a system notification offering "Show in Finder"); `Cmd + Z` undoes the last annotation; `Esc` or a right-click outside cancels.

### Scrolling Long Screenshot

- **Start anywhere** — press `⌥S` (Option + S) or click "Long Screenshot" in the capture toolbar after making a selection.
- **Live capture** — frames are read asynchronously with ScreenCaptureKit, and the control panel and border are excluded from the captured content; capture and stitching never block the main thread.
- **Scroll modes** — scroll manually with a trackpad or mouse wheel. With the Accessibility permission granted, dedicated "Capture Up" and "Capture Down" buttons complete the page in both directions from the current position; content you scroll back to review is never stitched twice.
- **Seam recovery** — a transient registration failure retries automatically; if the mismatch persists, the last successful frame is kept as a reference and a "Help me rejoin" button nudges in small steps to find a stitchable position again. Without the Accessibility permission, the tool follows the on-screen prompt back in small steps and resumes manual capture once aligned.
- **Reliable stitching** — vertical alignment is computed from multi-row, multi-column RGB features with a confidence threshold, so a mismatch is never mistaken for reaching the bottom. Repeated headers and footers are kept only once when there is enough evidence; moving windows, size changes, or unreliable alignment produce a clear notice instead of a broken image.
- **Bounded memory, clean finish** — only the first screen, incremental strips, and a few working frames are kept in memory, with a ~40 MP safety cap. The final image is composed exactly once at the end, written atomically in the background as a uniquely named PNG, copied to the clipboard per your preference, and only then announced with a notification. Cancelling discards the session's data.

### Screen Recording with System Audio

- **One-key start** — press `⌃[` (Control + `[`) to start; press it again to stop.
- **System audio without drivers** — built directly on ScreenCaptureKit with `capturesAudio = true`, capturing everything your Mac's speakers play as 48 kHz stereo PCM. No Soundflower/BlackHole-style virtual audio drivers to install.
- **High-quality encoding** — `AVAssetWriter` outputs 60 FPS H.264 video with AAC audio.
- **Floating control panel** — a live recording timer, status dot, real system-audio state, and a stop button; the timer freezes and shows "Saving" while the file is written. Pause is not offered.
- **Done notification** — recordings are saved automatically to `~/Downloads`, the file path is copied to the clipboard, and a notification confirms completion.

### Pin to Screen

- **Always on top** — press `⌥P` (Option + P) or click `Pin` in the capture toolbar to float a screenshot above everything, at the highest system window level.
- **Drag and zoom** — move the pinned image anywhere; use the scroll wheel to resize it.
- **Right-click menu** — copy, save as, and adjust opacity (100%, 80%, 50%, 30%); double-click closes the pin.

### Screenshot Studio and Mockups

- **Three ways in** — press `E` (or the Studio button) while annotating a fresh capture, click the Studio button on the post-capture floating thumbnail, or press `⌥E` (Option + E) anytime to load the clipboard image or pick a local file from the menu bar.
- **Window frames** — macOS light window with native Retina traffic lights and a subtle metallic body; macOS dark window with a deep title bar and high-contrast traffic lights; a modern browser frame with a Safari/Chrome-style minimal address bar (padlock icon and simulated domain, back/forward/reload buttons); or frameless to keep just the image.
- **Backgrounds and smart blur** — a smart Gaussian blur upscales and blurs the screenshot itself so the background matches the subject perfectly; curated gradient wallpapers (Sunrise Dawn, Aurora Borealis, Sunset Glow, Ocean Deep, Titanium Dark); elegant solid colors; and a checkerboard transparent background for PNG export.
- **Composition controls** — outer margin 0–100 px, window corner radius 0–40 px, and three shadow levels (none, soft, deep), all adjustable smoothly and losslessly.
- **Social aspect ratios** — one click to match Auto, 1:1 square, 4:3 classic, 16:9 landscape, 9:16 mobile portrait, or 3:4 portrait layouts.
- **Instant delivery** — `Enter` copies the finished image to the clipboard, `Cmd + S` saves a high-resolution PNG, and `⌥P` pins the result to the desktop for side-by-side comparison.

### Native App Experience

- **Menu bar control** — left-click the menu bar icon to capture immediately; right-click opens a status panel that gathers common actions with their shortcuts, plus live permission and recording status; maintenance actions live under "More".
- **Native settings** — a sidebar-categorized, scrollable settings window that remembers its size and position.
- **Appearance-aware studio** — the Studio follows the system light/dark appearance with live previews of background swatches, margins, corner radius, and aspect ratio; rapid adjustments coalesce into single render requests so exports never copy a stale preview.
- **Polished thumbnails** — the post-capture floating thumbnail never steals focus, pauses auto-dismiss while hovered, and stays at least 2 seconds after the cursor leaves.
- **Update checker** — check for updates from the status menu, the app menu, or Settings; it detects GitHub Releases or a self-hosted feed (with PAT token support for private repositories), and a native dialog shows the release notes with a direct download.
- **Changelog viewer** — the "Release Notes…" menu and Settings → About & Update show the actually installed version and build time; the first launch of a new version presents its release notes, reopenable from the menu at any time.

## Keyboard Shortcuts

| Action | Shortcut | Notes |
| :--- | :--- | :--- |
| Region screenshot | `⌃A` (Control + A) | Window snapping / free selection |
| Scrolling long screenshot | `⌥S` (Option + S) | Auto / manual scroll stitching |
| Image Studio | `⌥E` (Option + E) | Load clipboard image or local file |
| Enter Studio from selection | `E` | While a selection is active |
| Screen recording | `⌃[` (Control + `[`) | With system audio; press again to stop |
| Pin image | `⌥P` (Option + P) | Floating always-on-top image |
| Annotation tools | `1` `2` `3` `6` `7` `8` | 1 rectangle, 2 circle, 3 arrow, 6 mosaic, 7 text, 8 number badge; line from the toolbar |
| Copy and finish | `Enter` / double-click inside selection | Copies to clipboard |
| Save to file | `Cmd + S` | Saves to the default directory |
| Undo last annotation | `Cmd + Z` | Removes the last shape |
| Exit / cancel | `Esc` / right-click outside | Exits capture immediately |

## Download and Install

1. Download the latest DMG from [GitHub Releases](https://github.com/cduyzh/SnapScreen/releases).
2. Open the DMG and drag the app into your **Applications** folder.
3. Launch the app. On first use, grant **Screen Recording** permission (System Settings → Privacy & Security); optionally grant **Accessibility** for automatic scrolling in long screenshots, and **Microphone** if you want to record your voice.

## Build from Source

Requires macOS 14+ and Xcode or the Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/cduyzh/SnapScreen.git
cd SnapScreen
./build_app.sh
```

## Version History

Current version: **1.2.0 (Build 3)**, released 2026-10-23. See the full history in [CHANGELOG.md](CHANGELOG.md).

## Privacy

Everything you capture or record stays on your Mac. Copying writes only to the clipboard (plus an optional temporary file); permanent files are written only when you explicitly save. The only network access is the optional update check against GitHub Releases or a feed you configure — no analytics, no telemetry, and zero third-party closed-source dependencies. The app requests only the permissions its features need: Screen Recording (screenshots, long screenshots, recording), Accessibility (automatic scrolling), and optionally Microphone (voice recording).

## License

Released under the [MIT License](LICENSE).

## Author

**cduyzh**

- GitHub: <https://github.com/cduyzh>
- Website: <https://www.cduyzh.top>
- Goal: <https://www.cduyzh.top/goal>
