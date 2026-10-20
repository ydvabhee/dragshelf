# DragShelf — Architecture

Status: draft v1 (2026-10-20). Scope: `docs/PRD.md`. Tasks: `docs/TASKS.md`.

## 1. Stack
- Swift 6 language mode, strict concurrency, default actor isolation `MainActor`.
- AppKit: shelf panel, drop destination, drag source, event monitors, Quick Look.
- SwiftUI: shelf content, menu bar menu (`MenuBarExtra`), Settings window.
- Frameworks only from the SDK: AppKit, SwiftUI, QuickLookUI, QuickLookThumbnailing,
  UniformTypeIdentifiers, ServiceManagement, Carbon (hotkey only). **No third-party deps.**
- Toolchain on dev machine: macOS 26.5, Xcode 26.6, SDK macOS 26.5, Swift 6.3.3. Build with SwiftPM (ADR-013);
  `xcodebuild` is broken on this machine (OQ-15). No xcodegen/tuist.
- Deployment target: **macOS 14.0** (ADR-002).

## 2. Project layout
SwiftPM package (ADR-013). No `.xcodeproj`. Any file added under `Sources/DragShelf/` or
`Tests/DragShelfTests/` joins its target automatically. Open `Package.swift` in Xcode once Xcode works (OQ-15).

```
Package.swift                                 # tools 6.2, .macOS(.v14), no dependencies
scripts/
  build-app.sh                                # swift build + assemble/sign build/DragShelf.app
Sources/DragShelf/                            # executableTarget DragShelf
  App/
    DragShelfApp.swift        # @main SwiftUI App: MenuBarExtra + Settings scenes, AppDelegate adaptor
    AppDelegate.swift         # owns ShelfStore, ShelfPanelController, DragMonitor, HotKey; cache wipe
  Model/
    ShelfItem.swift           # item value type
    ShelfStore.swift          # @Observable item list, selection, add/remove/clear, dedupe
    ItemCache.swift           # cache dir paths, per-item dirs, wipe
    Preferences.swift         # UserDefaults keys + defaults (@AppStorage keys)
  Panel/
    ShelfPanel.swift          # NSPanel subclass (config only)
    ShelfPanelController.swift# show/hide/position, owns hosting view, visibility rules
  Drag/
    PasteboardReader.swift    # NSPasteboard → [Incoming] (pure, unit-tested)
    DropReceiver.swift        # NSView: NSDraggingDestination, file promises; panel contentView
    DragOutSource.swift       # NSDraggingSource; ShelfItem → NSPasteboardWriting
    DragMonitor.swift         # global mouse monitors + drag pasteboard changeCount
    HotKey.swift              # Carbon RegisterEventHotKey wrapper
  UI/
    ShelfView.swift           # header (drag-all, clear, close), grid, empty state
    ShelfItemView.swift       # tile: thumbnail, name, remove button, a11y
    Glass.swift               # shelfBackground() modifier: Liquid Glass / material fallback
    Thumbnail.swift           # QLThumbnailGenerator + NSWorkspace icon fallback
    QuickLook.swift           # QLPreviewPanel data source for selected file items
    SettingsView.swift        # Form with the 5 settings (+ promo toggle, T-14)
    PromoFooter.swift         # one-line promo footer (T-14)
  Promos/
    PromoFeed.swift           # feed model, strict decode + validation, filter, daily pick (pure)
    PromoLoader.swift         # HTTPS fetch, ETag, disk cache, staleness (T-14)
Tests/DragShelfTests/                         # testTarget DragShelfTests (Swift Testing)
  ShelfStoreTests.swift
  ItemCacheTests.swift
  PasteboardReaderTests.swift
  DragOutSourceTests.swift
```
- No `main.swift` (it conflicts with `@main`). No resources, no asset catalog in MVP (menu bar icon = SF Symbol; app icon: OQ-06).
- `.gitignore` must contain `.build/`, `.swiftpm/`, `build/`.

