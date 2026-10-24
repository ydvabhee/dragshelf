import AppKit
import Carbon.HIToolbox
import Observation
import os
import SwiftUI

/// A global shortcut in Carbon terms (V2-09). `keyCode` is a virtual key code (`kVK_*`, same as `NSEvent.keyCode`);
/// `modifiers` is a Carbon mask of `controlKey | optionKey | shiftKey | cmdKey`.
struct Shortcut: Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a recorded key event; flags other than ⌃⌥⇧⌘ (Caps Lock, fn, …) are dropped.
    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, Int)] = [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        self.init(keyCode: UInt32(keyCode),
                  modifiers: pairs.reduce(0) { flags.contains($1.0) ? $0 | UInt32($1.1) : $0 })
    }

    /// Needs ⌘, ⌃, or ⌥: plain or ⇧-only keys would swallow normal typing in every app.
    var isValid: Bool { modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 }

    private var modifierParts: [(symbol: String, word: String)] {
        [(controlKey, "⌃", "Control"), (optionKey, "⌥", "Option"), (shiftKey, "⇧", "Shift"), (cmdKey, "⌘", "Command")]
            .filter { modifiers & UInt32($0.0) != 0 }.map { ($0.1, $0.2) }
    }

    /// Label in the current layout ("A" on AZERTY for the US-Q key). Read at display time, so it follows layout changes.
    var keyName: String { Self.keyName(keyCode, layout: Self.currentLayout()) }
    /// Apple order and symbols, e.g. "⌃⌥⌘D".
    var display: String { modifierParts.map(\.symbol).joined() + keyName }
    /// VoiceOver, e.g. "Control-Option-Command-D".
    var spoken: String { (modifierParts.map(\.word) + [keyName]).joined(separator: "-") }

    /// For the menu item; nil when SwiftUI has no `KeyEquivalent` for the key (function keys, keypad).
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch Int(keyCode) {
        case kVK_Return: key = .return
        case kVK_Tab: key = .tab
        case kVK_Space: key = .space
        case kVK_Delete: key = .delete
        case kVK_ForwardDelete: key = .deleteForward
        case kVK_Escape: key = .escape
        case kVK_Home: key = .home
        case kVK_End: key = .end
        case kVK_PageUp: key = .pageUp
        case kVK_PageDown: key = .pageDown
        case kVK_LeftArrow: key = .leftArrow
        case kVK_RightArrow: key = .rightArrow
        case kVK_UpArrow: key = .upArrow
        case kVK_DownArrow: key = .downArrow
        default:
            guard Self.specialNames[Int(keyCode)] == nil, let c = keyName.lowercased().first, keyName.count == 1 else { return nil }
            key = KeyEquivalent(c)
        }
        let pairs: [(Int, SwiftUI.EventModifiers)] = [(controlKey, .control), (optionKey, .option), (shiftKey, .shift), (cmdKey, .command)]
        return KeyboardShortcut(key, modifiers: pairs.reduce(into: []) { if modifiers & UInt32($1.0) != 0 { $0.insert($1.1) } })
    }

    /// Pure: special keys by table, character keys through `layout` (`kTISPropertyUnicodeKeyLayoutData`).
    static func keyName(_ keyCode: UInt32, layout: Data?) -> String {
        if let name = specialNames[Int(keyCode)] { return name }
        guard let layout, let code = UInt16(exactly: keyCode) else { return "Key \(keyCode)" }
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(base, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        }
        let name = String(utf16CodeUnits: chars, count: length).uppercased()
        guard status == noErr, !name.isEmpty, name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "Key \(keyCode)" }
        return name
    }

    /// Key layout data of the current ASCII-capable input source. Main thread only (TIS); `Shortcut` is MainActor
    /// by default isolation (ADR-011), so every caller is on main.
    static func currentLayout() -> Data? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
    }

    /// Keys whose label does not depend on the layout.
    private static let specialNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_ANSI_KeypadDecimal: "Keypad .", kVK_ANSI_KeypadMultiply: "Keypad *", kVK_ANSI_KeypadPlus: "Keypad +",
            kVK_ANSI_KeypadClear: "Keypad Clear", kVK_ANSI_KeypadDivide: "Keypad /", kVK_ANSI_KeypadEnter: "Keypad Enter",
            kVK_ANSI_KeypadMinus: "Keypad -", kVK_ANSI_KeypadEquals: "Keypad =",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fKeys.enumerated() { names[code] = "F\(i + 1)" }
        let keypad = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
                      kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        for (i, code) in keypad.enumerated() { names[code] = "Keypad \(i)" }
        return names
    }()
}

/// The global show/hide shortcut via Carbon `RegisterEventHotKey` (ADR-009): no permission prompt.
/// `@Observable` so the menu and Settings follow `current`.
@Observable
class HotKey {
    /// The app's one hotkey; Settings registers through it so a refused shortcut can be reported inline.
    static let shared = HotKey()

    @ObservationIgnored var onPress: (() -> Void)?
    /// The registered shortcut; nil = none (off, or Carbon refused it).
    private(set) var current: Shortcut?

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    private static let log = Logger(subsystem: PromoConfig.selfBundleID, category: "HotKey")

    /// Swaps to `shortcut`. If it is refused (taken), the previous shortcut is registered again and this returns false.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        guard shortcut != current else { return true }
        let previous = current
        unregister()
        if carbonRegister(shortcut) {
            current = shortcut
            return true
        }
        if let previous, carbonRegister(previous) { current = previous }
        return false
    }

    func unregister() {
        carbonUnregister()
        current = nil
    }

    /// Carbon registration of one shortcut; tests override this pair.
    func carbonRegister(_ shortcut: Shortcut) -> Bool {
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                // Application event target delivers on the main thread (ADR-016).
                MainActor.assumeIsolated {
                    Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else {
                Self.log.error("InstallEventHandler failed: \(status)")
                handlerRef = nil
                return false
            }
        }
        let id = EventHotKeyID(signature: OSType(0x4453_4846), id: 1) // 'DSHF'
        let reg = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard reg == noErr else {
            Self.log.error("RegisterEventHotKey \(shortcut.display, privacy: .public) failed (shortcut taken?): \(reg)")
            hotKeyRef = nil
            return false
        }
        return true
    }

    func carbonUnregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
