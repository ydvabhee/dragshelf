# DragShelf — Open Questions

User was away; defaults were picked so work is not blocked. Change any default by answering here;
product-architect then updates PRD/ARCHITECTURE/TASKS.

| ID | Question | Default chosen | Impact if changed |
|---|---|---|---|
| OQ-01 | License and price: free/open source or paid? | Free, no license file yet | Paid needs licensing/trial code (new task) and affects PRD positioning only |
| OQ-02 | Bundle identifier / team name? | `com.abhishekyadav.DragShelf` | Cheap now; after release it resets UserDefaults, login item, and TCC state. Change before T-12 |
| OQ-03 | Should items survive app quit or reboot? | No. Memory only, cache wiped on launch/quit (ADR-010) | Persistence needs security-scoped/regular bookmarks + storage; new task, ~1 day |
| OQ-04 | Hotkey: which default, and customizable? | Fixed ⌃⌥⌘D, on/off only | Custom recorder UI = new task in M4; changing the default key is trivial |
| OQ-05 | Drag out of an original file: copy or move? | Copy only; originals never moved (ADR-007) | Allowing move (e.g. with ⌘ held) touches user data; needs ADR + extra QA |
| OQ-06 | App icon? | None in MVP (generic icon; menu bar uses SF Symbol) | Adds asset catalog + `ASSETCATALOG_COMPILER_APPICON_NAME`; small task before M5 |
| OQ-07 | Auto-show trigger: every content drag or a gesture (shake/modifier)? | Every content drag with a non-window drag pasteboard | Shake/modifier = new DragMonitor logic; may be needed if users find auto-show noisy |
| OQ-08 | Remove items after successful drag out by default? | Yes; setting "Keep items after drag out" (off) | Flip the default only; no code impact |
| OQ-09 | Default shelf position? | Right edge of the cursor's screen, vertically centered | Default only; options already planned (left edge, near cursor) |
| OQ-10 | Minimum macOS? | macOS 14.0, Liquid Glass on 26 (ADR-002) | macOS 26-only removes fallback branch; macOS 13 would need `ObservableObject` instead of `@Observable` |
| OQ-11 | Max items on shelf? | No hard limit; tested to 50 | A cap needs UI for "shelf full"; only if memory becomes a problem |
| OQ-12 | Distribution channel and who signs? | Developer ID + notarization by user (T-12 BLOCKED); no App Store | App Store needs sandbox + bookmarks: new ADR, rework of drop/promise/cache code |
| OQ-13 | Text items: drag out as text only, or also as a `.txt` file? | Text only (`NSString`); Finder makes a text clipping | Adding a file representation = small change in `DragOutSource.writer` |
| OQ-14 | Localization? | English only, but all UI strings via `String(localized:)` | Adding languages later = string catalog only |
| OQ-15 | Xcode broken (`xcodebuild` exits 70: stale `/Library/Developer/PrivateFrameworks/DVTDownloads`). Run `sudo xcodebuild -runFirstLaunch`? | SwiftPM build (ADR-013), unaffected; no xcodeproj | After the fix: open `Package.swift` in Xcode for debugging/Instruments; universal (arm64+x86_64) release build becomes possible for M5. No architecture change needed |
