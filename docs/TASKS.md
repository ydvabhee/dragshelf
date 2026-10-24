# DragShelf — Tasks

Ordered. One task per developer run. **Priority override (user, 2026-10-20): T-08 runs before T-07.** Each task leaves build + tests green and is committed alone.
Status: `TODO` → `IN PROGRESS` → `QA` → `DONE` (or `BLOCKED`). Stories: `docs/PRD.md`. Design: `docs/ARCHITECTURE.md`.

Every task's implicit ACs (QA checks always):
- `swift build` (zero warnings), `swift test`, and `scripts/build-app.sh release` (ARCHITECTURE §3; the release build is required) all succeed; manual checks run `open build/DragShelf.app`.
- Any closure AppKit/Foundation may call off the main thread is `nonisolated` + `@Sendable` (ADR-016); new ones get an off-main test.
- No permission prompt appears. No new dependency. New UI uses SF Symbols, system fonts, VoiceOver labels.

| ID | Title | Milestone | Depends on | Stories | Status |
|---|---|---|---|---|---|
| T-01 | Project skeleton + menu bar item + CLI build/test green | M0 | — | US-8 (part) | DONE (2026-10-20) |
| T-02 | Shelf model: ShelfItem, ShelfStore, ItemCache | M1 | T-01 | US-2, US-6 (model) | DONE (2026-10-20) |
| T-03 | Floating ShelfPanel with Liquid Glass UI shell | M1 | T-02 | US-3, US-10 | DONE (2026-10-20) |
| T-04 | Drop in: files, folders, links, text, image data | M1 | T-03 | US-2 | DONE (2026-10-20) |
| T-05 | Drop in: file promises | M1 | T-04 | US-2 | DONE (2026-10-20) |
| T-06 | Drag out: single, multi-select, drag all, Cmd-C | M2 | T-04 | US-4, US-5 | DONE (2026-10-20) |
| T-07 | Manage items: remove, clear, missing files, Quick Look, keyboard | M2 | T-06 | US-6, US-7 | DONE (2026-10-20) |
| T-08 | Auto-show/hide on drag (DragMonitor) | M3 | T-03, T-04 | US-1 | DONE (2026-10-20) |
| T-09 | Global hotkey ⌃⌥⌘D | M3 | T-03 | US-8 | DONE (2026-10-20) |
| T-13 | Responsive shelf: fit-to-content + scroll, movable + remembered position, O(1) dedupe | M3 | T-07, T-08 | US-2, US-3 | DONE (2026-10-20) |
| T-15 | Drag out: ⌘-drag moves file items (plain drag copies) | M4 | T-10 | US-4 | DONE (2026-10-20) |
| T-16 | UI polish: no focus ring/outline, inset scroll bar, user-resizable shelf | M4 | T-13, T-14 | US-3, US-10 | DONE (2026-10-20) |
| T-19 | Branding: call the shelf "DragShelf" in UI text | M4 | T-16 | US-8 | DONE (2026-10-23) |
| T-20 | Clear wording (no trash icon) + menu bar glyph matching app icon | M4 | T-17 | US-6, US-8 | DONE (2026-10-23) |
| T-21 | Cache hygiene: free temp files while running | M4 | T-17 | US-6 | DONE (2026-10-23) |
| T-17 | Recent drag-outs (last 5) + ⌘Z undo | M4 | T-16 | US-4, US-6 | DONE (2026-10-23) |
| T-18 | Contextual hints (one line, shown a few times) | M4 | T-17 | US-3, US-10 | DONE (2026-10-23) |
| T-10 | Settings window + launch at login | M4 | T-06, T-08, T-09 | US-9 | DONE (2026-10-20) |
| T-11 | Accessibility and motion polish pass | M4 | T-07, T-10 | US-10 | DONE (2026-10-20) |
| T-14 | Remote "More apps" promo line | M4 | T-10 | US-15 | DONE (2026-10-20) |
| T-12 | Developer ID signing + notarization | M5 | T-11 | — | BLOCKED (user: Developer ID cert + notary creds) |

---

## T-01 Project skeleton + menu bar item + CLI build/test green
Milestone M0. Depends on: —.
SwiftPM per ARCHITECTURE §2–3 (ADR-013): `Package.swift`, `scripts/build-app.sh`,
`Sources/DragShelf/App/DragShelfApp.swift`, `AppDelegate.swift`, one test file in `Tests/DragShelfTests/`.
Migrate the uncommitted xcodeproj-era files, then delete `DragShelf.xcodeproj/`, `DragShelf/`, `DragShelfTests/`.
- AC-1: `swift build` succeeds with zero warnings.
- AC-2: `swift test` runs ≥ 1 passing Swift Testing test (`@Test`) using `@testable import DragShelf`.
- AC-3: `scripts/build-app.sh` (and `scripts/build-app.sh release`) produces `build/DragShelf.app`; `codesign -dv --verbose=2 build/DragShelf.app` shows ad-hoc signature with `runtime` flag; `plutil -p build/DragShelf.app/Contents/Info.plist` shows the keys in ARCHITECTURE §3.
- AC-4: `open build/DragShelf.app` shows a menu bar icon (SF Symbol `tray.and.arrow.down`), no Dock icon, no app menu.
- AC-5: Menu has "Show Shelf" (disabled placeholder), "Settings…" (opens empty Settings window, app activates), "Quit DragShelf" (⌘Q, quits).
- AC-6: `Package.swift` matches ARCHITECTURE §3: tools 6.2, `.macOS(.v14)`, no dependencies, MainActor default isolation, warnings as errors (or documented fallback).
- AC-7: `.gitignore` has `.build/`, `.swiftpm/`, `build/`; no `.xcodeproj` in the repo.