## 3. Package, app bundle, and build settings
`Package.swift`:
- `// swift-tools-version: 6.2` (toolchain is Swift 6.3.3; 6.2 is the first manifest with `.defaultIsolation`).
- `platforms: [.macOS(.v14)]`; `executableTarget(name: "DragShelf")`; `testTarget(name: "DragShelfTests", dependencies: ["DragShelf"])`.
- Both targets: `swiftSettings: [.defaultIsolation(MainActor.self), .treatAllWarnings(as: .error)]`.
  Swift 6 language mode is the default for tools ≥ 6.0. If a setting fails to compile, fall back to
  explicit `@MainActor` / `-Xswiftc -warnings-as-errors` in the script, and note it in the task report.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`), `@testable import DragShelf`. Not hosted in the app:
  tests cover pure logic only and must not need a running `NSApplication`.

`scripts/build-app.sh [debug|release]` (default `debug`). `set -euo pipefail`. Steps:
1. `swift build -c <config>`.
2. Recreate `build/DragShelf.app/Contents/MacOS/`, copy `.build/<config>/DragShelf` binary into it.
3. Write `build/DragShelf.app/Contents/Info.plist` (heredoc), keys below.
4. `codesign --force --sign - --options runtime build/DragShelf.app` (ad-hoc, hardened runtime; no entitlements, no sandbox).
5. Print the app path. M5 adds the Developer ID identity, timestamp, `notarytool`, and stapler to this same script.

| Info.plist key | Value |
|---|---|
| `CFBundleIdentifier` | `com.abhishekyadav.DragShelf` (OQ-02) |
| `CFBundleName` / `CFBundleExecutable` | `DragShelf` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1` / `1` |
| `LSMinimumSystemVersion` | `14.0` |
| `LSUIElement` | `true` |
| `NSHumanReadableCopyright` | `© 2026 Abhishek Yadav` |

Commands (must stay green on every commit):
```
swift build                      # compile, zero warnings
swift test                       # all Swift Testing tests pass
scripts/build-app.sh             # assemble + ad-hoc sign build/DragShelf.app
open build/DragShelf.app         # run; never run the bare binary
```
- Always run the bundled app: `SMAppService`, `LSUIElement`, and the bundle id only work inside `DragShelf.app`.
- `ItemCache` uses the constant bundle id string, not `Bundle.main.bundleIdentifier` (nil under `swift test`).
- Build is native arm64 only. Universal binary is an M5 concern (OQ-15).

## 4. Key types
| Type | Kind | Responsibility |
|---|---|---|
| `DragShelfApp` | SwiftUI `App` | `MenuBarExtra("DragShelf", systemImage: "tray.and.arrow.down")` with menu style; `Settings { SettingsView() }`; `@NSApplicationDelegateAdaptor(AppDelegate.self)` |
| `AppDelegate` | `NSObject, NSApplicationDelegate` | Creates and wires store, panel controller, monitor, hotkey. `ItemCache.wipe()` on launch and terminate |
| `ShelfItem` | `struct`, `Identifiable, Hashable` | `id: UUID`, `kind: Kind`, `isCached: Bool`. `enum Kind { case file(URL), url(URL), text(String) }`. Images and promises are materialized to cache files → `.file` with `isCached = true` (ADR-012) |
| `ShelfStore` | `@Observable final class` | `items`, `selection: Set<UUID>`, `add(_:)` (dedupe by file path / URL / text), `remove(ids:)`, `clear()`, `missing(id:)`. Deletes cache dir of cached items on remove/clear |
| `ItemCache` | `enum` (static funcs) | `root` = `~/Library/Caches/<bundle id>/Shelf/`; `newItemDir() -> URL` = `root/<UUID>/`; `remove(dir:)`; `wipe()` |
| `Preferences` | `enum` keys + defaults | `autoShow` (true), `position` (`.topCenter`), `keepAfterDragOut` (false), `hotKeyEnabled` (true), `showPromos` (true, T-14), `dismissedPromoIDs` ([String], T-14). Launch at login is read from `SMAppService.mainApp.status`, never stored |
| `ShelfPanel` | `NSPanel` subclass | styleMask `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`, `hidesOnDeactivate = false`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `becomesKeyOnlyIfNeeded = true`, `canBecomeKey` → true (Space/Delete/Esc/arrows), `canBecomeMain` → false |
| `ShelfPanelController` | `final class` | `show(reason:)`, `hide()`, `toggle()`. Positions on screen with cursor per `Preferences.position`. Visibility rules below. Fade/scale animation honoring Reduce Motion |
| `DropReceiver` | `NSView` | Panel `contentView`; hosts `NSHostingView(rootView: ShelfView)` filling it. `registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes)`. Highlight state → store flag `isDropTargeted`. Uses `PasteboardReader` |
| `PasteboardReader` | `enum` (static funcs) | `read(_ pb: NSPasteboard) -> [Incoming]`. `enum Incoming { case file(URL), promise(NSFilePromiseReceiver), image(Data, UTType), url(URL), text(String) }`. Precedence per pasteboard item: file URL > file promise > image data > web URL > string. `canAccept(_ pb:) -> Bool` used by `DragMonitor` too |
| `DragOutSource` | `NSObject, NSDraggingSource` | `begin(items:event:view:)` → `beginDraggingSession` with one `NSDraggingItem` per item. `writer(for: ShelfItem) -> NSPasteboardWriting` (`NSURL` for file/url, `NSString` for text). Operation mask `.copy` (ADR-007). On `endedAt operation != []` and `!keepAfterDragOut` → `store.remove` |
| `DragMonitor` | `final class` | Global monitors `.leftMouseDragged`, `.leftMouseUp`. Callbacks `onDragStart(NSPoint)`, `onDragEnd()`. Stop/start with `Preferences.autoShow` |
| `HotKey` | `final class` | Carbon `RegisterEventHotKey` for ⌃⌥⌘D, `InstallEventHandler` → `onPress`. Unregister on disable/deinit |

