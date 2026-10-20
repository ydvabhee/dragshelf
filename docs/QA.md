# QA

Build cmds: `swift build && swift test && scripts/build-app.sh`. No xcodebuild (ADR-013).

## T-01 skeleton (commit ca1a1a4): PASS
Automated (done by QA):
- AC-1 clean `swift build`: 0 warnings.
- AC-2 `swift test`: 1 Swift Testing test passes.
- AC-3 debug + release `build-app.sh` ok; codesign `flags=0x10002(adhoc,runtime)`; Info.plist keys match ARCHITECTURE §3.
- AC-4 (partial) app launches, alive after 3s, ApplicationType=UIElement.
- AC-6 Package.swift matches §3. AC-7 .gitignore ok, no .xcodeproj.

Manual (user):
1. `open build/DragShelf.app`. Tray-in icon appears in menu bar; no Dock icon; no app menu bar.
2. Click icon. "Show Shelf" greyed out.
3. "Settings…" opens empty Settings window in front, app active.
4. Press ⌘Q with menu open, or click "Quit DragShelf": app exits, icon gone.
5. Light + dark menu bar: icon legible.

## T-02 Shelf model (PASS, re-verified d73f802, 26ab8de)
Auto: build, test (6 pass), build-app.sh ok. Launch wipe verified.
Fixed: dedupe normalizes `..`/symlinks (test); nested cached file deletes root child dir (test); MainActor via `.defaultIsolation(MainActor.self)` in Package.swift, accepted.
Tests use temp root only.

Manual (user):
1. Quit via menu: confirm cache dir empty (`ls ~/Library/Caches/com.abhishekyadav.DragShelf/Shelf`). (SIGTERM skips willTerminate; only menu Quit covers AC-5 quit.)

## T-03 Floating panel + Liquid Glass shell (PASS, c5caff8)
Auto: build, test (7 pass), build-app.sh ok. No NSApp.activate in panel path (only Settings). `#available` only in Glass.swift. Reduce Motion/Transparency/Increase Contrast handled in code. Header icons + tiles have VoiceOver labels.
Snapshots (offscreen, `DRAGSHELF_SNAPSHOT_DIR=... swift test`): colors in code are semantic (.secondary/.tertiary/default primary), but offscreen render shows black text in dark and white icons in light. Offscreen NSHostingView in an unshown NSWindow does not propagate appearance to SwiftUI; treat as artifact, confirm on screen (steps 7-8). Glass never renders offscreen.
Known gaps: Esc hides only when panel is key (non-activating panel rarely is) -> deferred to T-07 keyboard; drag-all button no action until T-06. Controller<->panel<->hosting view is a strong cycle (app-lifetime singleton, harmless).

Manual (user):
1. Menu "Show Shelf": panel at right edge, vertically centered, on the display containing the cursor. Menu item becomes "Hide Shelf".
2. Frontmost app (e.g. TextEdit) stays frontmost and its window stays key after show and after clicking panel/Close.
3. Cmd-Tab, switch Spaces, open a full-screen app: panel stays visible on top.
4. macOS 26: glass background, 22 pt corners, circular glass header buttons. macOS 14-15 (if available): vibrant material.
5. Empty: tray icon + "Drop here"; Drag All and Clear disabled. Close hides. Esc: note whether it works (expected only if panel is key).
6. System Settings > Accessibility > Display: Reduce Motion -> fade only, no scale; Reduce Transparency -> opaque panel; Increase Contrast -> border.
7. Light mode: text/icons legible on glass over light and dark wallpapers.
8. Dark mode: same. Title/captions must be light, not black.
9. VoiceOver: Drag All, Clear Shelf, Close announced; tiles read "<type>, <name>".
10. Two displays: show with cursor on each.

## Manual drag/drop matrix (fill from T-04 on)
Per cell check: shelf appears on drag start, accepts drop, stays on top across app switch,
drag out gives right content, removal works, cache empty after clear/quit.

| Source \ Target | Finder | Slack/Messages | Browser upload | Mail compose | Hidden/minimized app | Other Space / full screen |
|---|---|---|---|---|---|---|
| Finder 1 file | | | | | | |
| Finder many files | | | | | | |
| Finder folder | | | | | | |
| Safari/Chrome image | | | | | | |
| Safari/Chrome link | | | | | | |
| Safari/Chrome selected text | | | | | | |
| Mail attachment | | | | | | |
| Photos | | | | | | |
| Desktop item | | | | | | |