## T-02 Shelf model: ShelfItem, ShelfStore, ItemCache
Milestone M1. Depends on: T-01. Pure logic, no UI.
- AC-1: `ShelfItem` with `Kind { file(URL), url(URL), text(String) }` and `isCached`, per ARCHITECTURE §4.
- AC-2: `ShelfStore.add` appends in drop order; adding the same file path, URL, or exact text twice keeps one item (unit test).
- AC-3: `remove(ids:)` and `clear()` update `items` and `selection`; removing a cached item deletes its `ItemCache` dir (unit test with temp root).
- AC-4: `ItemCache.newItemDir()` creates `root/<UUID>/`; `wipe()` removes everything under root (unit test).
- AC-5: `AppDelegate` wipes cache on launch and in `applicationWillTerminate`.
- AC-6: `ItemCache` root is injectable for tests; tests never touch the real `~/Library/Caches`.

## T-03 Floating ShelfPanel with Liquid Glass UI shell
Milestone M1. Depends on: T-02.
`ShelfPanel`, `ShelfPanelController`, `ShelfView`, `ShelfItemView`, `Glass.swift`. Show via menu "Show Shelf" (now enabled).
- AC-1: "Show Shelf" toggles the panel; it appears at the right edge, vertically centered, on the screen with the cursor.
- AC-2: Panel does not activate DragShelf: frontmost app and its key window are unchanged after show and after clicking the panel.
- AC-3: Panel stays above normal windows across Cmd-Tab, appears on every Space and over a full-screen app.
- AC-4: macOS 26: Liquid Glass background (`glassEffect`, 22 pt continuous corners), header buttons glass in a `GlassEffectContainer`. Code path for macOS 14–15 compiles behind `#available` (NSVisualEffectView, `state = .active`).
- AC-5: Empty state shows `tray.and.arrow.down` + "Drop here"; header has drag-all (disabled when empty), Clear, Close; all have VoiceOver labels.
- AC-6: Close button and Esc hide the panel. Show/hide animate with spring; Reduce Motion → fade only; Reduce Transparency → opaque background.
- AC-7: Correct in light and dark mode (screenshots of both in QA).

## T-04 Drop in: files, folders, links, text, image data
Milestone M1. Depends on: T-03. `PasteboardReader`, `DropReceiver`, `Thumbnail.swift`.
- AC-1: `PasteboardReader.read` unit tests on a private named `NSPasteboard`: file URLs → `.file`; web URL → `.url`; string → `.text`; PNG/TIFF data → `.image`; item with both image data and URL → `.image` (precedence per ARCHITECTURE §4).
- AC-2: Dropping 1 file, 5 files, and a folder from Finder adds 1, 5, 1 items; originals untouched.
- AC-3: Dropping an image from Safari or Chrome adds a cached PNG/JPEG file item (not `.webloc`), file exists under `ItemCache.root`.
- AC-4: Dropping a link adds a `.url` item; dropping selected text adds a `.text` item showing its first line.
- AC-5: Panel shows a tinted/highlighted drop-target state while a drag hovers; it clears on exit/drop.
- AC-6: Tiles show a QuickLook thumbnail (file) or system icon fallback; link tile `link`, text tile `text.alignleft` symbols; VoiceOver label "<type>, <name>".
- AC-7: 50 dropped files all show; grid scrolls past max height.

## T-05 Drop in: file promises
Milestone M1. Depends on: T-04.
- AC-1: Dropping an attachment from Mail and a photo from Photos adds a file item whose file is written under `root/<UUID>/` with the sender's filename.
- AC-2: Promise receiving runs off the main thread; UI stays responsive (scroll works) while a 100 MB+ promised file is written.
- AC-3: A promise that fails (sender error) adds no item and logs the error with `Logger`; no empty dir left in cache.
- AC-4: Unit test: given a received URL, the store adds a `.file` item with `isCached = true`.
- AC-5 (carried from T-04 QA): `DropReceiver.draggingUpdated` returns `[]` when the drag was rejected in `draggingEntered`; `.copy` only when acceptable.

## T-06 Drag out: single, multi-select, drag all, Cmd-C
Milestone M2. Depends on: T-04. `DragOutSource`, selection in `ShelfStore`.
- AC-1: Dragging a file item into Finder, Mail compose, Messages/Slack, and a browser upload field delivers the file.
- AC-2: Dragging a link item into a browser address bar delivers the URL; into Finder creates a `.webloc`. Text item into TextEdit inserts the text.
- AC-3: Cmd-click / Shift-click select multiple; dragging a selected tile drags all selected. Drag-all handle drags every item. 5 files into a Finder folder → 5 files.
- AC-4: Operation mask is `.copy` only: dragging an original into another Finder folder on the same volume copies it; the original stays (unit test on mask + manual check).
- AC-5: Successful drop → dragged items removed (cached dirs kept until Clear/quit/launch wipe, because receivers read the file after the drop); cancelled drag (Esc / drop on nothing) → items stay. Shelf hides when it becomes empty.
- AC-6: Cmd-C copies selected items to `NSPasteboard.general` with the same writers (unit test on `writer(for:)`).
- AC-7: Dragging out of the panel does not activate DragShelf.

## T-07 Manage items: remove, clear, missing files, Quick Look, keyboard
Milestone M2. Depends on: T-06.
- AC-1: Hover shows `xmark.circle.fill` on a tile; click removes it. Delete key and context menu "Remove" remove the selection.
- AC-2: Clear removes all items, wipes cache root, hides the panel.
- AC-3: A file item whose file was deleted from disk shows dimmed with "Missing" and cannot be dragged or Quick Looked; check runs each time the panel shows.
- AC-4: Space opens Quick Look for selected file items; Space/Esc closes it; arrow keys move selection and preview follows. DragShelf does not become the active app.
- AC-5: Tiles expose VoiceOver actions "Remove" and "Quick Look".
- AC-6 (carried from T-03 AC-6): Esc hides the panel even though it is non-activating (panel becomes key on click, or a local key monitor), without activating DragShelf.
- AC-7 (carried from T-05 QA): a file promise that completes after Clear/quit adds no item and leaves no file (e.g. generation counter bumped in `clear()`, checked in `DropReceiver.finishPromise`). Unit test.
- AC-8 (carried from T-06 QA): right-click context menu and hover `xmark` work on tiles despite the `DragOutHandleView` overlay (overlay below controls, or forward rightMouseDown/hover).
- AC-9 (user, OQ-16): dropping the same image data again (same content hash, SHA-256 via CryptoKit) replaces the existing item: old item + its cache dir removed, new item appended. Unit test.

