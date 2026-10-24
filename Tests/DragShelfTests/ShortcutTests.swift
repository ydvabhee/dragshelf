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

@Test func displayStrings() {
    #expect(Shortcut.standard.display == "⌃⌥⌘D")
    #expect(Shortcut.standard.spoken == "Control-Option-Command-D")
    let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    #expect(Shortcut(keyCode: code(kVK_F12), modifiers: all).display == "⌃⌥⇧⌘F12")
    #expect(Shortcut(keyCode: code(kVK_Space), modifiers: UInt32(optionKey)).display == "⌥Space")
    #expect(Shortcut(keyCode: code(kVK_LeftArrow), modifiers: UInt32(cmdKey)).display == "⌘←")
    #expect(Shortcut(keyCode: code(kVK_ANSI_Slash), modifiers: UInt32(shiftKey | cmdKey)).spoken == "Shift-Command-/")
}

@Test func menuKeyEquivalent() {
    #expect(Shortcut.standard.keyboardShortcut == KeyboardShortcut("d", modifiers: [.control, .option, .command]))
    #expect(Shortcut(keyCode: code(kVK_UpArrow), modifiers: UInt32(shiftKey | cmdKey)).keyboardShortcut
        == KeyboardShortcut(.upArrow, modifiers: [.shift, .command]))
    #expect(Shortcut(keyCode: code(kVK_F5), modifiers: UInt32(cmdKey)).keyboardShortcut == nil)
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
