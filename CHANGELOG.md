# Version History

This file is generated from the in-app ReleaseHistory.json; version, build number and content match the in-app records.

## 1.2.0 (Build 3) · 2026-10-23

Clearer scrolling capture and status panel

Makes scroll direction, seam recovery and menu state easier to understand, and streamlines the annotation tools.

- Scrolling capture gains two auto-capture buttons (up and down) that extend the stitch from the current position in both directions without repeating content.
- Brief alignment failures retry first; persistent mismatch keeps the successful frames side by side and offers "Help me rejoin" to find the overlap in small steps.
- Left-clicking the menu bar icon starts a capture directly; right-click opens a grouped panel with common actions, shortcuts and actual permission states.
- Removed the pen, highlighter and stroke-width controls; rectangle, ellipse, arrow, line, mosaic, text and number badges remain.

Usage notes:

- Auto-capture and "Help me rejoin" need Accessibility permission; manual scrolling still works without it.
- Page jumps, repeating textures or large animated areas may still fail to align; if the stitch cannot be recovered you can save what was captured.

## 1.1.0 (Build 2) · 2026-10-18

First version history

Starts a clear record for every update, with a lighter native interface and a re-implemented scrolling capture.

- New online update check: one click from the status bar menu, app menu or settings; detects GitHub Releases or a custom source automatically, with PAT-token support for private repos; new versions show a native dialog with release notes and direct download.
- Menus and settings show version and build numbers; a new About & Updates page shows the version history any time.
- New versions show their release notes on first launch, then reopen from the menu.
- Settings move to a sidebar layout; Image Beautifier gains light/dark appearance, background palettes and continuous composition controls.
- Scrolling capture now uses async frame grabbing with background incremental stitching, supporting manual review then continue, fixed header/footer detection and mismatch hints.
- Improved copy, save-as, recording save states and floating thumbnail feedback to avoid state conflicts from repeated actions.
- Installation cleans up old build copies and standalone preview bundles, keeping only the official app in /Applications.

Usage notes:

- This is the first formally recorded version; the earlier 1.0.0 (build 1) kept no changelog.
- Screenshots and scrolling capture need Screen Recording permission; auto-scroll and cross-app control keys need Accessibility permission.
- Repeating textures, videos or large animated areas may not align reliably; when prompted, scroll back a section and scroll slowly.