## 5. Data flow
```
            drag starts anywhere                               user presses ⌃⌥⌘D / menu "Show Shelf"
                    │                                                         │
       DragMonitor (global mouse monitor,                               HotKey / MenuBarExtra
        drag pasteboard changeCount)                                          │
                    └──────────── onDragStart ──► ShelfPanelController ◄──────┘
                                                   show(on cursor screen)
                                                         │
 drop on panel ─► DropReceiver ─► PasteboardReader ─► [Incoming]
                       │                                 │ file/url/text → ShelfItem
                       │                                 │ image data    → write ItemCache dir → ShelfItem(.file, cached)
                       └ NSFilePromiseReceiver ─────────►│ promise       → receivePromisedFiles into ItemCache dir
                                                         ▼                 (background queue → MainActor add)
                                                    ShelfStore (@Observable)
                                                         │ observed by
                                                         ▼
                                              ShelfView / ShelfItemView (SwiftUI, Glass)
                                                         │ DragGesture on tile
                                                         ▼
                                     DragOutSource.begin(selected items, NSApp.currentEvent)
                                                         │ session ends with operation
                                                         ▼
                                   ShelfStore.remove (unless keepAfterDragOut) → cache dir deleted
                                   store empty → ShelfPanelController.hide()
```

### Panel visibility rules (ShelfPanelController)
1. `onDragStart` and auto-show on and panel hidden → show (reason `.autoDrag`).
2. `onDragEnd` and reason `.autoDrag` and store empty → hide after 300 ms grace
   (lets an in-flight drop or promise land first).
3. Hotkey/menu → toggle (reason `.manual`); never auto-hidden by rule 2.
4. Store becomes empty after remove/drag-out/clear → hide.
5. Close button / Esc → hide, items kept.
6. Never call `NSApp.activate` for the shelf. Only Settings activates the app.

### Drag-start detection (DragMonitor)
- On `.leftMouseDragged`: read `NSPasteboard(name: .drag).changeCount`. If it differs from the
  last seen value → remember it; if `PasteboardReader.canAccept` → `onDragStart(NSEvent.mouseLocation)`.
  Window moves/resizes do not write the drag pasteboard, so they never trigger.
- On `.leftMouseUp` after a start → `onDragEnd()`.
- Global monitors do not see our own app's events → our own drag-outs never re-trigger.
- Mouse global monitors need no permission (key monitors would; we use none).