## T-08 Auto-show/hide on drag (DragMonitor)
Milestone M3. Depends on: T-03, T-04.
- AC-1: Dragging a file in Finder ≥ 10 pt shows the panel within 300 ms; same for Safari/Chrome image, link, and selected text.
- AC-2: Moving or resizing windows never shows the panel.
- AC-3: Drag ends without a drop on the shelf and shelf empty → panel hides within 500 ms. Drop on shelf → panel stays.
- AC-4: Panel appears on the display that holds the cursor (multi-display check).
- AC-5: Panel already shown manually is not hidden by a drag ending.
- AC-6: Drags out of DragShelf itself do not re-trigger show/hide logic.
- AC-7: No permission prompt (Accessibility/Input Monitoring) on fresh install (`tccutil reset All com.abhishekyadav.DragShelf` first).
- AC-8: Monitors removed when auto-show is disabled (API ready for T-10; QA checks via a debug toggle or T-10).
- AC-9 (user request 2026-10-20): panel shows at **top center** of the cursor's screen (centered horizontally, 12 pt below `visibleFrame.maxY`, top-anchored so adding items grows it downward), for both auto-show and menu "Show Shelf". Replaces T-03 AC-1 right-edge placement.

## T-09 Global hotkey ⌃⌥⌘D
Milestone M3. Depends on: T-03.
- AC-1: ⌃⌥⌘D toggles the panel from any frontmost app, including a full-screen app.
- AC-2: No permission prompt.
- AC-3: Menu "Show Shelf" shows the shortcut ⌃⌥⌘D.
- AC-4: If registration fails (shortcut taken), app keeps running and logs it; menu item still works.

