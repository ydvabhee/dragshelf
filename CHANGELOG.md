# Changelog

All notable changes to DragShelf are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Pet: Mochi appears whenever DragShelf shows (empty shelf too, about a second after) and tells every tip in her speech bubble; with the pet on, no tip appears in the footer (the sponsor line stays). A tip waits while she is out for a drag.
- Pet intro: the first time the cat appears it says "Meet Mochi 🐱, your shelf pet" and stays until you click anywhere on DragShelf (the click still works as usual); tips follow. Settings → Reset Tips shows it again. A click anywhere also hides a tip bubble without marking it learned.
- Pet intro: the first time the cat appears it says "Meet Mochi 🐱, your shelf pet" and stays until you click anywhere on DragShelf (the click still works as usual); tips follow. Settings → Reset Tips shows it again. A click anywhere also hides a tip bubble without marking it learned.
- Shelf pet (trial, off by default): turn on Settings → Pet → "Show pet" and a soft clay cat ("Mochi", renameable) lives on the bottom edge of DragShelf, over the shelf itself (no extra band). It is mostly asleep and notices your pointer in its own way: it may ignore it, watch it, walk over, crouch and jump up at it, bat at it, lean into a head rub or a slow stroke along its back, and purr when you stroke it. Double-click it or empty shelf space to call it over. It often brings its own yarn ball (Settings → Pet → "Play with ball" starts a game now), plays and pushes it off the edge, walks under each new item to sniff it and bat it so it wiggles, and plays with the tiles on screen now and then (most of all Curious, the default; a Mischievous cat may knock one and look away innocently; items never change), runs out of the shelf while you drag and walks back in a second after. While the cat is on DragShelf it tells tips in a soft speech bubble instead of the footer line, acting them out (points up at the clock for Recent, taps a paw for ⌘V, waves for the shortcut); click the bubble once you've got it. New tips for ⌘V paste, pinning and ⌘F search. Click to pet, right-click to send it home. Personalities: Playful, Lazy, Curious, Shy, Mischievous, Surprise me. Reduce Motion keeps it still.
- Search and filter: press ⌘F or click the magnifying glass to search DragShelf by name, link, or text (case and accents don't matter), and pick All, Files, Folders, Images, Links, Text, or Pinned from the filter menu. The header shows "3 of 12"; Drag All, Clear, ⌘A, arrows, Quick Look and ⌘C act on the shown items. Esc clears the search, and it resets when DragShelf hides.
- Pin items: right-click an item and choose "Pin" to keep it on DragShelf. Pinned items sit first with a small pin badge, stay after Clear and drag out, and come back after you quit. Pinned files are always copied out (⌘ does not move them); "Unpin" puts the item back to normal.
- Text and .txt: drag a text item into a text field to insert the text, or onto Finder or the Desktop to get a real "<first line>.txt" file (the app you drop on decides). Right-click a text item for "Save as .txt", or a plain-text file (up to 1 MB) for "Use as Text".
- Paste: press ⌘V on DragShelf, right-click empty space and choose Paste, or use "Paste to DragShelf" in the menu bar to add what is on your clipboard (files, links, text, images) like a drop. "Nothing to paste" shows when there is nothing usable.
- Custom shortcut: Settings → General has a shortcut field. Click it and type a new shortcut (it needs ⌘, ⌃, or ⌥); Esc cancels, Delete or ✕ turns the shortcut off, and "Reset to ⌃⌥⌘D" brings back the default. A shortcut another app already uses is refused and the old one keeps working. The menu bar menu and tips show the current shortcut.
- Custom resize: Resize ▸ Custom… opens a size form right in DragShelf (Pixels or Percent, width and height, a link button to keep the aspect ratio). Several images each fit inside the size; custom sizes may enlarge, and DragShelf says so. Copies are named like "photo (800×600).jpg"; the originals stay.
- Share and AirDrop: send DragShelf items with "Share…" (any macOS share service) or "AirDrop" from the Actions menu or a tile's context menu. Files, links, and text are shared; missing files are left out. Items stay on DragShelf afterwards.
- Rename: press Return or choose "Rename…" on a file to edit its name right on the tile (Return or a click elsewhere saves, Esc cancels). DragShelf renames its own copy; your original file keeps its name. New items named like one already on DragShelf get a Finder-style number ("Archive 2.zip").
- Convert To and Resize: turn image items into HEIC, JPEG, PNG, or TIFF, or shrink them to 512, 1024, 2048, or 3840 px on the longest edge, from the Actions menu or a tile's context menu. Each image gets a new upright copy (for example "photo.jpg" or "photo (1024px).jpg") without location or camera data; the originals stay. Images are never enlarged, and Cancel keeps the ones already done.
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
- Settings: the global shortcut recorder now reliably captures keys (it brings Settings forward first), and shows the modifiers you hold while recording.
- Pinned items: a Recent drag of a pinned item no longer shows "Missing" after you unpin or rename it, leftover copies of pinned files are cleaned up at launch, and a damaged pin list keeps every backup instead of overwriting the first.
- Rename and Compress: names that differ only in accents (typed vs. decomposed) or case now get the Finder-style number instead of colliding, and control characters or a name made too long by that number are rejected.
- Convert To and Resize: one damaged image no longer cancels the whole batch; the rest are converted and DragShelf says how many couldn’t be.
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
