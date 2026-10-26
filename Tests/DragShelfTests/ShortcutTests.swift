import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing
@testable import DragShelf

private func code(_ k: Int) -> UInt32 { UInt32(k) }

@Test func shortcutNeedsCommandControlOrOption() {
    #expect(!Shortcut(keyCode: code(kVK_ANSI_D), modifiers: 0).isValid)
    #expect(!Shortcut(keyCode: code(kVK_ANSI_D), modifiers: UInt32(shiftKey)).isValid)
    #expect(Shortcut(keyCode: code(kVK_ANSI_D), modifiers: UInt32(cmdKey)).isValid)
    #expect(Shortcut(keyCode: code(kVK_F5), modifiers: UInt32(controlKey | shiftKey)).isValid)
    #expect(Shortcut(keyCode: code(kVK_Space), modifiers: UInt32(optionKey)).isValid)
}

@Test func eventFlagsMapToCarbon() {
    let s = Shortcut(keyCode: UInt16(kVK_ANSI_D), flags: [.control, .option, .command, .capsLock, .function])
    #expect(s == .standard)
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_K), flags: [.shift, .command]).modifiers == UInt32(shiftKey | cmdKey))
    #expect(Shortcut(keyCode: UInt16(kVK_ANSI_K), flags: [.capsLock]).modifiers == 0)
}

/// Layout data of an installed keyboard layout, e.g. "com.apple.keylayout.French"; nil if not installed.
private func layout(_ id: String) -> Data? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first, let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
}

@Test func keyNamesFollowTheLayout() throws {
    let us = try #require(layout("com.apple.keylayout.US"))
    #expect(Shortcut.keyName(code(kVK_ANSI_D), layout: us) == "D")
    #expect(Shortcut.keyName(code(kVK_ANSI_Slash), layout: us) == "/")
    if let french = layout("com.apple.keylayout.French") {
        #expect(Shortcut.keyName(code(kVK_ANSI_Q), layout: french) == "A")
    }
    if let dvorak = layout("com.apple.keylayout.Dvorak") {
        #expect(Shortcut.keyName(code(kVK_ANSI_D), layout: dvorak) == "E")
    }
    // Layout-independent keys, and no layout at all.
    #expect(Shortcut.keyName(code(kVK_ANSI_Keypad1), layout: us) == "Keypad 1")
    #expect(Shortcut.keyName(code(kVK_ANSI_KeypadEnter), layout: nil) == "Keypad Enter")
    #expect(Shortcut.keyName(code(kVK_ANSI_D), layout: nil) == "Key 2")
}

@Test func displayStrings() {
    // Character keys follow the host layout; only the modifier part is fixed.
    #expect(Shortcut.standard.display == "⌃⌥⌘" + Shortcut.standard.keyName)
    #expect(Shortcut.standard.spoken == "Control-Option-Command-" + Shortcut.standard.keyName)
    let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    #expect(Shortcut(keyCode: code(kVK_F12), modifiers: all).display == "⌃⌥⇧⌘F12")
    #expect(Shortcut(keyCode: code(kVK_Space), modifiers: UInt32(optionKey)).display == "⌥Space")
    #expect(Shortcut(keyCode: code(kVK_LeftArrow), modifiers: UInt32(cmdKey)).display == "⌘←")
    #expect(Shortcut(keyCode: code(kVK_ANSI_Keypad5), modifiers: UInt32(shiftKey | cmdKey)).spoken == "Shift-Command-Keypad 5")
}

@Test func menuKeyEquivalent() throws {
    let d = try #require(Shortcut.standard.keyName.lowercased().first)
    #expect(Shortcut.standard.keyboardShortcut == KeyboardShortcut(KeyEquivalent(d), modifiers: [.control, .option, .command]))
    #expect(Shortcut(keyCode: code(kVK_UpArrow), modifiers: UInt32(shiftKey | cmdKey)).keyboardShortcut
        == KeyboardShortcut(.upArrow, modifiers: [.shift, .command]))
    #expect(Shortcut(keyCode: code(kVK_F5), modifiers: UInt32(cmdKey)).keyboardShortcut == nil)
    #expect(Shortcut(keyCode: code(kVK_ANSI_Keypad1), modifiers: UInt32(cmdKey)).keyboardShortcut == nil)
}

@Test func shortcutPersistence() {
    let d = UserDefaults(suiteName: "ShortcutTests-\(UUID().uuidString)")!
    #expect(Preferences.shortcut(d) == .standard)
    d.set(false, forKey: Preferences.hotKeyEnabled)
    let s = Shortcut(keyCode: code(kVK_ANSI_K), modifiers: UInt32(controlKey | shiftKey))
    Preferences.setShortcut(s, d)
    #expect(Preferences.shortcut(d) == s)
    #expect(Preferences.hotKeyOn(d))
    // Corrupt or invalid values fall back to the default.
    d.set(["keyCode": -1, "modifiers": cmdKey], forKey: Preferences.hotKeyShortcut)
    #expect(Preferences.shortcut(d) == .standard)
    d.set(["keyCode": kVK_ANSI_K, "modifiers": shiftKey], forKey: Preferences.hotKeyShortcut)
    #expect(Preferences.shortcut(d) == .standard)
    d.set("junk", forKey: Preferences.hotKeyShortcut)
    #expect(Preferences.shortcut(d) == .standard)
}

/// Stands in for Carbon: shortcuts in `taken` are refused.
private final class FakeHotKey: HotKey {
    var taken: Set<Shortcut> = []
    var live: Shortcut?

    override func carbonRegister(_ shortcut: Shortcut) -> Bool {
        guard !taken.contains(shortcut) else { return false }
        live = shortcut
        return true
    }

    override func carbonUnregister() { live = nil }
}

@Test func refusedShortcutKeepsThePreviousOne() {
    let hotKey = FakeHotKey()
    let other = Shortcut(keyCode: code(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
    hotKey.taken = [other]
    #expect(hotKey.register(.standard))
    #expect(!hotKey.register(other))
    #expect(hotKey.current == .standard && hotKey.live == .standard)
    hotKey.taken = []
    #expect(hotKey.register(other))
    #expect(hotKey.current == other && hotKey.live == other)
    hotKey.unregister()
    #expect(hotKey.current == nil && hotKey.live == nil)
    // Nothing registered before: a refusal leaves it off.
    hotKey.taken = [other]
    #expect(!hotKey.register(other))
    #expect(hotKey.current == nil)
}

@Test func recorderShowsHeldModifiers() {
    #expect(ShortcutRecording.heldDisplay([.control, .option, .command]) == "⌃⌥⌘")
    #expect(ShortcutRecording.heldDisplay([.shift, .capsLock]) == "⇧")
    #expect(ShortcutRecording.heldDisplay([]) == "")
}

@Test func commandComboMapsToShortcut() {
    // ⌘K arrives via performKeyEquivalent with the same keyCode/flags as keyDown.
    let s = Shortcut(keyCode: UInt16(kVK_ANSI_K), flags: [.command])
    #expect(s.isValid && s.modifiers == UInt32(cmdKey))
}

@Test func keyDedupeDropsSamePressOnly() {
    var d = KeyDedupe()
    let results = [d.isDuplicate(code: 2, time: 1.0), d.isDuplicate(code: 2, time: 1.0),
                   d.isDuplicate(code: 2, time: 1.5), d.isDuplicate(code: 3, time: 1.5)]
    #expect(results == [false, true, false, false])
}
