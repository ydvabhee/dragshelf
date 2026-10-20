# DragShelf — Product Requirements

Status: draft v1 (2026-10-20). Owner: product-architect. Open questions: `docs/OPEN_QUESTIONS.md`.

## 1. Problem
Dragging a file into an app that is hidden or behind other windows fails. The user must
switch apps mid-drag, wait for focus, and the drag often gets dropped. Workarounds (Cmd-Tab
while dragging, hover over Dock icon, arranging windows first) are slow and fragile.

## 2. Solution
A temporary floating shelf. Start dragging anything: the shelf appears. Drop it on the shelf,
switch to the target app at your own pace, then drag it out of the shelf into the target.

## 3. Target user
- Mac users who move files, images, links, and text between apps many times a day
  (designers, developers, support, writers).
- Uses multiple Spaces, full-screen apps, or many overlapping windows.
- Wants zero setup: no permissions, no account, no configuration.

## 4. Competitors and how we differ
| | Dropover | Yoink | **DragShelf** |
|---|---|---|---|
| Trigger | Shake cursor while dragging (default) | Shelf at screen edge on drag | Shelf appears on **any** content drag, no gesture |
| Shelves | Multiple, stackable | One + history | **One**, no history |
| Extras | Cloud upload, actions, scripts | iOS sync, clipboard history | **None** (do one thing) |
| Permissions | Some features need Accessibility | — | **None required** |
| Price | Paid | Paid | Free, open source (assumed, see OQ-01) |
| Look | Custom | Custom | Native macOS 26 Liquid Glass, HIG-standard |

Our pitch: the simplest native shelf. One shelf, appears by itself, no permissions,
looks and behaves like part of macOS.

## 5. MVP scope
- Shelf appears automatically when a content drag starts. Also opens from menu bar and global hotkey.
- Accepts files, folders, file promises (images from browsers, Mail, Photos), images, links, text.
- Shows items as a grid of thumbnails/icons with names.
- Drag items out one at a time, a selection, or all at once.
- Items are removed after a successful drag out (setting to keep them).
- Remove one item, clear all, Quick Look with Space.
- Menu bar app, no Dock icon. Settings: launch at login, auto-show on/off, shelf position,
  keep items after drag out, hotkey on/off.
- Modern Apple look: Liquid Glass on macOS 26, material fallback on macOS 14–15. SF Symbols,
  system fonts, light/dark, VoiceOver, Reduce Motion, Reduce Transparency.
- One-line "More apps" promo for the developer's other apps, from a remote feed (US-15). Off with one toggle.

## 6. Non-goals (MVP)
- Cloud sync, upload, or share extensions.
- History or persistence across app quit (shelf starts empty each launch).
- Multiple shelves, shelf stacking, named shelves.
- Shake-to-show gesture.
- Custom hotkey recorder (fixed default hotkey, on/off only).
- File actions (rename, convert, compress, AirDrop). Planned for v2, see §10.
- iOS/iPadOS, Mac App Store build, sandbox.
- Drag via VoiceOver (we provide Copy as the keyboard alternative instead).

