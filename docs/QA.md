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

## T-02 Shelf model (FAIL)
Auto: build, test (4 pass), build-app.sh ok. Launch wipe verified: dummy dir in cache gone after `open` + 2s.
Findings:
- ShelfStore.add dedupe uses URL ==. Trailing slash same. `/tmp/x` vs `/private/tmp/x` and `a/../b` NOT deduped. Fix: compare `.standardizedFileURL.resolvingSymlinksInPath()`.
- ShelfStore not `@MainActor`. Fix: annotate store (+ tests).
- removeCacheDir only deletes direct child of root; nested file (root/uuid/sub/f) leaks. Low. Fix: walk to root's direct child.
- Path traversal: `..` safe (standardized check, stays inside root). Symlink in item path not resolved, low.
- Tests use temp root only; real cache untouched.

Manual (user):
1. Quit via menu: confirm cache dir empty (`ls ~/Library/Caches/com.abhishekyadav.DragShelf/Shelf`). (SIGTERM skips willTerminate; only menu Quit covers AC-5 quit.)

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