## Edge cases (every task)
Multi-display, Stage Manager, full-screen app, Space switch mid-drag, Esc cancel, huge file,
file deleted while on shelf, duplicate items, dark mode, VoiceOver labels.

## T-04 Drop in (manual)
Auto: `PasteboardReaderTests`, `DropReceiverTests` (fake NSDraggingInfo: 2 files + text -> 3 items). Real drag delivery is manual only.
1. Finder: drag 1 file, 5 files, 1 folder onto shelf -> 1, 5, 1 tiles. Originals untouched. Cursor shows copy badge (not move/link).
2. Safari/Chrome: drag an image -> PNG tile; file under `~/Library/Caches/com.abhishekyadav.DragShelf/Shelf/<UUID>/`. Drop same image again -> no 2nd tile, no orphan dir.
3. Drag a link -> link tile. Drag selected text -> text tile, first line shown. Drop same text twice -> 1 tile.
4. While hovering: accent border + tint appear; leave panel or press Esc -> clears. After drop -> clears.
5. Hover with Reduce Motion on: note whether the highlight still springs (known: not gated).
6. 50 files: all tiles show, grid scrolls. Drop onto the scrolling grid area as well as the header: both accept.
7. Drop while another app is frontmost: it stays frontmost, shelf does not steal focus.
8. VoiceOver: tile reads "<type>, <name>". Thumbnails: file = QuickLook or icon, link `link`, text `text.alignleft`.
9. Mail attachment / Photos: expected to NOT work until T-05 (file promises).

Matrix rows for T-04 (drop-in only): Finder 1/many/folder, Safari image/link/text, Desktop item.
Drag-out columns wait for T-06.

## T-05 Drop in: file promises (manual)
Auto: `finishPromiseAddsCachedFile`, `finishPromiseFailureLeavesNoDir`, `draggingUpdatedRejectsUnacceptableDrag`. Real promises are manual only.
Precedence: real file URLs on pasteboard beat promises; promises beat image/url/text. Known: promise + image in same drag (Safari/Chrome image) now yields the promised file, not raw image data.
1. Mail: drag 1 attachment, then 2 attachments -> tile(s) with original filename(s); file under `.../Shelf/<UUID>/<name>`.
2. Photos: drag 1 photo, then 3 photos -> file tiles; filenames from Photos.
3. Safari/Chrome: drag image from page -> tile appears (file or PNG), no orphan dir. Note which.
4. Large file: drag 100 MB+ promised file (Mail big attachment / Photos video) -> shelf stays scrollable/responsive while writing; tile appears after write.
5. Failure: drag attachment from Mail while offline (not downloaded) -> no tile; Console (subsystem `com.abhishekyadav.DragShelf`, category `drop`) shows "promise failed"; `ls Shelf/` has no empty UUID dir.
6. Race: start big promise drop, press Clear (or quit) before it finishes -> shelf stays empty, `Shelf/` empty after. (Expected FAIL-ish: see finding, low.)
7. Hover a rejected drag (e.g. empty/unsupported type) -> no copy badge, no highlight.
Matrix rows for T-05: Mail attachment, Photos (drop-in only).