## 7. Milestones
| ID | Goal |
|---|---|
| M0 | Project skeleton, menu bar item, CLI build/test green |
| M1 | Floating shelf panel, model, drop in (files, text, links, images, promises) |
| M2 | Drag out (single, multi), remove, clear, Quick Look |
| M3 | Auto-show on drag, global hotkey |
| M4 | Settings, accessibility and motion polish |
| M5 | Developer ID signing + notarization (**BLOCKED**: needs user's Developer ID cert) |
| M6 | v2: Shelf Actions (BACKLOG, starts after v1 ships; §10) |

## 8. User stories and acceptance criteria
AC wording is for QA. "Shelf" = the DragShelf floating panel.

### US-1 Auto-show on drag (M3)
As a user, when I start dragging content, the shelf appears so I can drop it without switching apps.
- AC-1: Dragging a file in Finder ≥ 10 pt shows the shelf within 300 ms.
- AC-2: Dragging selected text, a link, or an image from Safari/Chrome shows the shelf.
- AC-3: Dragging a window by its title bar or resizing a window does **not** show the shelf.
- AC-4: If the drag ends without a drop on the shelf and the shelf is empty, the shelf hides within 500 ms.
- AC-5: Shelf appears on the display that contains the cursor.
- AC-6: Showing the shelf does not change the frontmost app or key window.
- AC-7: With "Auto-show on drag" off, drags never show the shelf.
- AC-8: No macOS permission prompt (Accessibility, Input Monitoring, Full Disk Access) appears at any time.

### US-2 Drop content on shelf (M1)
As a user, I drop files, images, links, or text on the shelf and they stay there.
- AC-1: Dropping 1 file, many files, or a folder from Finder adds one item per file/folder, original file untouched.
- AC-2: Dropping an image from Safari, Chrome, Mail, or Photos adds an image file item (not a `.webloc`).
- AC-3: Dropping a link adds a link item showing the URL host/title.
- AC-4: Dropping selected text adds a text item showing the first line.
- AC-5: Dropping the same file twice keeps one item.
- AC-6: Shelf shows a highlighted drop state while a drag hovers over it.
- AC-7: Shelf holds at least 50 items; it scrolls past its max height.

### US-3 Shelf stays while I switch apps (M1)
- AC-1: Shelf stays above normal windows while switching apps with Cmd-Tab, Dock, or Mission Control.
- AC-2: Shelf is visible on every Space and over full-screen apps.
- AC-3: Clicking the shelf does not activate DragShelf or deactivate the current app.

### US-4 Drag one item out (M2)
- AC-1: Dragging a file item into Finder, Mail compose, Slack/Messages, or a browser upload field delivers that file.
- AC-2: Dragging a link item into a browser address bar or text field delivers the URL; into Finder creates a `.webloc`.
- AC-3: Dragging a text item into a text field inserts the text.
- AC-4: The original file on disk is never moved or deleted by a drag out (copy semantics).
- AC-5: After a successful drop the item is removed from the shelf; after a cancelled drag (Esc or drop on nothing) it stays.

### US-5 Drag many items out (M2)
- AC-1: Cmd-click / Shift-click select multiple items; dragging any selected item drags all selected.
- AC-2: A "drag all" handle drags every item in one gesture.
- AC-3: Dropping 5 files into a Finder folder delivers all 5.
- AC-4: Cmd-C copies selected items to the clipboard (keyboard alternative to drag).

### US-6 Manage items (M2)
- AC-1: Hover shows a remove button per item; Delete key and context menu "Remove" remove selected items.
- AC-2: "Clear" removes all items and hides the shelf.
- AC-3: Close button and Esc hide the shelf but keep its items.
- AC-4: The last item leaving the shelf (removed or dragged out) hides the shelf.
- AC-5: A file deleted from disk shows as "missing" (dimmed) and cannot be dragged out.
- AC-6: Cached copies (promised files, dropped image data) are deleted on remove, clear, and quit.

### US-7 Quick Look (M2)
- AC-1: Space with a file item selected opens Quick Look; Space again closes it.
- AC-2: Arrow keys move the selection and Quick Look follows.

### US-8 Open shelf on demand (M3)
- AC-1: Menu bar item has: Show Shelf, Clear Shelf, Settings…, Quit DragShelf.
- AC-2: Global hotkey ⌃⌥⌘D toggles the shelf from any app, without a permission prompt.
- AC-3: App has no Dock icon and no app menu bar when shown.

### US-9 Settings (M4)
- AC-1: Launch at login toggle registers/unregisters the app; state survives relaunch.
- AC-2: Auto-show on drag toggle (default on).
- AC-3: Shelf position: top center by default; user drags the shelf by its header to move it, position remembered per display; "Reset Shelf Position" in Settings and menu. (Picker dropped 2026-10-20, superseded by T-13.)
- AC-4: Keep items after drag out toggle (default off).
- AC-5: Global hotkey toggle (default on).
- AC-6: All settings persist across relaunch.

### US-10 Native look and accessibility (M1–M4)
- AC-1: On macOS 26 the shelf uses Liquid Glass; on macOS 14–15 a translucent material that stays vibrant when the panel is not key.
- AC-2: Correct in light and dark mode, and when the system accent color changes.
- AC-3: Reduce Transparency → opaque background. Reduce Motion → fades instead of springs/scales. Increase Contrast → visible borders.
- AC-4: VoiceOver reads every item ("PDF document, Report.pdf") and every button; items expose Remove and Quick Look actions.
- AC-5: Only SF Symbols and system fonts; all text supports the system text size setting where SwiftUI provides it.

### US-15 Discover the developer's other apps (M4, T-14)
As the developer, I promote my other apps inside DragShelf, and new apps appear without a DragShelf update.
As a user, I see at most one small line, and I can hide it.
- AC-1: When the feed has an eligible promo, the panel shows one footer line (optional SF Symbol, title, secondary subtitle, small ✕) under the grid. It never covers tiles or the drop area.
- AC-2: The footer is hidden while any drag is in progress (auto-show, hovering, or drag out).
- AC-3: Clicking the line opens its `https` URL in the default browser. DragShelf downloads and installs nothing.
- AC-4: ✕ hides that promo for good (also after relaunch). Other promos can still appear.
- AC-5: The menu bar menu has "More Apps" with every eligible promo; it is hidden when there are none.
- AC-6: One promo at a time; the footer promo changes once per day when several are eligible.
- AC-7: A new entry added to the hosted JSON appears within 24 h with no app update.
- AC-8: Offline or a broken feed: last good promos still show (or nothing); no error UI, no slowdown.
- AC-9: Settings toggle "Show other apps from the developer" (default on). Off → no footer, no menu item, no network requests.
- AC-10: Promos for DragShelf itself, or outside their app version or date window, are never shown.
- AC-11: The request carries no identifiers: plain GET, `User-Agent: DragShelf/<version>`, no cookies.
- AC-12: A feed entry with a non-`https` URL or a host not on the built-in allowlist is never shown and never opened.

## 9. Success metrics (manual, MVP)
- Drag from Finder into a hidden app via shelf in ≤ 2 gestures, no lost drops in the QA matrix.
- Zero permission prompts. Idle CPU ~0%, memory < 60 MB with 50 items.
- Network: at most 1 small request per 24 h (promo feed only), none when promos are off.

## 10. v2: Shelf Actions (next version, BACKLOG)
Not part of v1. v1 scope and T-01..T-12 do not change. User picked 4 actions (2026-10-20):
Zip all, Rename, AirDrop / Share, Convert or resize images.

Principle: an action never changes the user's original files. Each output is a **new cached shelf item**
(except Share, which hands items to another service). The user drags the output out as usual.

Where actions live:
- Tile context menu: actions that apply to the clicked item, or to the selection if the clicked item is selected.
- Header "Actions" menu (`ellipsis.circle`): applies to the selection, or to all items when nothing is selected.
- Keyboard: Return renames the single selected file item (Finder parity).

### US-11 Zip items (M6)
As a user, I zip shelf items into one archive and drag the zip into an email or upload field.
- AC-1: "Compress" on 1 file/folder item adds `<name>.zip`; on 2+ items adds `Archive.zip` (Finder naming).
- AC-2: The zip opens in Archive Utility and contains exactly the zipped files/folders with original names and contents (byte-equal).
- AC-3: Link and text items in the selection are skipped; the panel says how many were skipped (OQ-18).
- AC-4: Source items stay on the shelf; the zip is added at the end and selected.
- AC-5: Progress shows while zipping; Cancel stops it within 1 s and leaves no partial file in the cache.
- AC-6: Originals are unchanged (same path, name, mtime).

### US-12 Rename (M6)
As a user, I rename a file on the shelf before dragging it out, so the target gets the right name.
- AC-1: Context menu "Rename" or Return on one selected file item turns the caption into a text field with the base name selected.
- AC-2: Return commits, Esc cancels, clicking elsewhere commits.
- AC-3: Empty names, names with `/` or `:`, and names starting with `.` are rejected with an inline message; the old name stays.
- AC-4: The tile shows the new name; dragging it out delivers a file with the new name and the same contents.
- AC-5: The original file on disk keeps its name (OQ-17). The renamed item keeps its position on the shelf.
- AC-6: Rename is unavailable for link, text, and missing items.

### US-13 Share and AirDrop (M6)
As a user, I send shelf items with AirDrop or any macOS share service without opening Finder.
- AC-1: "Share…" shows the system share picker for the target items (files, links, and text).
- AC-2: "AirDrop" opens the system AirDrop sheet with the target items; it is disabled when AirDrop cannot handle them (`canPerform`).
- AC-3: A completed AirDrop to a nearby Mac or iPhone delivers the files with their names.
- AC-4: Items stay on the shelf after sharing (OQ-25).
- AC-5: The shelf stays visible while the picker or sheet is open, and does not hide behind it.

### US-14 Convert or resize images (M6)
As a user, I convert an image to another format or make it smaller before I upload it.
- AC-1: "Convert To ▸" offers HEIC, JPEG, PNG, TIFF for image items (any format ImageIO can read, including WebP input).
- AC-2: "Resize ▸" offers longest edge 512, 1024, 2048, 3840 px, never upscaling; the output keeps the source format (OQ-23).
- AC-3: Each output is a new item named `<base>.<ext>` or `<base> (<N>px).<ext>`; source items stay.
- AC-4: Output pixel size and format match the choice (`sips -g pixelWidth -g pixelHeight -g format`); orientation is upright.
- AC-5: A transparent PNG converted to JPEG has a white background, not black.
- AC-6: GPS location and other metadata are stripped; the color profile is kept (OQ-21).
- AC-7: Batch over 20 selected images shows "n of 20" progress; Cancel stops after the current image, and finished outputs stay.
- AC-8: Non-image items in the selection are skipped; with no image items the menu entries are disabled.

### Common ACs for every action (M6)
- AC-C1: The UI stays responsive (scrolling, dragging other items) while an action runs.
- AC-C2: One action at a time; action menu entries are disabled while one runs.
- AC-C3: A failure shows a short inline message in the panel and leaves no partial output.
- AC-C4: Clear or quit during an action cancels it; nothing is left in the cache.
- AC-C5: Every menu entry, progress, and error message has a VoiceOver label; start and finish are announced.
- AC-C6: No permission prompt and no network access, except for what the user's chosen share service does.

### v2 non-goals
WebP or AVIF output, custom pixel sizes, quality slider, batch rename patterns, unzip, PDF actions,
cloud upload, renaming originals in place (unless OQ-17 changes).

