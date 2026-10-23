import Foundation
import Observation

/// One-line contextual tips in the footer slot (T-18). Events add eligible hints to `pending`; the top-priority one
/// becomes `current` once the panel is visible and no drag runs. Each hint shows at most `maxShows` times, ✕ retires
/// it for good. Counts and dismissals live in UserDefaults (injectable for tests).
@Observable
final class HintEngine {
    /// Declaration order = priority (first wins).
    enum Hint: String, CaseIterable {
        case clear, dragOut, firstDrop, hotkey, recent, holdCommand, moveResize

        var text: String {
            switch self {
            case .clear: "Clear only empties DragShelf; your files aren't touched."
            case .dragOut: "Removed from DragShelf · ⌘Z to bring it back"
            case .firstDrop: "Switch apps, then drag items out of DragShelf."
            case .hotkey: "Tip: ⌃⌥⌘D shows DragShelf from anywhere."
            case .recent: "Recent drags are under the clock icon."
            case .holdCommand: "Hold ⌘ while dragging out to move instead of copy."
            case .moveResize: "Drag the top bar to move DragShelf · edges to resize."
            }
        }
    }

    enum Event {
        case dropped
        /// `removed`: the drag out took items off DragShelf (not kept, not a Recent row).
        case draggedOut(removed: Bool)
        case cleared
        case shown(ShelfPanelController.ShowReason, hasFile: Bool, hasRecent: Bool)
    }

    static let maxShows = 3
    static let countsKey = "hintCounts"
    static let dismissedKey = "dismissedHints"
    static let showsKey = "panelShowCount"
    static let menuShowsKey = "menuShowCount"

    private(set) var current: Hint?
    @ObservationIgnored private(set) var pending: Set<Hint> = []
    @ObservationIgnored private let defaults: UserDefaults
    /// Set by the panel controller on show/hide. Hidden → `current` cleared, pending kept for the next show.
    @ObservationIgnored var visible = false {
        didSet { if visible { present() } else { current = nil } }
    }
    /// Mirrors `ShelfStore.isDragging || isDropTargeted`: never a new hint during a drag.
    @ObservationIgnored var dragging = false {
        didSet { if !dragging { present() } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func count(_ hint: Hint) -> Int { counts[hint.rawValue] ?? 0 }
    var dismissed: Set<String> { Set(defaults.stringArray(forKey: Self.dismissedKey) ?? []) }
    private var counts: [String: Int] { defaults.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:] }

    /// Tips on, not dismissed, shown fewer than `maxShows` times; the hotkey tip only while the shortcut is on.
    func eligible(_ hint: Hint) -> Bool {
        Preferences.tipsOn(defaults) && !dismissed.contains(hint.rawValue) && count(hint) < Self.maxShows
            && (hint != .hotkey || Preferences.hotKeyOn(defaults))
    }

    func record(_ event: Event) {
        let triggered: [Hint]
        switch event {
        case .dropped: triggered = [.firstDrop]
        case .draggedOut(let removed): triggered = removed ? [.dragOut, .recent] : [.recent]
        case .cleared: triggered = [.clear]
        case .shown(let reason, let hasFile, let hasRecent):
            let shows = defaults.integer(forKey: Self.showsKey) + 1
            defaults.set(shows, forKey: Self.showsKey)
            var menuShows = defaults.integer(forKey: Self.menuShowsKey)
            if reason == .manual {
                menuShows += 1
                defaults.set(menuShows, forKey: Self.menuShowsKey)
            }
            triggered = (reason == .manual && menuShows >= 2 ? [.hotkey] : []) + (hasRecent ? [.recent] : [])
                + (hasFile ? [.holdCommand] : []) + (shows >= 3 ? [.moveResize] : [])
        }
        pending.formUnion(triggered.filter(eligible))
        present()
    }

    /// ✕: never show this hint again.
    func dismiss() {
        guard let current else { return }
        defaults.set((dismissed.union([current.rawValue])).sorted(), forKey: Self.dismissedKey)
        self.current = nil
    }

    /// Settings → Reset Tips: every hint shows again from zero.
    static func reset(_ defaults: UserDefaults = .standard) {
        for key in [countsKey, dismissedKey, showsKey, menuShowsKey] { defaults.removeObject(forKey: key) }
    }

    private func present() {
        guard visible, !dragging, let next = Hint.allCases.first(where: { pending.contains($0) && eligible($0) }) else { return }
        pending.removeAll()
        var all = counts
        all[next.rawValue, default: 0] += 1
        defaults.set(all, forKey: Self.countsKey)
        current = next
    }
}
