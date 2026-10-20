# DragShelf — Tasks

Ordered. One task per developer run. Each task leaves build + tests green and is committed alone.
Status: `TODO` → `IN PROGRESS` → `QA` → `DONE` (or `BLOCKED`). Stories: `docs/PRD.md`. Design: `docs/ARCHITECTURE.md`.

Every task's implicit ACs (QA checks always):
- `swift build` (zero warnings), `swift test`, and `scripts/build-app.sh` (ARCHITECTURE §3) all succeed; manual checks run `open build/DragShelf.app`.
- No permission prompt appears. No new dependency. New UI uses SF Symbols, system fonts, VoiceOver labels.

| ID | Title | Milestone | Depends on | Stories | Status |
|---|---|---|---|---|---|
| T-01 | Project skeleton + menu bar item + CLI build/test green | M0 | — | US-8 (part) | DONE (2026-10-20) |
| T-02 | Shelf model: ShelfItem, ShelfStore, ItemCache | M1 | T-01 | US-2, US-6 (model) | DONE (2026-10-20) |
| T-03 | Floating ShelfPanel with Liquid Glass UI shell | M1 | T-02 | US-3, US-10 | DONE (2026-10-20) |
| T-04 | Drop in: files, folders, links, text, image data | M1 | T-03 | US-2 | DONE (2026-10-20) |
| T-05 | Drop in: file promises | M1 | T-04 | US-2 | TODO |
| T-06 | Drag out: single, multi-select, drag all, Cmd-C | M2 | T-04 | US-4, US-5 | TODO |
| T-07 | Manage items: remove, clear, missing files, Quick Look, keyboard | M2 | T-06 | US-6, US-7 | TODO |
| T-08 | Auto-show/hide on drag (DragMonitor) | M3 | T-03, T-04 | US-1 | TODO |
| T-09 | Global hotkey ⌃⌥⌘D | M3 | T-03 | US-8 | TODO |
| T-10 | Settings window + launch at login | M4 | T-06, T-08, T-09 | US-9 | TODO |
| T-11 | Accessibility and motion polish pass | M4 | T-07, T-10 | US-10 | TODO |
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
- AC-5: Successful drop → dragged items removed (cached dirs deleted); cancelled drag (Esc / drop on nothing) → items stay. Shelf hides when it becomes empty.
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

## T-09 Global hotkey ⌃⌥⌘D
Milestone M3. Depends on: T-03.
- AC-1: ⌃⌥⌘D toggles the panel from any frontmost app, including a full-screen app.
- AC-2: No permission prompt.
- AC-3: Menu "Show Shelf" shows the shortcut ⌃⌥⌘D.
- AC-4: If registration fails (shortcut taken), app keeps running and logs it; menu item still works.

## T-10 Settings window + launch at login
Milestone M4. Depends on: T-06, T-08, T-09. `SettingsView` (SwiftUI `Form`, `.formStyle(.grouped)`).
- AC-1: Launch at login toggle calls `SMAppService.mainApp.register/unregister`; toggle reflects real status after relaunch.
- AC-2: Auto-show on drag toggle (default on) starts/stops `DragMonitor` immediately.
- AC-3: Shelf position picker: Right edge (default), Left edge, Near cursor; next show uses it.
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

## T-12 Developer ID signing + notarization — BLOCKED
Milestone M5. Depends on: T-11. **Blocked on user:** needs a Developer ID Application certificate in the keychain and `notarytool` credentials (Apple ID app-specific password or API key).
- AC-1: `scripts/build-app.sh release` signs with the Developer ID identity, hardened runtime, `--timestamp`.
- AC-2: `xcrun notarytool submit --wait` returns Accepted; `xcrun stapler staple` succeeds.
- AC-3: `spctl -a -vv DragShelf.app` reports `source=Notarized Developer ID`.
- AC-4: Zipped app opens on a second Mac without Gatekeeper warnings.