### Cache directory
- `ItemCache.root` = `FileManager.default.urls(for: .cachesDirectory)[0]/com.abhishekyadav.DragShelf/Shelf/`.
- One subdir per item: `root/<item UUID>/<original filename>` keeps original names, no collisions.
- Image data with no filename → `Image <yyyy-MM-dd HH.mm.ss>.png` (or the source type's extension).
- Lifecycle: wiped on launch (crash leftovers), item dir deleted on remove, whole root wiped on clear and on `applicationWillTerminate`.
- Original user files are referenced, never copied.

## 6. UI design (Apple HIG)
- Panel: ~288 pt wide, height fits content from 160 pt up to 70% of screen visible height, then scrolls.
  Default top center: horizontally centered, 12 pt below `visibleFrame.maxY` (clears menu bar / notch) on the cursor's screen, anchored by its top edge so it grows downward. Right/Left edge: 12 pt from edge, vertically centered.
- Layout: header row (drag-all handle `square.stack.3d.up`, item count, Clear `trash`, Close `xmark`),
  then `LazyVGrid` of 3 tiles: 64 pt thumbnail + 2-line caption (`.caption`, middle truncation).
  Empty state: `tray.and.arrow.down` symbol + "Drop here".
- **macOS 26** (`if #available(macOS 26, *)`): panel background `.glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))`;
  header buttons in a `GlassEffectContainer` with `.buttonStyle(.glass)`; drop-target state uses `.glassEffect(.regular.tint(.accentColor.opacity(0.25)))`.
  Item thumbnails are content, not glass (no glass-on-glass).
- **macOS 14–15**: `NSVisualEffectView` (`material = .popover`, `blendingMode = .behindWindow`, **`state = .active`**
  so it stays vibrant in a non-key panel) clipped to a 16 pt continuous rounded rect, wrapped as `NSViewRepresentable`.
  Buttons `.buttonStyle(.borderless)`.
- All in one modifier `shelfBackground(isTargeted:)` in `Glass.swift`; no other file checks availability for styling.
- Reduce Transparency (`accessibilityReduceTransparency`) → solid `Color(nsColor: .windowBackgroundColor)`.
- Increase Contrast (`colorSchemeContrast == .increased`) → 1 pt `separatorColor` stroke.
- Motion: show/hide = opacity + 0.96→1 scale with `.spring(duration: 0.35, bounce: 0.15)`; insert/remove tiles
  `.transition(.scale.combined(with: .opacity))`. Reduce Motion → opacity only.
- Selection: system accent color ring; hover shows `xmark.circle.fill` remove button.
- VoiceOver: tile `accessibilityElement(children: .combine)`, label "<type description>, <name>"
  (`UTType.localizedDescription`), `accessibilityAction(named: "Remove")`, `"Quick Look"`; header buttons labeled.
- Fonts: system only (`.body`, `.caption`, `.headline`). Icons: SF Symbols only.

## 7. Permissions and security
- **None requested.** No Accessibility, Input Monitoring, Full Disk Access, Screen Recording.
- Global mouse monitors and Carbon hotkeys work without TCC permission. If QA ever sees a prompt, it is a bug.
- Files dropped by the user are readable without TCC prompts (user-intent grant), including Desktop/Documents/Downloads.
- Network: only the promo feed (T-14, §12): one HTTPS GET to a hardcoded URL, at most once per 24 h, none when promos are off. No identifiers, no analytics, no cookies. No user data leaves the machine.
- Cache dir holds copies of promised/image content only; always wiped (see §5).
- Drag out offers `.copy` only, so targets can never move or delete the user's originals.

## 8. Distribution
- Dev: `scripts/build-app.sh` ad-hoc signs (`codesign -s - --options runtime`). Hardened runtime on now so M5 needs no code change.
- M5 (**BLOCKED on user**): Developer ID Application cert (none on this machine), `notarytool` credentials,
  `scripts/build-app.sh release` → Developer ID sign → notarize → staple → zip/DMG. App Store/sandbox: future ADR.
- `SMAppService.mainApp` (launch at login) works best when the app lives in `/Applications`; QA tests it from there.

## 9. Risks
| Risk | Mitigation |
|---|---|
| Global `.leftMouseDragged` monitor may not fire during some apps' drag sessions | T-08 verifies with the QA matrix sources; fallback = hotkey/menu (still useful) |
| `NSHostingView` may intercept dragged types and block `DropReceiver` | No SwiftUI drop modifiers anywhere; if it still intercepts, subclass hosting view and forward `NSDraggingDestination` |
| Starting AppKit drag from SwiftUI `DragGesture` via `NSApp.currentEvent` | If flaky, wrap tile in `NSViewRepresentable` that handles `mouseDragged` itself |
| Material looks inactive in non-key panel (14–15) | `NSVisualEffectView.state = .active` |
| Quick Look needs panel key without activating app | `canBecomeKey = true` on non-activating panel; verified in T-07 |
| File promise senders that are slow/large | Receive on background `OperationQueue`; add item when written; 300 ms hide grace |
| `xcodebuild` broken (stale DVTDownloads framework, exit 70) | SwiftPM build (ADR-013); user may run `sudo xcodebuild -runFirstLaunch` (OQ-15) |
| Hotkey ⌃⌥⌘D conflicts with a user's shortcut | Registration failure → setting shows "Unavailable"; custom recorder later (OQ-04) |

## 10. ADRs
- **ADR-001: Native Swift 6 + AppKit/SwiftUI, no third-party deps.** Why: small app, all needed APIs are in the SDK, native look. Rejected: Electron/Catalyst (non-native drag plumbing), SPM packages for hotkeys/launch-at-login (SDK covers both).
- **ADR-002: Deployment target macOS 14.0; Liquid Glass on macOS 26 via `#available`.** Why: macOS 14 gives `@Observable`, `SettingsLink`, `MenuBarExtra`, `SMAppService`, and covers most active Macs; one availability branch in `Glass.swift` gives the macOS 26 look. Rejected: macOS 26-only (drops many users for one styling branch), macOS 13 (loses `@Observable`, more boilerplate).
- **ADR-003 (SUPERSEDED by ADR-013): Hand-written `DragShelf.xcodeproj`, objectVersion 77, synchronized folders, shared scheme.** Why: no xcodegen/tuist on machine and no new tools; synced folders mean new files need no pbxproj edits. Rejected: SPM executable (no app bundle/Info.plist keys/test host), installing xcodegen (new dependency).
- **ADR-004: No sandbox; Developer ID + notarization; ad-hoc signing in dev; hardened runtime on.** Why: sandbox needs security-scoped bookmarks and complicates promises/global monitors. Rejected: Mac App Store for MVP.
- **ADR-005: SwiftUI `App` lifecycle with `MenuBarExtra` + `Settings`; shelf is an AppKit `NSPanel`.** Why: least code for menu bar + settings; `NSPanel` is required for non-activating floating behavior. Rejected: `NSStatusItem` + manual settings window (more code), SwiftUI `Window` scene for shelf (no non-activating panel control).
- **ADR-006: Drop destination in AppKit (`DropReceiver: NSView`), not SwiftUI `onDrop`/`dropDestination`.** Why: needs `NSFilePromiseReceiver` and full pasteboard access. Rejected: SwiftUI drop APIs (weak promise support).
- **ADR-007: Drag out via `NSDraggingSource`, file URLs/`NSURL`/`NSString` writers, operation mask `.copy` only. No `NSFilePromiseProvider`.** Why: promised/image content is already a real file in the cache; copy-only protects originals; session end gives the operation needed for remove-after-drop. Rejected: SwiftUI `.draggable` (no end-operation callback, weak multi-item), offering `.move` (Finder would move the user's original; OQ-05).
- **ADR-008: Drag detection = global mouse monitors + `NSPasteboard(name: .drag).changeCount`.** Why: no permission needed, ignores window drags. Rejected: `CGEventTap` (needs Input Monitoring/Accessibility), shake gesture (non-goal).
- **ADR-009: Global hotkey via Carbon `RegisterEventHotKey`, fixed ⌃⌥⌘D.** Why: only permission-free global hotkey API. Rejected: `NSEvent` global key monitor (needs Accessibility), third-party KeyboardShortcuts package (ADR-001).
- **ADR-010: Items live in memory only; cache wiped on launch/clear/quit.** Why: history/persistence is a non-goal; nothing stale on disk. Rejected: persisting items with bookmarks (later, if asked; OQ-03).
- **ADR-011: Swift 6 mode, default actor isolation `MainActor`, warnings as errors.** Why: app is UI-bound; fewer annotations; zero-warning rule enforced by the compiler. Off-main work (promise receive, thumbnails) uses explicit `nonisolated`/`Task.detached` and hops back to main.
- **ADR-012: Images and promised files are materialized to cache files; `ShelfItem.Kind` = file/url/text.** Why: one drag-out path for files, real files work in every target. Rejected: separate image kind with in-memory `NSImage` (two drag-out paths, fails in Finder/upload fields).
- **ADR-013: SwiftPM package + `scripts/build-app.sh` instead of an `.xcodeproj` (supersedes ADR-003).** Why: `xcodebuild` (even `-list`) exits 70 on this machine (missing IDESimulatorFoundation symbol from stale `/Library/Developer/PrivateFrameworks/DVTDownloads`); the fix needs `sudo`, which only the user can run. `swift build`/`swift test` work, compile `.glassEffect` behind `#available(macOS 26, *)`, and run Swift Testing. A 30-line script gives the app bundle, Info.plist, and signing that Xcode would. Xcode can still open `Package.swift` later. Rejected: keep xcodeproj (cannot build or test), wait for the user (blocks all work), `swift build` xcbuild backend / universal `--arch` flags (route through the broken Xcode build system).
- **ADR-014 (v2): Shelf Actions use native tools only and produce new cached items.** Zip = `/usr/bin/ditto` via `Process`; Share/AirDrop = SwiftUI `ShareLink` (wraps `NSSharingServicePicker`) + `NSSharingService(named: .sendViaAirDrop)`; Convert/Resize = ImageIO; Rename = rename the shelf copy (APFS clone into the cache), never the original. Work runs off `MainActor`, one job at a time, cancellable. Why: no deps (ADR-001), originals never touched (same rule as ADR-007), outputs reuse the existing cached-file drag-out path (ADR-012). Rejected: `NSFileCoordinator` `.forUploading` (zips only a single directory, returns a plain file unchanged, no cancel), ZIPFoundation/libarchive (deps), Apple Archive (`.aar`, not zip), `NSImage`/Core Image resize (more memory, loses orientation/metadata control), libwebp for WebP output (dep; ImageIO cannot write WebP), renaming originals in place (touches user data; OQ-17).
- **ADR-015: "More apps" promo = static JSON feed over HTTPS, text only, hardcoded URL + host allowlist, opt-out toggle (T-14, §12).** Why: new apps must appear without a DragShelf update, and users who never update must still see them, so the fetch code ships in v1. A static file (GitHub Pages/S3/our site) needs no server code. Text + SF Symbol only means no remote images (no tracking pixels, no image decoder attack surface). Rejected: own API server (ops cost), remote images/HTML/`WKWebView` (tracking, attack surface, weight), CloudKit (entitlements, Apple ID coupling), Sparkle-style appcast or any package (ADR-001), list bundled in the app (needs an update for every new app).

## 11. v2: Shelf Actions design (BACKLOG)
Scope: `docs/PRD.md` §10 (US-11..US-14). Tasks: `docs/TASKS.md` v2 backlog. Not built in v1.

New files (all under `Sources/DragShelf/Actions/` unless noted):
| Type | Kind | Responsibility |
|---|---|---|
| `ActionRunner` | `@Observable final class` (MainActor) | Holds the single running job: `title`, `progress: Double?` (nil = indeterminate), `error: String?`. `run(_ title:, work: @Sendable (ProgressReporter) async throws -> [URL])` starts a `Task`, adds each returned URL to `ShelfStore` as `.file` with `isCached = true`, selects the outputs. `cancel()` cancels the task. Drops results if `store.generation` changed (Clear during a job) |
| `Zipper` | `enum`, `nonisolated` static funcs | `zip(_ urls: [URL], into dir: URL) async throws -> URL`. 1 source: `ditto -c -k --sequesterRsrc --keepParent <src> <dir>/<name>.zip`. 2+ sources: clone each into `<dir>/stage/` (`FileManager.copyItem`, APFS clone on the same volume), then `ditto -c -k --sequesterRsrc <dir>/stage <dir>/Archive.zip` (contents at top level), then delete `stage/`. `Process` args as an array, never a shell string. Cancel → `withTaskCancellationHandler { process.terminate() }` |
| `ImageConverter` | `enum`, `nonisolated` static funcs | `convert(_ src: URL, to type: UTType, maxPixel: Int?, into dir: URL) throws -> URL`. `CGImageSourceCreateWithURL` → `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform` (upright), `kCGImageSourceThumbnailMaxPixelSize` = `min(maxPixel, source longest edge)` (no upscale) → `CGImageDestinationCreateWithURL` + `kCGImageDestinationLossyCompressionQuality = 0.85` for JPEG/HEIC. No source properties copied (strips GPS/EXIF); the color space stays with the `CGImage`. Alpha → JPEG: draw onto white in a `CGContext` first. `writableTypes` = `[.heic, .jpeg, .png, .tiff]` ∩ `CGImageDestinationCopyTypeIdentifiers()` |
| `Renamer` | `enum`, `nonisolated` static funcs | `validate(_ name:) -> String?` (error text or nil). `rename(_ item:, to name:, cache:) throws -> ShelfItem`. Cached item: `moveItem` inside its own item dir. Original: `newItemDir()` + `copyItem` (clone) to `<dir>/<name>`, result `isCached = true`. Same `id` so position and selection stay |
| `ActionsMenu` | SwiftUI view (`UI/ActionsMenu.swift`) | Menu content used by both the header "Actions" menu and the tile context menu: Compress, Rename…, Share… (`ShareLink`), AirDrop, Convert To ▸, Resize ▸. Target = selection if non-empty (or clicked item for context menu), else all |

`ShelfStore` gets one new method: `replace(id:with:)` (Rename; keeps index and selection).

Data flow: menu → `ActionRunner.run` → `Task.detached` work writes into `ItemCache.newItemDir()` →
returns output URLs → back on `MainActor` → `store.add(ShelfItem(kind: .file(url), isCached: true))` → user drags it out.
On failure or cancel, the job deletes its own item dir before returning.

Rules:
- Files produced by actions live in `ItemCache` and follow its lifecycle: removed with the item, wiped on clear/quit.
- Actions never write outside `ItemCache`; sources are only read.
- Progress: zip is indeterminate (ditto reports none); convert reports `done/total`; rename is indeterminate and shown only if it takes > 300 ms.
- UI: while a job runs, the header shows a small `ProgressView`, the job title, and a Cancel (`xmark.circle`) button. Errors show as a one-line caption under the header until the next action or Close. VoiceOver announces start/finish via `AccessibilityNotification.Announcement`.
- Rename edits text, so the panel must become key (it can: `canBecomeKey` is true). It must not activate the app.
- Share/AirDrop: the picker and AirDrop sheet are owned by our app. If they do not appear in front from a non-activating panel, call `NSApp.activate()` only for this action (the same exception as Settings, ADR-005 rule 6). While the sheet is open, auto-hide rules must not hide the panel.

v2 risks:
| Risk | Mitigation |
|---|---|
| AirDrop sheet or share picker appears behind other apps from a non-activating panel | Spike first in V2-02; fallback: activate the app for this action only |
| Renaming a large original across volumes is a full copy (slow, uses disk) | Runs as a cancellable job with progress; same-volume copies are APFS clones (instant, no extra space) |
| Zipping 2+ items cross-volume copies them into `stage/` first | Same as above; ponytail ceiling documented in `Zipper`; upgrade = `ditto` per item into a shared archive if it matters |
| ImageIO writers differ by OS (HEIC encode needs hardware support on some Macs) | Menu lists only `writableTypes` computed at runtime |
| Text field inside a SwiftUI grid in an `NSPanel` loses focus on drag-out handle views | Rename task verifies keyboard focus with the T-07/T-13 overlay views in place |

## 12. "More apps" promo feed (T-14, v1)
Scope: PRD US-15. ADR-015.

### Feed
- Static JSON over HTTPS. URL and allowed hosts are **hardcoded constants** in `PromoFeed.swift` (`PromoConfig.feedURL`, `PromoConfig.allowedHosts`). Placeholder until the user answers OQ-26: `https://example.com/dragshelf/promos.json`, hosts `["example.com"]`.
- Schema: `backend/promos.schema.json` (JSON Schema). Example: `backend/promos.json`. The publisher validates the file against the schema before upload.

| Field | Type | Rule (client drops the entry if broken) |
|---|---|---|
| `version` | Int | Must be `1`. Any other value → ignore the whole feed, keep the last good cache |
| `promos` | Array | ≤ 20 entries kept, rest ignored |
| `id` | String | `^[a-z0-9-]{1,40}$`, unique; key for ✕ dismiss |
| `title` | String | 1–60 chars, no control/format chars (`\n`, bidi overrides) |
| `subtitle` | String? | ≤ 80 chars, same character rule |
| `url` | String | `https` scheme, host exactly in `allowedHosts`, no user/password, ≤ 2048 chars |
| `symbol` | String? | SF Symbol name ≤ 64 chars; ignored (not the entry) if `NSImage(systemSymbolName:)` is nil |
| `minAppVersion` / `maxAppVersion` | String? | `MAJOR.MINOR[.PATCH]`, inclusive, compared to `CFBundleShortVersionString` |
| `startsAt` / `endsAt` | String? | ISO 8601 date-time; shown when `startsAt ≤ now < endsAt` |
| `excludeBundleIds` | [String]? | ≤ 20 entries. The entry is hidden in apps whose bundle id is listed. Every promo for an app lists that app's own bundle id, so DragShelf never promotes itself |

Unknown fields are ignored. Body > 64 KB → rejected.

### Client
| Type | Kind | Responsibility |
|---|---|---|
| `PromoFeed` | `struct`, `Decodable` + `nonisolated` static funcs | `decode(_ data: Data) -> PromoFeed?` decodes leniently per entry (`[FailableEntry]`) then validates; invalid entries dropped. `eligible(now:appVersion:bundleID:dismissed:) -> [Promo]` (sorted by `id`). `pick(from:now:calendar:)` = `eligible[dayOrdinal % count]` (daily rotation, stable) |
| `PromoLoader` | `@Observable final class` (MainActor) | `init(session: URLSession, cacheURL: URL, defaults: UserDefaults, now: () -> Date)`. `feed: PromoFeed?`. `refreshIfStale()` called at launch and on each panel show: does nothing when `showPromos` is off or last fetch < 24 h ago. Loads disk cache first |
| `PromoFooter` | SwiftUI view | One line: `Image(systemName:)` (if any), `title` in `.callout`, `subtitle` in `.secondary` with tail truncation, `xmark` dismiss button. Whole line is one `Button`; a11y label "<title>, <subtitle>. Opens in browser"; ✕ label "Hide this suggestion" |

Fetch:
- Session: `URLSessionConfiguration.ephemeral`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`, `timeoutIntervalForRequest = 15`, `httpAdditionalHeaders = ["User-Agent": "DragShelf/<CFBundleShortVersionString>"]`. Tests pass a session whose `protocolClasses` holds a stub `URLProtocol`.
- `GET feedURL` with `If-None-Match: <stored ETag>`. 200 → validate → write `<caches>/com.abhishekyadav.DragShelf/Promos/feed.json` atomically + store ETag and `lastFetch` in UserDefaults. 304 → bump `lastFetch`, keep cache. Anything else, decode failure, or > 64 KB → keep cache, `Logger(subsystem: bundle id, category: "promos").error`, bump `lastFetch` (no retry storm).
- Redirects: `URLSessionTaskDelegate.willPerformHTTPRedirection` allows only `https` to an allowlisted host; otherwise cancels.
- Promo cache dir is outside `ItemCache.root`, so shelf clear/quit wipes do not touch it.

Opening a promo:
- Re-check the URL (`https` + allowlisted host) at click time, then `NSWorkspace.shared.open(url)`. Never open other schemes. Does not activate DragShelf.

Display rules:
- Footer is a separate row under the grid. Panel height grows by one line; the grid/drop area keeps its size.
- Hidden when `showPromos` is off, no eligible promo, or a drag is in progress (`isDropTargeted`, auto-drag show until drag end, or a drag-out session).
- ✕ adds the id to `dismissedPromoIDs`; the footer then shows the next eligible promo, if any. Dismissed promos still appear in the menu bar "More Apps" submenu (user asked for it there).
- "More Apps" submenu in `MenuBarExtra`: one item per eligible promo (dismissed included), hidden when the list is empty.

