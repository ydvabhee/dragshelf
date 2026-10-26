# DragShelf — Release checklist (manual)

Only what needs a real Mac and a GUI. Automated checks (`swift build`, `swift test`, `scripts/build-app.sh release`) must already be green.
Details per feature: `docs/QA.md`. Test with the bundled `build/DragShelf.app`, ideally from `/Applications`, on macOS 26 and on 14 or 15 if available.

## Drag and drop: sources
Shelf appears on drag start, accepts the drop, stays on top after an app switch.
- [ ] Finder: 1 file, many files, a folder
- [ ] Desktop item
- [ ] Safari and Chrome: image, link, selected text (app must not quit on promise drops)
- [ ] Mail attachment
- [ ] Photos (slow iCloud item still lands)
- [ ] VS Code or Slack image (file promise)
- [ ] Drag the shelf's own item back onto the shelf: ignored

## Drag and drop: targets
Right content and name arrive; copy by default, ⌘-drag moves files only; removal after drag out works.
- [ ] Finder (plain = copy, ⌘ = move; mixed selection = copy)
- [ ] Slack or Messages
- [ ] Browser upload field
- [ ] Mail compose
- [ ] Hidden or minimized app
- [ ] Other Space and a full-screen app
- [ ] Recent (clock): restore, drag from a row, ⌘Z undo
- [ ] Multi-display: shelf opens on the cursor's screen, position and size remembered per display
- [ ] Display with a notch: shelf is not hidden

## Actions
- [ ] Compress 1 item and 3 items: zip opens in Archive Utility, names right; Cancel mid-zip leaves no file
- [ ] Rename (Return): base name selected, Return/Esc/click-away behave, bad name shakes; original on disk unchanged
- [ ] Convert To HEIC/JPEG/PNG/TIFF: sizes and formats match; transparent PNG to JPEG has white background; GPS removed
- [ ] Batch of 20 images: "n of 20", Cancel keeps finished outputs; one corrupt image is skipped with a message
- [ ] Resize presets and Custom… (pixels, percent, lock): 400 % on a big photo shows "Too large", form stays open
- [ ] Custom form and rename field take keys while the target app stays frontmost (no activation)

## Share and AirDrop
- [ ] Share… picker opens in front; pick Notes or Messages: items arrive and stay on the shelf
- [ ] Click outside the picker: focus returns to the previous app
- [ ] AirDrop 2 files to a nearby device: both arrive with names; cancel returns focus; repeat 10 times, app never stays active
- [ ] With Settings open and key, Share… then cancel: Settings stays key

## Paste and Text
- [ ] Menu "Paste to DragShelf", context-menu Paste, ⌘V: file, image, link, text each add; empty clipboard shows "Nothing to paste"
- [ ] Drag a text item to a text field (pastes text) and to Finder/Desktop (real `.txt`, not a clipping)
- [ ] Drop into a Finder folder that already has the name: "name 2.txt", no error dialog
- [ ] Save as .txt and Use as Text (a `.md`, a UTF-16 file, a file over 1 MB is refused)

## Pin persistence
- [ ] Pin a Finder file, a Safari image, some text: pin badge, VoiceOver says "Pinned"
- [ ] Clear keeps pinned; ⌘-drag of a pinned file copies only
- [ ] Quit and relaunch: pins return in order; `~/Library/Application Support/com.abhishekyadav.DragShelf/Pinned/` holds `pinned.json` + `<UUID>/` dirs
- [ ] Move a pinned original, relaunch: follows it. Delete it, relaunch: Missing
- [ ] Unpin, rename a pinned image, pin an item then see it in Recent: no stray "Missing" rows

## Shortcut on a non-US layout
- [ ] Record ⌃⌥⌘J: menu and Settings show it, hotkey works, survives relaunch
- [ ] Press the current shortcut while recording: it is recorded, shelf does not toggle
- [ ] Record a system-taken one (⌘Space): "used by another app", old shortcut still works; plain A is refused
- [ ] Switch to French AZERTY: field and menu show the key you actually pressed; switch layout, labels follow
- [ ] Close Settings while recording: not stuck; hotkey works

## Search and filter
- [ ] ⌘F focuses the field, live filter, accents and capitals match; Esc clears and hides, second Esc hides the panel
- [ ] Filter menu: Files, Folders (`.app` counts as a file), Images, Links, Text, Pinned
- [ ] Filtered: ⌘A, arrows, Space, Drag All, ⌘C, Clear and Actions touch only the shown items; pinned survive Clear

## Accessibility
- [ ] VoiceOver: header buttons, tiles ("<type>, <name>"), Remove / Quick Look actions, Missing value, tips and action results announced
- [ ] Reduce Motion, Reduce Transparency, Increase Contrast: panel and footer look right
- [ ] Light and dark mode, accent color change
- [ ] Keyboard only: arrows, Space, Delete, Return (rename), ⌘Z, ⌘C, Esc

## Performance
- [ ] Idle with the panel hidden: ~0 % CPU, memory in Activity Monitor around 20 MB
- [ ] 50 items on the shelf: memory under 60 MB, scrolling smooth, resize smooth
- [ ] Cache folder `~/Library/Caches/com.abhishekyadav.DragShelf/Shelf/` is empty after Clear (with empty Recent) and after quit
- [ ] No permission prompt at any point; no network traffic except the promo feed

## Release build and DMG
- [ ] `scripts/build-app.sh release` bundle launches; menu bar glyph shows, no Dock icon
- [ ] `scripts/make-dmg.sh`: `build/DragShelf.dmg` opens, shows the app and an Applications link
- [ ] Copy to `/Applications`, launch; launch at login toggle works after logout and login
- [ ] Gatekeeper: ad-hoc build opens via Open Anyway; notarized build (M5) opens with no warning and `spctl -a -vv` accepts it
- [ ] `VERSION`, About/Info.plist version and `CHANGELOG.md` section agree
