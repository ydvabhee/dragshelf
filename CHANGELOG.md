# Changelog

All notable changes to DragShelf are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Rename: press Return or choose "Rename…" on a file to edit its name right on the tile (Return or a click elsewhere saves, Esc cancels). DragShelf renames its own copy; your original file keeps its name. New items named like one already on DragShelf get a Finder-style number ("Archive 2.zip").
- Compress: zip DragShelf items from the new Actions menu (⋯) in the header or a tile's context menu. One item becomes "<name>.zip", several become "Archive.zip"; the zip is added and selected, the originals stay. Links and text are skipped. A spinner and Cancel show while it runs.
- App icon: a file card dropping into a tray, on a blue macOS-style squircle.
- Recent drags: the last 5 drag outs sit under a clock button in the DragShelf header; click one to put it back or drag it out again. ⌘Z (or "Undo Drag Out" in the menu bar) restores the latest.
- Tips: a one-line hint under DragShelf now and then (for example "Hold ⌘ while dragging out to move instead of copy"). Each shows up to 3 times; ✕ hides it for good. Settings → Tips turns them off or resets them.

### Changed
- DragShelf opens a bit larger by default (360 pt wide) and always keeps room for the tip line, so it no longer grows when a tip appears. Sizes you set yourself stay as they are; Reset Position gives the new default.
- Temp files are freed while DragShelf runs: unused cache is swept on show and every 30 minutes, Recent entries expire after 24 hours, and the cache stays under 1 GB.
- Header "Clear" is now a text button (no trash icon); the context menu says "Remove from DragShelf". Both leave your files untouched.
- Menu bar icon now matches the app icon (file card dropping into a tray).
- Recent list resets to the grid each time DragShelf shows or receives a drop.
- Menu, header, tooltips and Settings now call the panel "DragShelf" instead of "Shelf" (for example "Show DragShelf", "Clear DragShelf").

### Fixed
- Dropping only items already on DragShelf now switches Recent back to the grid.
- DragShelf no longer quits when you drop a file promise, such as an image dragged from VS Code.
- Dragging a row from Recent no longer removes items from DragShelf.
- Menu bar icon, DragShelf background mask and scroll bar style no longer risk a crash when macOS draws or notifies off the main thread.

## [0.1.0] - 2026-10-23

First public preview. The build is ad-hoc signed and not yet notarized (see README → Install).

### Added
- Floating shelf that appears at the top center of the screen when you start dragging a file, image, link or text. It stays above all windows and never steals focus.
- Drop in files, folders, links, text, browser images, and file promises from Mail and Photos.
- Drag out to copy. Hold ⌘ to move file items. Copy-only apps still receive a copy.
- Multi-select (⌘/⇧-click), Drag All, Quick Look (Space), arrow-key selection, Delete to remove, ⌘C to copy, Esc to hide.
- Global shortcut ⌃⌥⌘D to show or hide the shelf from any app.
- Movable shelf (drag the header) and resizable shelf (drag its edges). Position and size are remembered for each display. Reset Shelf Position restores the defaults.
- Fit-to-content layout that scrolls past about 4.5 rows, with an inset overlay scroll bar.
- Duplicate detection (same file, link or text is kept once; the same image replaces the older copy) with O(1) adds and no item limit.
- Missing-file detection: tiles for deleted files are dimmed and can't be dragged.
- Settings: launch at login, auto-show on drag, global shortcut, keep items after drag out, show other apps from the developer.
- Liquid Glass on macOS 26 with a vibrancy fallback on macOS 14–15. Supports light and dark mode, Reduce Motion, Reduce Transparency, Increase Contrast and VoiceOver.
- An optional one-line "more apps" suggestion, loaded from a static HTTPS feed once a day with no identifiers sent, and a strict domain allowlist.

[Unreleased]: https://github.com/ydvabhee/dragshelf/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ydvabhee/dragshelf/releases/tag/v0.1.0