## T-06 Drag out, multi-select, Cmd-C (manual)
Auto: `DragOutSourceTests` (writer types, copy-only mask, end-of-session removal, select/shift/cmd), `DropReceiverTests` (self-drop rejected). Real sessions are manual only.
Deviation (manager-approved): AC-5 text says "cached dirs deleted" on drop; actual: item leaves shelf, cache dir stays until Clear/quit/next launch (receivers read file after drop). TASKS.md AC-5 needs this wording.
Known for T-07: tile handle overlay is an AppKit view above the tile; hover xmark and context menu "Remove" must be verified to still work (right-click is not forwarded explicitly).
1. Finder: drag 1 file tile to a Finder folder -> copy appears, cursor copy badge, tile leaves shelf. Dir still under `.../Shelf/<UUID>/` (expected) if the item was cached.
2. Same-volume original: drop a non-cached file tile into another folder on the same volume -> copied, original stays, even with Cmd/Option held.
3. Mail compose, Messages/Slack, browser upload field: drag file tile -> attached/uploaded with correct content.
4. Link tile -> browser address bar = URL; -> Finder = .webloc. Text tile -> TextEdit = text.
5. Click tile = select; Cmd-click toggles; Shift-click selects range; click empty grid space deselects. Click without moving never starts a drag; move >= 3 pt does.
6. Select 3, drag one selected tile -> all 3 drop; plain-click one selected tile of 3 without moving -> selection collapses to it on mouse up. Drag unselected tile while others selected -> only that one.
7. Drag All button -> every item drops (5 files into a Finder folder -> 5 files). Button with empty shelf does nothing.
8. Cancel: Esc mid-drag, and drop on desktop-less empty area/menu bar -> items stay. Drop onto the shelf itself -> rejected (no badge), items stay, no duplicate.
9. Remove on success: after the last item drops, panel hides. Change selection (Cmd-click) during a drag is not possible; check only dragged items left the shelf when 5 items on shelf and 2 dragged.
10. Cmd-C: click a tile (panel becomes key), Cmd-C, paste in Finder/TextEdit -> file/text pasted. With nothing selected, Cmd-C does nothing. Cmd-C while another app has keyboard focus (panel not key) goes to that app (expected).
11. Focus: with TextEdit frontmost, drag from shelf. DragShelf never appears in Cmd-Tab/Dock, menu bar stays TextEdit's. Note: tile mouse-down makes the panel key, so typing goes to the panel until you click the other app's window.
12. Multi-display, full-screen app target, Space switch mid-drag, large file drag.
Matrix rows for T-06: all targets x drag out; item removal = removed on success, kept on cancel; cache = survives drop, gone after Clear/quit.

## T-08 Auto-show/hide on drag, top-center placement (manual)
Auto: `AutoShowTests` (start rule: pasteboard written since mouse-down + >= 10 pt; top-center frame math; hide rule). Real drags are manual only. `swift build` + `swift test` green (27 tests). `scripts/build-app.sh` not run by QA (user's instance was running).
Design notes: baseline `changeCount` taken at every mouse-down; poll timer (0.1 s) exists only during an active drag; hide = 300 ms grace + 0.2 s fade (AC-3 "500 ms" is borderline).
Findings (see verdict): failed promise drop leaves empty panel open; notch + full-screen placement unverified; second drag ending within 300 ms of the first shortens grace.
1. Fresh install: `tccutil reset All com.abhishekyadav.DragShelf`, launch. No Accessibility/Input Monitoring prompt ever (AC-7).
2. Finder: drag 1 file >= 10 pt -> panel appears top center, <= 300 ms. Repeat: Safari/Chrome image, link, selected text (AC-1, AC-9).
3. Placement: horizontally centered, 12 pt below menu bar. Add 1, then 6+ items -> top edge stays fixed, panel grows downward. Menu "Show Shelf" -> same spot (AC-9).
4. No false positives: drag a window by title bar, resize a window, Finder marquee select, select text in a page, scrollbar drag, slider drag, click-hold without moving -> panel never shows (AC-2).
5. Cancel/no drop: drag a file, release over empty desktop, shelf empty -> panel hides <= 500 ms. Esc mid-drag -> same (AC-3).
6. Drop on shelf: drag file onto the shown panel -> stays open. Next drag + release elsewhere (items present) -> stays (AC-3).
7. Manual show then drag: open via menu, drag a file elsewhere and release -> panel stays (AC-5). Close it, repeat -> auto hide.
8. Drag out of shelf: drag a tile out to Finder; no flicker/re-show, with 1 item the panel hides because shelf is empty (AC-6).
9. Two displays: cursor on display 2, start a drag -> panel on display 2, top center of that display (AC-4). Repeat with display 1.
10. Notch Mac / menu bar autohide: panel not under notch in normal and full-screen app; with autohide menu bar, panel not covered. Report result.
11. Quick re-drag: drag, release (no drop), start a new drag within 300 ms -> panel stays during second drag.
12. CPU: Activity Monitor, idle 60 s, DragShelf ~0%. Move/click a lot without dragging -> still ~0%.
13. Promise failure: drop a Mail attachment that is not downloaded (offline) -> expect panel hides; currently stays empty (known finding).
14. Other apps: drag from Mail attachment, Photos, Desktop; test lazy writers (Chrome/Electron): does panel show within 300 ms?
15. AC-8: no UI until T-10; code check only (`stop()` removes monitor + timer).
Matrix rows for T-08: all sources x "shelf appears on drag start".
