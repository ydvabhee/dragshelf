# DragShelf

**A floating shelf for drag and drop on macOS.** Start dragging anything, and the shelf slides in. Drop your files on it, switch to the target app at your own pace, then drag them out where they need to go.

[![Latest release](https://img.shields.io/github/v/release/ydvabhee/dragshelf?label=release)](https://github.com/ydvabhee/dragshelf/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen)

---

## Why

Dragging a file into an app that's hidden or behind other windows is painful. You hold the file, switch apps, wait for the window to come forward, and halfway there the drag drops and the file snaps back.

DragShelf removes the rush. The shelf holds your files for as long as you need, stays above every window, and never steals focus from the app you're working in.

## Features

- **Appears when you drag.** Start dragging a file, image, link or text and the shelf slides down at the top center of the screen. Moving or resizing windows never triggers it.
- **Holds anything.** Files, folders, links, text, images from browsers, and attachments from Mail and Photos (file promises).
- **Drag out to copy, or hold ⌘ to move.** It works the way Finder does. Apps that can only copy, such as Mail, Slack and upload fields, still get a copy.
- **Multi-select.** ⌘-click and ⇧-click to select several items, then drag them all at once, or use **Drag All**.
- **Quick Look, keyboard and clipboard.** Space previews, the arrow keys move the selection, Delete removes, ⌘C copies, and Esc hides the shelf.
- **Movable and resizable.** Drag the header to move the shelf, or drag its edges to resize it. Position and size are remembered for each display.
- **Global shortcut.** ⌃⌥⌘D shows or hides the shelf from any app, including full-screen apps.
- **Native look.** Liquid Glass on macOS 26, with a vibrancy fallback on macOS 14–15. It follows light and dark mode, Reduce Motion, Reduce Transparency, Increase Contrast and VoiceOver.
- **Light on resources.** About 0% CPU and roughly 20 MB of memory when idle. There's no item limit: adding to a shelf of 5,000 items takes about 0.05 ms.
- **No permission prompts.** It needs no Accessibility, Input Monitoring or Full Disk Access.

## Requirements

- macOS 14 Sonoma or later. Liquid Glass needs macOS 26.
- Building from source needs Xcode 26 or later (Swift 6.2 toolchain).

## Install

### Download

**[⬇ Download DragShelf.dmg (latest)](https://github.com/ydvabhee/dragshelf/releases/latest/download/DragShelf.dmg)**. Every version is listed on the [releases page](https://github.com/ydvabhee/dragshelf/releases), and the changes in each one are in the [changelog](CHANGELOG.md).

1. Open the DMG and drag **DragShelf** into **Applications**.
2. Preview builds aren't notarized yet, so the first time you open DragShelf, macOS will block it:
   - On **macOS 15 or later**, try to open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - On **macOS 14**, right-click DragShelf in Applications, choose **Open**, then click **Open** again.

   Developer ID signed, notarized builds are coming.
3. DragShelf runs in the menu bar (tray icon) and has no Dock icon. Turn on **Launch at login** in Settings to keep it running.

### Build from source

```sh
git clone https://github.com/ydvabhee/dragshelf.git
cd dragshelf
scripts/build-app.sh release
open build/DragShelf.app
```

Building from source avoids the Gatekeeper prompt, because a locally built app isn't quarantined.

## Usage

| Action | How |
|---|---|
| Show the shelf | Start dragging anything, press **⌃⌥⌘D**, or choose **Show Shelf** from the menu bar |
| Add items | Drop them onto the shelf |
| Copy out | Drag an item to any app or folder |
| Move out | Hold **⌘** while dragging a file out |
| Select several | ⌘-click, ⇧-click, or the arrow keys |
| Preview | Select an item and press **Space** |
| Remove | Hover and click ✕, right-click and choose **Remove**, or press **Delete** |
| Copy to clipboard | Select items and press **⌘C** |
| Move the shelf | Drag its header |
| Resize the shelf | Drag its bottom or side edges |
| Reset position and size | Double-click the header, or choose **Reset Shelf Position** |
| Hide | **Esc**, the close button, or ⌃⌥⌘D |

Items leave the shelf once they've been dragged out. Cancelled drags keep them. The shelf is temporary: it empties when you quit.

## Settings

Open **Settings…** from the menu bar icon.

- **Launch at login**
- **Auto-show on drag**: turn off to show the shelf only with the shortcut or the menu
- **Global shortcut ⌃⌥⌘D**
- **Keep items after drag out**
- **Reset Shelf Position**
- **Show other apps from the developer**: the one-line suggestion described below

## Privacy

- DragShelf never reads your files' contents. It only keeps references to them, and stores its own temporary copies (dropped images, promised files) in `~/Library/Caches/com.abhishekyadav.DragShelf`, which is wiped on launch and on quit.
- **Network:** DragShelf makes one network request. Once a day, it downloads a small public JSON list of other apps by the same developer and shows one as a single, dismissible line under the shelf.
  - The request is a plain HTTPS GET with no identifiers, cookies or analytics.
  - Links open in your browser only if they're `https` links on an allowlisted domain.
  - Turn it off in Settings to stop all network access.
  - The feed format is in [`backend/promos.schema.json`](backend/promos.schema.json).

## Build and test

```sh
swift build                     # debug build
swift test                      # unit tests (Swift Testing)
scripts/build-app.sh            # debug .app → build/DragShelf.app
scripts/build-app.sh release    # optimized .app, ad-hoc signed
scripts/make-dmg.sh             # release .app packaged as build/DragShelf.dmg
```

The version lives in [`VERSION`](VERSION) and follows [Semantic Versioning](https://semver.org/). The build number is the git commit count.

To work in Xcode, open `Package.swift`.

The package treats warnings as errors and uses Swift 6 strict concurrency, with the main actor as the default isolation.

## Project structure

```
Sources/DragShelf/
  App/      app entry, menu bar, settings, global hotkey, preferences
  Model/    shelf items, store (ordered items + O(1) dedupe index), cache
  Panel/    floating non-activating panel, drag detection, drop in, drag out
  Promos/   remote "more apps" feed: strict decoding, allowlist, loader
  UI/       SwiftUI views, Liquid Glass styling, thumbnails
Tests/DragShelfTests/   unit tests
backend/                example promo feed and its JSON schema
docs/                   product spec, architecture and ADRs, task list, QA plan
scripts/build-app.sh    builds and signs the .app bundle
```

Design decisions are recorded as ADRs in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), and the product spec is in [`docs/PRD.md`](docs/PRD.md).

## Roadmap

- **Next:** Recent drag-outs with ⌘Z undo, and gentle one-line tips
- **Release:** a Developer ID signed and notarized DMG
- **v2, Shelf Actions:** zip everything, rename, share or AirDrop, convert or resize images

See [`docs/TASKS.md`](docs/TASKS.md) for the full plan.

## Contributing

Issues and pull requests are welcome.

1. Keep it native: AppKit and SwiftUI, with **no third-party dependencies** unless an ADR justifies one.
2. `swift build`, `swift test` and `scripts/build-app.sh release` must all pass with zero warnings. The optimized build can catch compiler issues that the debug build misses.
3. Add a unit test for any new logic.
4. Use [Conventional Commits](https://www.conventionalcommits.org/), such as `feat: …`, `fix: …` and `docs: …`, with a short, imperative subject.
5. Add a line under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) for every user-visible change.
6. UI changes should follow Apple's Human Interface Guidelines and keep VoiceOver, keyboard access and Reduce Motion working.

## License

No license has been chosen yet. Until a `LICENSE` file is added, all rights are reserved by the author.

---

Made by [Abhishek Yadav](https://github.com/ydvabhee).