## T-13 Responsive shelf: fit-to-content + scroll, movable + remembered position, O(1) dedupe
Milestone M3. Depends on: T-07, T-08. Source: user reports 2026-10-20 + investigation (scroll root cause, perf table below).
Root cause: panel frame set only once in `ShelfPanelController.show()`; auto-show opens empty (1 row), later rows clip and nothing scrolls. Dedupe is O(n^2) (re-resolves symlinks for every existing item per add): 1000 files = 23.5 s, 5000 ~ 10 min.
- AC-1: Panel resizes to fit content whenever items change (grow and shrink), keeping its **top edge fixed** (`setFrame` with `y = maxY - h`). Fit runs async after geometry change (`.onGeometryChange` then `Task { @MainActor }`; synchronous `fittingSize` in the callback returns 0).
- AC-2: Max height = min(4.5 tile rows, 50% of the screen's `visibleFrame` height); the half row hints there is more. Beyond that the grid scrolls with trackpad/wheel anywhere over tiles or gaps. Scroll indicators flash when items are added (`scrollIndicatorsFlash`, macOS 15+ behind `#available`).
- AC-3: After a drop, the grid scrolls to reveal the newly added item(s).
- AC-4 (user request): The shelf can be **dragged to move it** by its header bar (empty header area; tiles keep drag-out, buttons keep working). No `isMovableByWindowBackground` on tiles. Native feel; panel stays non-activating while moving.
- AC-5: Moved position is remembered across shows and relaunches (UserDefaults, stored per screen as offset of the panel's top-center from the screen's `visibleFrame`), used by auto-show, hotkey and menu. If the saved spot is off-screen (display removed / resolution change), clamp into `visibleFrame`. Growing near the bottom of the screen clamps so the panel never extends past `visibleFrame`.
- AC-6: Menu bar menu item "Reset Shelf Position" and double-click on the header restore top center (default from T-08 AC-9).
- AC-7: Dedupe via `keys: [Key: UUID]` beside ordered `items`; `Key` = `file(normalized path, resolved once per add)`, `url(absoluteString)`, `text(String)`, `image(SHA256.Digest)`. `remove` and `clear` drop keys. Same-image replace (T-07 AC-9) still works — verify against current code.
- AC-8: Perf unit test: adding 5000 file items completes < 1 s; 1 add at N=5000 < 1 ms average. Decision recorded: **no item limit** (UI cost is flat: lazy grid, bounded thumbnails, ~3 MB view memory at N=5000).
- AC-9: No regressions: auto-hide rules (T-08), Quick Look sync (T-07), drag-out (T-06), all tests green.

## T-15 Drag out: ⌘-drag moves file items (plain drag copies)
Milestone M4. Depends on: T-10 (touches `DragOutSource` after T-10's keepAfterDragOut change). Source: user request 2026-10-20; ⌘ chosen over Shift to match Finder convention (⌘ = move, ⌥ = copy).
- AC-1: Plain drag of file items out of the shelf → receiver copies (current behavior). Holding ⌘ during the drag → move: Finder moves the file (original gone from its folder). Toggling ⌘ mid-drag switches live; cursor badge updates (`ignoreModifierKeys = false`, mask computed per `sourceOperationMaskFor` call from current modifier flags).
- AC-2: Link and text items always copy (⌘ has no effect). Mixed selection with ⌘: files move, links/text copy (or whole drag copies if per-item masks unsupported; document choice).
- AC-3: Session ended with `.move` → dragged items always removed from the shelf, even when "Keep items after drag out" is on. Cached items moved out leave no empty cache dir.
- AC-4: Inside-app mask stays `[]` (self-drop still a no-op).
- AC-5: Unit tests: mask decision (modifiers × item kinds × inside/outside app); removal decision for `.move` vs `.copy` × keepAfterDragOut.
- AC-6: Manual: same volume and cross-volume ⌘-drag into Finder; ⌘-drag into apps that only accept copy (e.g. Mail compose) still works or falls back to copy.
- AC-7 (carried from T-10 QA): `AppDelegate.applyPreferences` remembers last applied values and only calls DragMonitor start/stop and HotKey register/unregister when a value changed (no repeated register error log on every shelf move).

## T-16 UI polish: no focus ring/outline, inset scroll bar, user-resizable shelf
Milestone M4. Depends on: T-13, T-14. Source: user report 2026-10-20 ("UI not looking good": outline on click, stray outline on screen, ugly scroll bar; wants drag-to-resize).
- AC-1: Clicking anywhere on the shelf (tiles, header, empty area, footer) never draws a focus ring or outline: SwiftUI `.focusEffectDisabled()` where focusable, AppKit views `focusRingType = .none`; keyboard selection is shown only by the tile's own accent selection style.
- AC-2: No rectangular border, hairline, or square shadow around the rounded shelf in any state (shown, key, non-key, drop-target, Reduce Transparency, Increase Contrast). Shadow follows the rounded shape (`invalidateShadow()` after resize/glass layout; transparent window background; `isOpaque = false`). Increase Contrast stroke, if any, follows the same rounded corners and sits inside the edge.
- AC-3: Scroll bar: system overlay style (thin, auto-hides), inset inside the rounded shelf: never touches or is clipped by the corner radius (scroller insets / content margins ≥ corner radius at top and bottom, ~4–6 pt from the right edge). Only visible when content overflows.
- AC-4: Shelf is user-resizable by dragging its bottom edge, left/right edges, and bottom corners (top edge stays the header/move area). Cursor shows resize arrows on hover. Panel stays non-activating while resizing.
- AC-5: Width resize reflows tiles into more/fewer columns (adaptive grid); min size = 1 tile column + header, 1 row; max = screen `visibleFrame`.
- AC-6: Height resize sets the user's max height; content still fits-to-content below that (T-13 AC-1 behavior), scrolls above it. If the user never resized, defaults from T-13 AC-2 apply.
- AC-7: User size is remembered per display with the position (T-13 AC-5) and restored on show/relaunch; "Reset Shelf Position" (menu, Settings, header double-click) also resets size.
- AC-8: Unit tests for size math (min/max clamps, columns from width, persisted size per screen, reset).
- AC-9: No regressions: drag-out, drop-in, header move, auto-hide, promo footer, Quick Look.

## T-17 Recent drag-outs (last 5) + ⌘Z undo
Milestone M4. Depends on: T-16. Source: user idea 2026-10-20 (validated): items are removed after drag out (OQ-08), so a wrong drop or a later upload failure loses the item. Name it "Recent", not "History".
- AC-1: Every successful drag out (copy or move) records one Recent entry = the batch of items dragged (a "drag all" of 30 files = 1 entry). Keep the last **5 entries**; oldest falls off. Cancelled drags record nothing.
- AC-2: ⌘Z (panel key, or menu bar item "Undo Drag Out") puts the most recent entry's items back on the shelf (normal dedupe rules apply) and removes that entry. Repeating ⌘Z walks back through entries.
- AC-3: Header gets a small `clock.arrow.circlepath` button (hidden when Recent is empty). Click → compact popover/list: one row per entry, e.g. "3 files · 2 min ago" / "photo.heic · just now", newest first. Click row → restore its items to the shelf. Drag a row → drags its items out directly (same copy/⌘-move rules as T-15).
- AC-4: Items whose file no longer exists (e.g. ⌘-moved, deleted) show the existing "Missing" style and are skipped on restore/drag; a row with nothing present is dimmed and not draggable.
- AC-5: Cache dirs of cached items (images, promises) are kept while they are in Recent; deleted when their entry falls off, on Clear Recent, Clear shelf? (NO — Clear shelf keeps Recent), and on quit. Recent is memory-only, wiped on quit (OQ-03).
- AC-6: Recent list has "Clear Recent". VoiceOver labels for button, rows ("3 files, 2 minutes ago"), and actions Restore / Drag.
- AC-7: Unit tests: entry recording per batch, cap 5, ⌘Z order, restore with dedupe, missing skipped, cache dir lifetime.

## T-18 Contextual hints (one line, shown a few times)
Branding: follow T-19 rule ("DragShelf", not "the shelf", in hint text where it names the panel).
Milestone M4. Depends on: T-17. Source: user request 2026-10-20 ("add hints for the user"). Rule: never a popup/modal; never more than one hint line at a time; never during an active drag; each hint auto-retires.
- AC-1: Hints use the single footer line slot (same place as the promo line; a hint takes priority over a promo). Style: `.secondary` caption, leading `lightbulb` SF Symbol, small ✕ to dismiss that hint forever.
- AC-2: Hint set (each shown at most 3 times, then never again; tracked in UserDefaults):
  - after first item dropped: "Switch apps, then drag items out of the shelf."
  - after first drag out: "Removed from shelf · ⌘Z to bring it back" (also shown right after any drag out for the first 3 times).
  - shelf shown with ≥ 1 file item: "Hold ⌘ while dragging out to move instead of copy."
  - shelf shown 3rd time: "Drag the top bar to move the shelf · edges to resize."
  - shelf shown via menu (not hotkey) 2nd time: "Tip: ⌃⌥⌘D shows the shelf from anywhere."
  - first time Recent has an entry: "Recent drags are under the clock icon."
- AC-3: Tooltips (`.help`) on every header button, the clock button, and Recent rows (short, verb-first: "Restore to shelf", "Clear all items").
- AC-4: Settings → "Show tips" toggle (default on) + "Reset tips" button.
- AC-5: VoiceOver reads the hint line; Reduce Motion → no slide, fade only.
- AC-6: Unit tests: hint eligibility + show-count retirement + priority over promo + never during drag.

## T-19 Branding: call the shelf "DragShelf" in UI text
Milestone M4. Depends on: T-16. Source: user request 2026-10-23 ("status bar says Show Shelf, change it to Show DragShelf, use this as branding").
Rule (applies to all later tasks too): commands, titles, tooltips and VoiceOver labels that name the floating panel say **DragShelf**; generic nouns inside longer sentences may say "DragShelf" too, never a bare "Shelf" as a name.
- AC-1: Menu bar menu: "Show DragShelf" / "Hide DragShelf", "Reset DragShelf Position", "Quit DragShelf" (unchanged). Keyboard shortcut display unchanged.
- AC-2: Panel header title when empty: "DragShelf" (was "Shelf"); with items keeps the count ("3 Items").
- AC-3: Header buttons: "Clear DragShelf" (label + `.help`), hints "Removes every item and hides DragShelf" / "Hides DragShelf; items stay".
- AC-4: Settings: toggle "Show DragShelf when dragging"; section "Shelf" → "DragShelf"; button "Reset DragShelf Position"; footers say "DragShelf" where they named the shelf ("…under DragShelf…", "…items leave DragShelf once dropped elsewhere. Drag the DragShelf header to move it.").
- AC-5: README usage table and Settings list updated to the new names; CHANGELOG `[Unreleased]` → Changed line.
- AC-6: No identifier/key/type renames (strings only); tests that assert strings updated; build/test/release green.

## T-20 Clear wording (no trash icon) + menu bar glyph matching app icon
Milestone M4. Depends on: T-17 (same header and menu files). Source: user 2026-10-23: the trash icon suggests deleting the original files; the menu bar icon should match the app icon.
- AC-1: Header "Clear" control is a small text button ("Clear", glass style matching the header buttons), not `trash`. Disabled when empty. `.help("Remove all items from DragShelf. Your files stay where they are.")`. VoiceOver: label "Clear DragShelf", hint "Removes all items from DragShelf; files are not deleted".
- AC-2: Context menu item "Remove" becomes "Remove from DragShelf"; Delete key behavior unchanged. No `trash` SF Symbol anywhere in the UI.
- AC-3: Menu bar icon = template glyph matching the app icon (tilted file card dropping into a solid tray with a knocked-out down arrow), drawn in code in `UI/MenuBarIcon.swift` as an `NSImage` (18x18 pt, `isTemplate = true`); `MenuBarExtra` uses it instead of `tray.and.arrow.down`. Reference drawing: `docs/assets/menubar-glyph-prototype.swift` (`drawGlyph`) (card rotated -10 deg, 1.5 pt outline, two content lines; tray 14x6 pt rounded 2.2 with 0.9 pt cleared gap; arrow 1.4 pt knocked out).
- AC-4: Empty-state symbol in the panel may stay `tray.and.arrow.down` or use the same glyph (choose the one that looks better at 34 pt; note choice).
- AC-5: T-18 hint list gains: first Clear with ≥ 1 item → "Clear only empties DragShelf; your files aren't touched."
- AC-6: README usage table and CHANGELOG `[Unreleased]` updated. Build/test/release green.
- AC-7 (carried from T-17 QA): dragging a Recent row never removes shelf items (skip `remove(ids:)` when the drag came from Recent, unless `.move` and the same file item is on the shelf); Recent entry stays.
- AC-8 (carried from T-17 QA): the Recent list resets to the grid on every show; any drop onto the panel (even duplicate-only) switches back to the grid.

## T-21 Cache hygiene: free temp files while running
Milestone M4. Depends on: T-17. Source: user 2026-10-23 ("keep cleaning the temp data so it does not consume a lot"). The cache (`~/Library/Caches/com.abhishekyadav.DragShelf`) is wiped at launch/quit, but with launch at login the app can run for weeks while Recent keeps cached files (images, file promises) alive.
- AC-1: Orphan sweep: after any change that can drop a reference (remove, clear, drag out, Recent eviction, Clear Recent, undo, image replace) and on each show, delete cache dirs referenced by neither a shelf item nor a Recent entry. Cheap: one directory listing; never touches non-cache paths.
- AC-2: Size cap: if the cache exceeds 1 GB (`ponytail:` constant, upgrade path: a setting), evict the oldest Recent entries (and their cache dirs) until under the cap. Never deletes dirs used by items still on the shelf.
- AC-3: Age limit: Recent entries older than 24 h are dropped (with their dirs) on the next sweep; a sweep also runs every 30 min while the app is running (timer, tolerance set, no work when the cache is empty).
- AC-4: Sweeps run off the main actor for the file system work; results applied on MainActor; Swift 6 clean (ADR-016 rules).
- AC-5: Logger line with bytes freed (debug level). No UI.
- AC-6: Unit tests with a temp cache root: orphan removed, shelf-referenced kept, Recent-referenced kept until evicted, size cap evicts oldest first, age expiry, empty cache no-op.

## V2-05 Custom image resize (Pixels/Percent, aspect lock)
Milestone M6. Depends on: V2-03. Source: user 2026-10-23 ("add a custom resize for images"). Supersedes OQ-23 "presets only". Model: Preview's Tools → Adjust Size.
- AC-1: "Resize ▸" gains a separator + "Custom…" (header Actions menu and tile menu), enabled when target items contain an image.
- AC-2: Custom… shows an inline form inside the panel (in place of the grid, like Recent; no sheet/window — must not activate the app; panel becomes key for typing): segmented Pixels | Percent; Width and Height fields; aspect-lock toggle (`link` SF Symbol, on by default); Cancel and Resize buttons (Resize = default, Return); Esc cancels; VoiceOver labels.
- AC-3: One image: fields prefilled with its pixel size; with lock on, editing one field updates the other from the image's aspect ratio. Several images: fields start empty, semantics = fit each image inside W x H keeping its own aspect; either field may be empty (constrain one dimension only); Percent applies to each image.
- AC-4: Explicit custom sizes may upscale (presets still never upscale); show a subtle note "Larger than the original" when any output would upscale.
- AC-5: Validation: integers 1–16384 px, 1–400 %, at least one dimension; invalid → shake (fade under Reduce Motion) + one-line message, form stays open.
- AC-6: Output reuses V2-03 pipeline (same format as source, metadata stripped, orientation applied, color profile kept, per-image failure skip, progress, cancel, in-flight dir); name "<base> (<W>×<H>).<ext>" with the actual output size; collisions via uniqueName.
- AC-7: Unit tests: aspect-lock math, fit-in-box for mixed aspect batch, single-dimension constraint, percent, upscale allowed for custom only, validation bounds, output names.

## V2-06 Paste clipboard into DragShelf
Milestone M7. Source: user 2026-10-24. Reuse `PasteboardReader` + `DropReceiver.ingest` (same dedupe, image hashing, file promises n/a, uniqueName).
- AC-1: ⌘V while the panel is key adds the general pasteboard's items (files, folders, URLs, text, image data) exactly like a drop; ignored while a text field (rename/resize/search) has focus (field gets the paste).
- AC-2: Right-click on empty grid area → "Paste" (disabled when the pasteboard has nothing usable). Menu bar menu: "Paste to DragShelf" (shows the panel, adds items, panel not key, app not activated).
- AC-3: Nothing usable → subtle one-line footer message "Nothing to paste". Recent view switches back to grid (like a drop).
- AC-4: Unit tests via a private named pasteboard: files/URL/text/image paste paths, dedupe, empty pasteboard.

## V2-07 Text ↔ .txt (dual drag-out, Use as Text, Save as .txt)
Milestone M7. Source: user 2026-10-24 ("UI should be user friendly and not confusing"). Principle: the receiving app decides; no toggles.
- AC-1: Dragging a text item out writes both `NSString` and a file promise (`NSFilePromiseProvider`, `.txt`, UTF-8) — text fields receive text, Finder/Desktop receive a real "<first line, ≤ 60 chars, sanitized>.txt" (not a .textClipping). Same for ⌘C (string + file URL of a temp .txt only if cheap; else string only — note choice).
- AC-2: `.txt`/plain-text file item → context menu "Use as Text" adds a text item with its contents (UTF-8/UTF-16 detected; ≤ 1 MB, else disabled with tooltip "File is too large").
- AC-3: Text item → context menu "Save as .txt" adds a cached `.txt` file item (name from first line, uniqueName). Original text item stays.
- AC-4: ADR-016 for the file-promise provider delegate (writes off main). Tests: name sanitizing, encoding detection, size limit, promise writes exact bytes.
- AC-5 (carried from V2-06 QA): `DropReceiver.pasteItems` keeps the "Nothing to paste" clear-timer Task and cancels it before starting a new one.

## V2-08 Pin items (persist across Clear, drag out, quit)
Milestone M7. Source: user 2026-10-24. Supersedes OQ-03 for pinned items only (unpinned still cleared on quit).
- AC-1: Context menu "Pin" / "Unpin" (and Recent untouched). Pinned items render first, with a small `pin.fill` badge; VoiceOver "Pinned".
- AC-2: Pinned items are never removed by Clear, drag out (copy or ⌘-move: move is disabled for pinned file originals — they copy), auto-hide rules unchanged. "Clear" tooltip mentions pinned items stay.
- AC-3: Persistence in Application Support (`~/Library/Application Support/com.abhishekyadav.DragShelf/Pinned/`): original files stored as bookmark data (resolve on launch; stale → refresh; unresolvable → Missing style); cached items (images, promises, text, zips, converted) copied into the Pinned folder (not the cache, so launch wipe and T-21 sweep never touch it); text stored as UTF-8. Manifest JSON (versioned, strict decode). Unpin of a stored copy deletes it.
- AC-4: Cache sweep (T-21) and launch/quit wipe ignore the Pinned folder; dedupe keys include pinned items.
- AC-5: Tests: pin/unpin, survives clear, survives simulated relaunch (new store from manifest), bookmark of moved file resolves, unpin frees stored copy, manifest corruption handled.
- AC-6 (carried from V2-09 QA): `SettingsView` shortcut recorder re-registers the hotkey from `updateNSView` (mutates @Observable during a view update) — defer it (`Task { @MainActor }` / `DispatchQueue.main.async`) so SwiftUI never warns "Modifying state during view update".

## V2-09 Custom global shortcut (Settings recorder)
Milestone M7. Source: user 2026-10-24. Supersedes OQ-04.
- AC-1: Settings → General: shortcut recorder field (Apple-style: click → "Type shortcut", shows symbols like ⌃⌥⌘D), Clear and "Reset to ⌃⌥⌘D" buttons.
- AC-2: Requires ≥ 1 of ⌘ ⌃ ⌥ (⇧-only or no-modifier rejected with inline message); Esc cancels recording.
- AC-3: Registers via Carbon immediately; if registration fails (taken) → inline "This shortcut is used by another app" and keep previous one. Persisted (UserDefaults: keyCode + modifiers); menu "Show DragShelf" shows the current shortcut; T-18 hint text uses the current shortcut.
- AC-4: No Accessibility/Input Monitoring permission (record with a local key monitor while the Settings field is focused only).
- AC-5: Tests: modifier validation, persistence round-trip, display string, register-failure keeps old.

## V2-10 Search and filter
Milestone M7. Source: user 2026-10-24.
- AC-1: ⌘F (panel key) or a `magnifyingglass` header button reveals a search field in the header; typing filters tiles live (case/diacritic-insensitive) by name, URL text, and text content. Esc clears and hides the field; empty field = all.
- AC-2: Filter menu next to the field: All · Files · Images · Links · Text · Pinned (checkmark on active). Header count shows "3 of 12" while filtered.
- AC-3: Drag All, Clear, select-all, arrow keys, Quick Look act on visible (filtered) items only; Clear confirms nothing extra (pinned still kept).
- AC-4: Drops while filtered still add items; filter stays; new item visible only if it matches (header shows count change). Search state resets on hide.
- AC-5: Performance: filtering 5000 items < 16 ms (precomputed lowercase/folded search key per item). Tests: matching rules, filter kinds, visible-only actions, perf.

## T-10 Settings window + launch at login
Milestone M4. Depends on: T-06, T-08, T-09. `SettingsView` (SwiftUI `Form`, `.formStyle(.grouped)`).
- AC-1: Launch at login toggle calls `SMAppService.mainApp.register/unregister`; toggle reflects real status after relaunch.
- AC-2: Auto-show on drag toggle (default on) starts/stops `DragMonitor` immediately.
- AC-3: Shelf position: **no picker** (superseded by T-13 drag-to-move + remembered position). Settings shows a "Reset Shelf Position" button calling the existing `resetPosition()`.
- AC-4: Keep items after drag out toggle (default off) changes T-06 AC-5 behavior.
- AC-5: Global hotkey toggle (default on) registers/unregisters immediately.
- AC-6: All values persist across relaunch (UserDefaults). Settings opens in front (app activates only for Settings).

## T-11 Accessibility and motion polish pass
Milestone M4. Depends on: T-07, T-10.
- AC-1: VoiceOver walkthrough: every tile, header button, menu item, and setting has a meaningful label; tile actions Remove/Quick Look work.
- AC-2: Reduce Motion, Reduce Transparency, Increase Contrast each verified on macOS 26 (and macOS 14/15 if available, else noted).
- AC-3: Light/dark and accent color changes render correctly without relaunch.
- AC-4: Full keyboard path: hotkey → arrows → Space → Cmd-C → Esc works without the mouse.
- AC-5: Idle CPU ~0% and memory < 60 MB with 50 items (Activity Monitor).
- AC-6 (carried from T-04 QA): drop-target highlight animation in `DropReceiver` is gated on Reduce Motion (no spring when on).
- AC-7 (carried from T-07 QA): SHA-256 of dropped image data computed off MainActor (no UI hitch for 50 MB+ images); item added on MainActor after.
- AC-8 (carried from T-13 QA): max height recomputed for the panel's current screen in `fitToContent()`/after a user move (not only in `show()`).
- AC-9 (carried from T-13 QA): header drag clamps the panel inside the screen's `visibleFrame` while moving (never under the menu bar or off-screen).
- AC-10 (carried from T-13 QA): unit test that `ShelfStore.keys` stays consistent with `items` after image replace / remove / clear; perf test per-add bound loosened to 5 ms (avoid CI flake).

## T-14 Remote "More apps" promo line
Milestone M4. Depends on: T-10. v1: users who never update must still get new promos, so this ships in the first release.
Design: ARCHITECTURE §12, ADR-015. Files: `Promos/PromoFeed.swift`, `Promos/PromoLoader.swift`, `UI/PromoFooter.swift`, a menu entry in `DragShelfApp`, the `showPromos` + `dismissedPromoIDs` keys in `Preferences`, and a toggle row in `SettingsView`.
- AC-1: Unit test `PromoFeed.decode` on `backend/promos.json` (copied into the test as a string): all entries valid.
- AC-2: Unit tests: entries are dropped for `http:` URL, `file:`/custom scheme, host not in allowlist, title > 60 chars, title with `\n` or bidi override, bad id, bad version string, and `version != 1` (whole feed ignored). Valid neighbors are kept.
- AC-3: Unit tests `eligible`: version window, date window, `excludeBundleIds` containing `com.abhishekyadav.DragShelf`, dismissed ids. `pick` is stable within a day and rotates the next day (injected `now`/calendar).
- AC-4: Unit tests `PromoLoader` with a stub `URLProtocol`: 200 writes cache + ETag; second call within 24 h makes no request; after 24 h sends `If-None-Match`; 304 keeps cache; 500/garbage/> 64 KB keeps the previous cache and does not throw; redirect to `http` or another host is refused; request has `User-Agent: DragShelf/<version>` and no `Cookie` header.
- AC-5: With `showPromos` off, `refreshIfStale()` makes no request (stub counts 0) and no footer or menu item shows.
- AC-6: Manual (serve `backend/promos.json` locally or point a debug build at a test host): footer shows one line under the grid; hidden during a drag; ✕ hides it permanently across relaunch; click opens the browser without activating DragShelf; "More Apps" submenu lists eligible promos.
- AC-7: Offline launch with a cached feed shows the cached promo; without a cache shows nothing; no error UI.
- AC-8: Settings toggle "Show other apps from the developer" (default on) persists and takes effect immediately.
- AC-9: VoiceOver reads the footer and the ✕ with the labels in ARCHITECTURE §12.
- Limit: the feed URL and host are placeholders (OQ-26). Release (T-12) must not ship until OQ-26 is answered.
- AC-X (carried from T-11 QA): panel becomes key only when shown via the hotkey (`ShowReason.hotkey`); menu "Show Shelf" and auto-show keep it non-key so the frontmost app keeps keyboard focus.

## T-12 Developer ID signing + notarization — BLOCKED
Milestone M5. Depends on: T-11. **Blocked on user:** needs a Developer ID Application certificate in the keychain and `notarytool` credentials (Apple ID app-specific password or API key).
- AC-1: `scripts/build-app.sh release` signs with the Developer ID identity, hardened runtime, `--timestamp`.
- AC-2: `xcrun notarytool submit --wait` returns Accepted; `xcrun stapler staple` succeeds.
- AC-3: `spctl -a -vv DragShelf.app` reports `source=Notarized Developer ID`.
- AC-4: Zipped app opens on a second Mac without Gatekeeper warnings.

---

# v2 backlog: Shelf Actions (M6)
Next version only. Starts after v1 ships (T-11 DONE; T-12 may still be BLOCKED). Stories: PRD §10 (US-11..US-14).
Design: ARCHITECTURE §11 + ADR-014. Every v2 task also meets PRD common ACs AC-C1..AC-C6 and the implicit ACs above.

| ID | Title | Milestone | Depends on | Stories | Status |
|---|---|---|---|---|---|
| V2-01 | Zip + ActionRunner + Actions menus | M6 | T-11 | US-11, common | DONE (2026-10-23) |
| V2-02 | Share and AirDrop | M6 | V2-01 | US-13 | DONE (2026-10-23) |
| V2-03 | Convert and resize images (ImageIO) | M6 | V2-01 | US-14 | DONE (2026-10-23) |
| V2-04 | Rename shelf items | M6 | V2-01 | US-12 | DONE (2026-10-23) |
| V2-05 | Custom image resize (Pixels/Percent, aspect lock) | M6 | V2-03 | US-14 | DONE (2026-10-23) |
| V2-06 | Paste clipboard into DragShelf | M7 | V2-05 | US-2 | DONE (2026-10-24) |
| V2-07 | Text ↔ .txt (dual drag-out, Use as Text, Save as .txt) | M7 | V2-06 | US-4 | DONE (2026-10-24) |
| V2-08 | Pin items (persist across Clear, drag out, quit) | M7 | V2-07 | US-6 | TODO |
| V2-09 | Custom global shortcut (Settings recorder) | M7 | T-09 | US-8 | DONE (2026-10-24) |
| V2-10 | Search and filter | M7 | V2-08 | US-6 | TODO |

Order reason: V2-01 builds the shared runner, progress/cancel UI, and menus with the simplest action.
V2-02 is the riskiest UI (AirDrop from a non-activating panel), so it goes early. V2-04 last: text editing in the panel touches focus.

## V2-01 Zip + ActionRunner + Actions menus
Milestone M6. Depends on: T-11. `Actions/ActionRunner.swift`, `Actions/Zipper.swift`, `UI/ActionsMenu.swift`.
- AC-1: Header "Actions" menu (`ellipsis.circle`, glass on macOS 26) and tile context menu both show "Compress"; target = selection, else all (header) / clicked item (context).
- AC-2: 1 item → `<name>.zip`; 2+ items → `Archive.zip`; zip added at end and selected; sources stay (PRD US-11 AC-1, AC-4).
- AC-3: Unit test: zip 2 temp files + 1 folder, extract with `ditto -x -k` into a temp dir, contents byte-equal and names equal.
- AC-4: Link/text items skipped; panel caption says "Skipped n items" (US-11 AC-3).
- AC-5: Header shows progress + Cancel while running; Cancel terminates `ditto` within 1 s; unit test: cancelled job leaves no files under the test cache root.
- AC-6: Second action while one runs is disabled; Clear during a job cancels it and adds nothing (unit test with `generation`).
- AC-7: Failure (e.g. source deleted mid-job) shows a one-line error and leaves no partial zip.
- AC-8: Originals unchanged (path, name, mtime) after zipping.

## V2-02 Share and AirDrop
Milestone M6. Depends on: V2-01. Additions to `UI/ActionsMenu.swift` only.
- AC-1: "Share…" (`ShareLink`) shows the system share picker with file, link, and text items (US-13 AC-1).
- AC-2: "AirDrop" calls `NSSharingService(named: .sendViaAirDrop)`; disabled when `canPerform(withItems:)` is false.
- AC-3: Manual: AirDrop 2 files to a nearby device delivers both with names (US-13 AC-3).
- AC-4: Picker/sheet appears in front of other apps; panel stays visible while it is open. If `NSApp.activate()` is needed, it is called only for this action (documented in the code).
- AC-5: Items stay on the shelf after sharing.

## V2-03 Convert and resize images (ImageIO)
Milestone M6. Depends on: V2-01. `Actions/ImageConverter.swift`, menu entries.
- AC-1: "Convert To ▸" lists HEIC, JPEG, PNG, TIFF filtered by `CGImageDestinationCopyTypeIdentifiers()`; "Resize ▸" lists 512/1024/2048/3840 px. Both disabled when the target has no image items.
- AC-2: Unit test: a generated 4000×3000 image → each format; read back with `CGImageSource`: type matches, longest edge matches preset, 300×200 source is not upscaled.
- AC-3: Unit test: transparent PNG → JPEG; corner pixel is white.
- AC-4: Unit test: source with GPS EXIF → output has no `{GPS}` properties; source with orientation 6 → output upright (width/height swapped, orientation 1 or absent).
- AC-5: Output names per US-14 AC-3; outputs added and selected; sources stay.
- AC-6: Batch of 20 shows "n of 20"; Cancel stops after the current image and keeps finished outputs.
- AC-7: WebP input converts; no WebP/AVIF output offered (OQ-22).

## V2-04 Rename shelf items
Milestone M6. Depends on: V2-01. `Actions/Renamer.swift`, `ShelfStore.replace(id:with:)`, tile caption edit.
- AC-1: Context menu "Rename" and Return on one selected file item open an inline text field with the base name selected; panel becomes key without activating the app.
- AC-2: Return/click-away commits, Esc cancels (Esc does not also hide the panel while editing).
- AC-3: Unit test `Renamer.validate`: rejects empty, `/`, `:`, leading `.`, names > 255 UTF-8 bytes; accepts Unicode and spaces.
- AC-4: Unit test: cached item renamed in place (same item dir, old name gone); original item → new cached clone with the new name, original path still exists with the old name.
- AC-5: Renamed item keeps its id, index, and selection (unit test on `replace(id:with:)`).
- AC-6: Drag out of a renamed item delivers the new name with identical contents (manual, Finder).
- AC-7: Rename disabled for link, text, and missing items.
- AC-extra (carried from V2-01 QA): new shelf files never collide by name: a second "Archive.zip" (or a rename/convert output) gets a Finder-style suffix ("Archive 2.zip") when an item with that name is already on the shelf.
- Follow-up (from V2-04 QA, do after V2-03 merge): compare names NFC-normalized in `uniqueName`; reject "\0" in `validate`; validate the final name again after the " 2" suffix.

