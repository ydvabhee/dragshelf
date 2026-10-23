import Foundation

/// UserDefaults keys + defaults (ARCHITECTURE §4). Launch at login is never stored: read from `SMAppService`.
enum Preferences {
    static let autoShow = "autoShow"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let keepAfterDragOut = "keepAfterDragOut"
    static let showPromos = "showPromos"
    /// [String] of promo ids hidden with ✕ (T-14).
    static let dismissedPromoIDs = "dismissedPromoIDs"
    /// Footer tips (T-18); counts and dismissals: `HintEngine` keys.
    static let showTips = "showTips"

    static func autoShowEnabled(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: autoShow) as? Bool ?? true }
    static func hotKeyOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: hotKeyEnabled) as? Bool ?? true }
    static func keepAfterDrag(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: keepAfterDragOut) as? Bool ?? false }
    static func promosOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: showPromos) as? Bool ?? true }
    static func tipsOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: showTips) as? Bool ?? true }
}
