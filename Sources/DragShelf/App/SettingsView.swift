import AppKit
import Carbon.HIToolbox
import os
import ServiceManagement
import SwiftUI

private let shortcutLog = Logger(subsystem: PromoConfig.selfBundleID, category: "shortcut")

/// Pure parts of the recorder (V2-09), unit-tested.
enum ShortcutRecording {
    /// Live feedback while only modifiers are down, e.g. "⌃⌥⌘"; empty when none.
    static func heldDisplay(_ flags: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }
}

/// One key press can reach us through the monitor, `performKeyEquivalent` and `keyDown`; same key code and
/// event timestamp means same press.
struct KeyDedupe {
    private var last: (code: UInt16, time: TimeInterval)?
    mutating func isDuplicate(code: UInt16, time: TimeInterval) -> Bool {
        if let last, last.code == code, last.time == time { return true }
        last = (code, time)
        return false
    }
}

struct SettingsView: View {
    var onResetPosition: () -> Void
    var onResetTips: () -> Void
    var onPlayBall: () -> Void = {}

    @AppStorage(Preferences.autoShow) private var autoShow = true
    @AppStorage(Preferences.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(Preferences.keepAfterDragOut) private var keepAfterDragOut = false
    @AppStorage(Preferences.showPromos) private var showPromos = true
    @AppStorage(Preferences.showTips) private var showTips = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var shortcut = Preferences.shortcut()
    @State private var recording = false
    @State private var held = ""
    @State private var shortcutError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }))
                if loginStatus == .requiresApproval {
                    LabeledContent("Approval needed in Login Items.") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Show DragShelf when dragging", isOn: $autoShow)
                LabeledContent("Global shortcut") {
                    HStack(spacing: 6) {
                        ShortcutField(shortcut: hotKeyEnabled ? shortcut : nil, recording: $recording, held: $held,
                                      onKeyDown: record, onClear: clearShortcut)
                        Button("Reset to \(Shortcut.standard.display)") { apply(.standard) }
                            .disabled(hotKeyEnabled && shortcut == .standard && HotKey.shared.current == .standard)
                    }
                }
                // A failed attempt, or the saved shortcut refused at launch.
                if let message = shortcutError
                    ?? (hotKeyEnabled && !recording && HotKey.shared.current == nil ? Self.takenMessage : nil) {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("General")
            } footer: {
                Text("DragShelf appears when you start dragging a file, link, or text. The shortcut shows or hides it from any app.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep items after drag out", isOn: $keepAfterDragOut)
                LabeledContent("Position") {
                    Button("Reset DragShelf Position", action: onResetPosition)
                }
            } header: {
                Text("DragShelf")
            } footer: {
                Text("Off: items leave DragShelf once dropped elsewhere. Drag the DragShelf header to move it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show tips", isOn: $showTips)
                LabeledContent("Seen them all?") {
                    Button("Reset Tips", action: onResetTips)
                }
            } header: {
                Text("Tips")
            } footer: {
                Text("A one-line tip under DragShelf now and then. Each tip shows up to 3 times.")
                    .foregroundStyle(.secondary)
            }
            PetSettingsSection(onPlayBall: onPlayBall)
            Section {
                Toggle("Show other apps from the developer", isOn: $showPromos)
            } header: {
                Text("More Apps")
            } footer: {
                Text("A one-line suggestion under DragShelf and a More Apps menu. The list is downloaded once a day; nothing about you is sent.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .background(SettingsWindowTag())
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private static let takenMessage = "This shortcut is used by another app."

    /// Recorder keys: Esc cancels, Delete clears, anything else must carry ⌘, ⌃, or ⌥ (V2-09 AC-2).
    private func record(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) {
        held = ""
        let new = Shortcut(keyCode: keyCode, flags: flags)
        if new.modifiers == 0 && Int(keyCode) == kVK_Escape {
            recording = false
        } else if new.modifiers == 0 && [kVK_Delete, kVK_ForwardDelete].contains(Int(keyCode)) {
            clearShortcut()
        } else if !new.isValid {
            shortcutError = "Use at least one of ⌘, ⌃, or ⌥."
        } else {
            apply(new)
        }
    }

    /// Registers first; only a shortcut Carbon accepted is saved, otherwise the previous one stays.
    private func apply(_ new: Shortcut) {
        recording = false
        guard HotKey.shared.register(new) else {
            shortcutError = Self.takenMessage
            return
        }
        Preferences.setShortcut(new)
        shortcut = new
        hotKeyEnabled = true
        shortcutError = nil
    }

    /// Clear = shortcut off (same switch the old toggle used); the saved key stays for Reset or a new recording.
    private func clearShortcut() {
        recording = false
        shortcutError = nil
        hotKeyEnabled = false
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Could not change launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}

/// Apple-style shortcut field (V2-09): click, then type the shortcut. Keys are read only while recording, with a
/// local monitor on this window: no global monitor, no Accessibility or Input Monitoring prompt (AC-4).
private struct ShortcutField: View {
    var shortcut: Shortcut?
    @Binding var recording: Bool
    @Binding var held: String
    var onKeyDown: (UInt16, NSEvent.ModifierFlags) -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(recording ? (held.isEmpty ? "Type shortcut" : held) : shortcut?.display ?? "Record Shortcut")
                .foregroundStyle(recording || shortcut == nil ? .secondary : .primary)
                .frame(minWidth: 96)
            if shortcut != nil && !recording {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear")
                    .accessibilityLabel("Clear shortcut")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: recording ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { recording.toggle() }
        .background(KeyRecorder(active: recording, onKeyDown: onKeyDown, onFlags: { held = $0 },
                                      onCancel: { recording = false; held = "" }))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Global shortcut")
        .accessibilityValue(recording ? "Type shortcut" : shortcut?.spoken ?? "None")
        .accessibilityAction { recording.toggle() }
    }
}

/// Captures keys for the field while `active`; a click elsewhere in the window stops recording.
private struct KeyRecorder: NSViewRepresentable {
    var active: Bool
    var onKeyDown: (UInt16, NSEvent.ModifierFlags) -> Void
    var onFlags: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onFlags = onFlags
        view.onCancel = onCancel
        view.active = active
    }

    static func dismantleNSView(_ view: RecorderView, coordinator: ()) { view.active = false }

    /// While active the global hotkey is paused (Carbon would see the keys before the monitor); it comes back on
    /// every way out: a recorded key, Esc, Delete, click elsewhere, window close, teardown.
    /// Three capture paths, all deduped: the local monitor (sees everything while the window is key),
    /// and first-responder `performKeyEquivalent` (⌘ combos) / `keyDown` as fallback.
    final class RecorderView: NSView {
        var onKeyDown: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        var onFlags: ((String) -> Void)?
        /// Click elsewhere in the window, or the window closes.
        var onCancel: (() -> Void)?
        private var monitor: Any?
        private var dedupe = KeyDedupe()

        override var acceptsFirstResponder: Bool { active }

        var active = false {
            didSet {
                guard active != oldValue else { return }
                stopMonitoring()
                // Deferred: `updateNSView` sets `active` during a SwiftUI update, and the hotkey's `current` is
                // @Observable. The main queue keeps pause/resume calls in order.
                DispatchQueue.main.async { [weak self, active] in
                    if active {
                        HotKey.shared.unregister()
                        self?.takeFocus()
                    } else if Preferences.hotKeyOn() { HotKey.shared.register(Preferences.shortcut()) }
                }
                guard active else { return }
                // Local monitors run on the main thread; they see this app's events only.
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                    guard let self, let window = self.window else { return event }
                    if event.type == .leftMouseDown {
                        if event.window === window,
                           !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.onCancel?() }
                        return event
                    }
                    guard event.window === window || window.isKeyWindow else {
                        shortcutLog.debug("monitor ignored \(event.type.rawValue) key \(event.keyCode): not our window")
                        return event
                    }
                    return self.handle(event, via: "monitor") ? nil : event
                }
                if let window {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                                           name: NSWindow.willCloseNotification, object: window)
                }
            }
        }

        /// Settings is an accessory-app window: bring app and window forward or keys go to another app.
        private func takeFocus() {
            guard active, let window else { return }
            NSApp.activate()
            if !NSApp.isActive { NSRunningApplication.current.activate(options: []) }
            window.makeKeyAndOrderFront(nil)
            let ok = window.makeFirstResponder(self)
            shortcutLog.debug("recording start: appActive=\(NSApp.isActive) windowKey=\(window.isKeyWindow) firstResponder=\(ok && window.firstResponder === self)")
        }

        /// Returns true when the event was consumed.
        @discardableResult
        private func handle(_ event: NSEvent, via path: String) -> Bool {
            guard active else { return false }
            if event.type == .flagsChanged {
                let text = ShortcutRecording.heldDisplay(event.modifierFlags)
                shortcutLog.debug("\(path): flags \(text, privacy: .public)")
                onFlags?(text)
                return true
            }
            guard event.type == .keyDown else { return false }
            if dedupe.isDuplicate(code: event.keyCode, time: event.timestamp) {
                shortcutLog.debug("\(path): key \(event.keyCode) duplicate, dropped")
                return true
            }
            shortcutLog.debug("\(path): key \(event.keyCode) flags \(event.modifierFlags.rawValue): recorded")
            onKeyDown?(event.keyCode, event.modifierFlags)
            return true
        }

        override func keyDown(with event: NSEvent) { if !handle(event, via: "keyDown") { super.keyDown(with: event) } }
        override func flagsChanged(with event: NSEvent) { if !handle(event, via: "flagsChanged") { super.flagsChanged(with: event) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { handle(event, via: "performKeyEquivalent") }

        @objc private func windowWillClose() {
            active = false
            onCancel?()
        }

        private func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { active = false }
        }

        isolated deinit { stopMonitoring() }
    }
}

/// Remembers the Settings window so `Sharer` can tell it from share sheets (V2-02). Our own weak reference, not the
/// window's title (localized) or SwiftUI's private identifier; the identifier is left alone so SwiftUI still finds
/// and reuses its window.
struct SettingsWindowTag: NSViewRepresentable {
    static weak var window: NSWindow?

    func makeNSView(context: Context) -> NSView { TagView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class TagView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindowTag.window = window }
        }
    }
}
