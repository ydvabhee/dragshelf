import Foundation

/// UserDefaults keys + defaults (ARCHITECTURE §4). Launch at login is never stored: read from `SMAppService`.
enum Preferences {
    static let autoShow = "autoShow"
    static let hotKeyEnabled = "hotKeyEnabled"
    /// ["keyCode": Int, "modifiers": Int] (Carbon), one key so a change lands in one write (V2-09).
    static let hotKeyShortcut = "hotKeyShortcut"
    static let keepAfterDragOut = "keepAfterDragOut"
    static let showPromos = "showPromos"
    /// [String] of promo ids hidden with ✕ (T-14).
    static let dismissedPromoIDs = "dismissedPromoIDs"
    /// Footer tips (T-18); counts and dismissals: `HintEngine` keys.
    static let showTips = "showTips"

    static func autoShowEnabled(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: autoShow) as? Bool ?? true }
    static func hotKeyOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: hotKeyEnabled) as? Bool ?? true }
    /// The chosen shortcut (default ⌃⌥⌘D); whether it is on is `hotKeyOn`.
    static func shortcut(_ d: UserDefaults = .standard) -> Shortcut {
        guard let dict = d.dictionary(forKey: hotKeyShortcut),
              let code = (dict["keyCode"] as? Int).flatMap(UInt32.init(exactly:)),
              let mods = (dict["modifiers"] as? Int).flatMap(UInt32.init(exactly:)) else { return .standard }
        let shortcut = Shortcut(keyCode: code, modifiers: mods)
        return shortcut.isValid ? shortcut : .standard
    }
    /// Stores `shortcut` and turns the hotkey on (shortcut first, so the app never applies a half-changed state).
    static func setShortcut(_ shortcut: Shortcut, _ d: UserDefaults = .standard) {
        d.set(["keyCode": Int(shortcut.keyCode), "modifiers": Int(shortcut.modifiers)], forKey: hotKeyShortcut)
        d.set(true, forKey: hotKeyEnabled)
    }
    static func keepAfterDrag(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: keepAfterDragOut) as? Bool ?? false }
    static func promosOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: showPromos) as? Bool ?? true }
    static func tipsOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: showTips) as? Bool ?? true }
}
