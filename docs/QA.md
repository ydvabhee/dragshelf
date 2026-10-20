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
