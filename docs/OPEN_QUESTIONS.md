# DragShelf — Open Questions

User was away; defaults were picked so work is not blocked. Change any default by answering here;
architect then updates PRD/ARCHITECTURE/TASKS.

| ID | Question | Default chosen | Impact if changed |
|---|---|---|---|
| OQ-01 | License and price: free/open source or paid? | **RESOLVED by user: free; 2026-10-23: public repo for now, license not chosen yet** (no LICENSE file; README says so) | Paid needs licensing/trial code (new task) and affects PRD positioning only |
| OQ-02 | Bundle identifier / team name? | **RESOLVED by user 2026-10-23: keep** `com.abhishekyadav.DragShelf` (user wrote "OQ-32 skip"; read as OQ-02, keep default) | Cheap now; after release it resets UserDefaults, login item, and TCC state. Change before T-12 |
| OQ-03 | Should items survive app quit or reboot? | No. Memory only, cache wiped on launch/quit (ADR-010) | Persistence needs security-scoped/regular bookmarks + storage; new task, ~1 day |
| OQ-04 | Hotkey: which default, and customizable? | **RESOLVED by user 2026-10-24: customizable** → V2-09 | Custom recorder UI = new task in M4; changing the default key is trivial |
| OQ-05 | Drag out of an original file: copy or move? | **RESOLVED by T-15 (user 2026-10-20): plain drag copies, ⌘-drag moves.** | Allowing move (e.g. with ⌘ held) touches user data; needs ADR + extra QA |
| OQ-06 | App icon? | **RESOLVED 2026-10-23: icon designed** (file card into tray, blue squircle; `scripts/make-icon.swift` → `Resources/AppIcon.icns`) | Adds asset catalog + `ASSETCATALOG_COMPILER_APPICON_NAME`; small task before M5 |
| OQ-07 | Auto-show trigger: every content drag or a gesture (shake/modifier)? | Every content drag with a non-window drag pasteboard | Shake/modifier = new DragMonitor logic; may be needed if users find auto-show noisy |
| OQ-08 | Remove items after successful drag out by default? | **RESOLVED by user 2026-10-20: removed** after drag out (setting "Keep items after drag out" stays, off) | Flip the default only; no code impact |
| OQ-09 | Default shelf position? | **RESOLVED by user 2026-10-20: top center** of the cursor's screen, below the menu bar / notch | Default only; options already planned (left edge, near cursor) |
| OQ-10 | Minimum macOS? | macOS 14.0, Liquid Glass on 26 (ADR-002) | macOS 26-only removes fallback branch; macOS 13 would need `ObservableObject` instead of `@Observable` |
| OQ-11 | Max items on shelf? | **RESOLVED → see OQ-30: no limit (measured).** | A cap needs UI for "shelf full"; only if memory becomes a problem |
| OQ-12 | Distribution channel and who signs? | Developer ID + notarization by user (T-12 BLOCKED); no App Store | App Store needs sandbox + bookmarks: new ADR, rework of drop/promise/cache code |
| OQ-13 | Text items: drag out as text only, or also as a `.txt` file? | **RESOLVED by user 2026-10-24: both, receiver decides** (string + .txt promise; Use as Text / Save as .txt) → V2-07 | Adding a file representation = small change in `DragOutSource.writer` |
| OQ-14 | Localization? | English only, but all UI strings via `String(localized:)` | Adding languages later = string catalog only |
| OQ-15 | Xcode broken (`xcodebuild` exits 70: stale `/Library/Developer/PrivateFrameworks/DVTDownloads`). Run `sudo xcodebuild -runFirstLaunch`? | SwiftPM build (ADR-013), unaffected; no xcodeproj | After the fix: open `Package.swift` in Xcode for debugging/Instruments; universal (arm64+x86_64) release build becomes possible for M5. No architecture change needed |
| OQ-16 | Same image dropped twice creates two items (each cached at its own path). Dedupe by content hash? | **RESOLVED by user 2026-10-20: yes, merge; new drop replaces the old item** (moves to newest position) | Hash-based dedupe = small change in `DropReceiver.writeImage` + `ShelfStore.add` |
| OQ-17 | v2 Rename: rename the real file on disk (like Finder), or only the shelf copy? | **Shelf copy only.** Original untouched; a renamed original becomes an APFS clone in the cache with the new name (ADR-014) | Renaming originals is instant and saves disk, but it changes user data (breaks paths other apps use, fails on locked/read-only files, needs undo). Copy is a full copy across volumes (slow for big files) |
| OQ-18 | v2 Zip: what happens to link and text items in the selection? | Skipped, with "Skipped n items" | Including them as `.webloc` / `.txt` files is a small change in `Zipper` staging |
| OQ-19 | v2 Zip: keep source items on the shelf after zipping? | Yes; zip added and selected | Removing sources = one line; risky if the user still wants the originals |
| OQ-20 | v2 Convert/Resize: replace the source item or add a new one? | Add a new item; source stays | Replace = use `replace(id:with:)`; less clutter, but the original is gone from the shelf |
| OQ-21 | v2 Convert/Resize: keep metadata (EXIF, GPS, camera)? | Strip all metadata, keep color profile and apply orientation (privacy) | Keeping metadata = pass source properties minus orientation to `CGImageDestinationAddImage`; leaks location |
| OQ-22 | v2 Formats: WebP and AVIF output? | No. ImageIO on macOS 26.5 cannot write WebP (checked: writers are JPEG, PNG, TIFF, JPEG-2000, HEIC, HEICS, AVIF). AVIF is writable but not offered | WebP output needs libwebp (breaks ADR-001). AVIF is one line in `writableTypes` |
| OQ-23 | v2 Resize: presets only, or a custom size and quality? | **RESOLVED by user 2026-10-23: presets + Custom…** (Pixels/Percent, aspect lock; custom may upscale) → V2-05 | Custom size/quality needs a small popover UI; new task |
| OQ-24 | v2 Rename: Return key to rename (Finder) conflicts with nothing today. Also double-click? | Return and context menu only | Double-click to rename would conflict with a future "open" action |
| OQ-25 | v2 Share/AirDrop: remove items after sharing? | No, keep them. Share completion does not reliably confirm delivery | Removing = hook `NSSharingServiceDelegate` `didShareItems`; risk of losing items on a failed AirDrop |
| OQ-26 | T-14 promo feed: final feed URL and allowlisted domain(s)? **User must provide before release (T-12).** | Placeholder `https://example.com/dragshelf/promos.json`, allowlist `["example.com"]` | Change 2 constants in `PromoFeed.swift`. Shipping the placeholder means promos never appear and cannot be fixed without an app update |
| OQ-27 | T-14 promo placement? | One-line footer under the shelf grid (hidden during drags, ✕ per promo) + "More Apps" submenu in the menu bar menu | Menu-only is less visible but never in the shelf; Settings-only is nearly invisible. Small UI change either way |
| OQ-28 | T-14 promos on by default? | On, with Settings toggle "Show other apps from the developer" | Off by default = fewer views, no network request until the user opts in |
| OQ-29 | T-14: hide promos for apps the user already has installed? | No (schema has no promoted-app bundle id) | Add optional `appBundleId` to the schema and check `NSWorkspace.urlForApplication(withBundleIdentifier:)` locally; no data leaves the Mac |
| OQ-30 | Item limit on the shelf? | **RESOLVED (measured) 2026-10-20: no limit** after O(1) dedupe (T-13). 5000 items: 0.05 ms/add, 8 ms UI update, +3 MB | Revisit only if a real user hits a problem |
| OQ-31 | PRD US-8 draft listed a "Clear Shelf" menu bar item; no task built it. Add "Clear DragShelf" to the menu? | **RESOLVED by user 2026-10-23: skip** (Clear stays in the panel header only) | One `Button` in `DragShelfApp` calling `store.clear()` + hide; small task |
