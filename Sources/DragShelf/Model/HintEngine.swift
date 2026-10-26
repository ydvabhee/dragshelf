import Foundation
import Observation

/// One-line contextual tips in the footer slot (T-18). Events add eligible hints to `pending`; the top-priority one
/// becomes `current` once the panel is visible and no drag runs. Each hint shows at most `maxShows` times, ✕ retires
/// it for good. Counts and dismissals live in UserDefaults (injectable for tests).
@Observable
final class HintEngine {
    /// Declaration order = priority (first wins).
    enum Hint: String, CaseIterable {
        case clear, dragOut, firstDrop, hotkey, recent, holdCommand, moveResize, paste, pin, search

        var text: String {
            switch self {
            case .clear: "Clear only empties DragShelf; your files aren't touched."
            case .dragOut: "Removed from DragShelf · ⌘Z to bring it back"
            case .firstDrop: "Switch apps, then drag items out of DragShelf."
            case .hotkey: "Tip: \(Preferences.shortcut().display) shows DragShelf from anywhere."
            case .recent: "Recent drags are under the clock icon."
            case .holdCommand: "Hold ⌘ while dragging out to move instead of copy."
            case .moveResize: "Drag the top bar to move DragShelf · edges to resize."
            case .paste: "⌘V pastes your clipboard into DragShelf."
            case .pin: "Right-click an item and Pin it to keep it on DragShelf."
            case .search: "⌘F finds anything on DragShelf."
            }
        }

        /// The same tip in the shelf pet's words (V3-01): short, first person, at most two lines.
        var bubbleText: String {
            switch self {
            case .clear: "Clear only empties DragShelf — your files stay put"
            case .dragOut: "Oops? ⌘Z brings it back"
            case .firstDrop: "I'll hold it! Switch apps, then drag it out of here"
            case .hotkey: "\(Preferences.shortcut().display) brings DragShelf back from anywhere"
            case .recent: "Your recent drags are under the clock 🕘"
            case .holdCommand: "Hold ⌘ while dragging out to move it"
            case .moveResize: "Drag the top bar to move DragShelf, the edges to resize"
            case .paste: "⌘V pastes your clipboard here"
            case .pin: "Pin things you use often 📌"
            case .search: "⌘F finds anything on the shelf"
            }
        }
    }

    enum Event {
        case dropped
        /// `removed`: the drag out took items off DragShelf (not kept, not a Recent row).
        case draggedOut(removed: Bool)
        case cleared
        /// `itemCount`: items on DragShelf at show time (paste, pin and search tips).
        case shown(ShelfPanelController.ShowReason, hasFile: Bool, hasRecent: Bool, itemCount: Int = 0)
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

    /// The hotkey tip needs a registered shortcut (on, and not refused by Carbon). Injectable for tests.
    @ObservationIgnored var shortcutRegistered: () -> Bool = { HotKey.shared.current != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func count(_ hint: Hint) -> Int { counts[hint.rawValue] ?? 0 }
    var dismissed: Set<String> { Set(defaults.stringArray(forKey: Self.dismissedKey) ?? []) }
    private var counts: [String: Int] { defaults.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:] }

    /// Tips on, not dismissed, shown fewer than `maxShows` times; the hotkey tip only while the shortcut is on and registered.
    func eligible(_ hint: Hint) -> Bool {
        Preferences.tipsOn(defaults) && !dismissed.contains(hint.rawValue) && count(hint) < Self.maxShows
            && (hint != .hotkey || (Preferences.hotKeyOn(defaults) && shortcutRegistered()))
    }

    func record(_ event: Event) {
        let triggered: [Hint]
        switch event {
        case .dropped: triggered = [.firstDrop]
        case .draggedOut(let removed): triggered = removed ? [.dragOut, .recent] : [.recent]
        case .cleared: triggered = [.clear]
        case .shown(let reason, let hasFile, let hasRecent, let itemCount):
            let shows = defaults.integer(forKey: Self.showsKey) + 1
            defaults.set(shows, forKey: Self.showsKey)
            var menuShows = defaults.integer(forKey: Self.menuShowsKey)
            if reason == .manual {
                menuShows += 1
                defaults.set(menuShows, forKey: Self.menuShowsKey)
            }
            triggered = (reason == .manual && menuShows >= 2 ? [.hotkey] : []) + (hasRecent ? [.recent] : [])
                + (hasFile ? [.holdCommand] : []) + (shows >= 3 ? [.moveResize] : [])
                + (shows >= 2 && itemCount >= 1 ? [.paste] : []) + (itemCount >= 4 ? [.pin] : [])
                + (itemCount >= 8 ? [.search] : [])
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

    /// Settings → Reset Tips: every hint shows again from zero; a tip on screen goes away now.
    func reset() {
        for key in [Self.countsKey, Self.dismissedKey, Self.showsKey, Self.menuShowsKey] { defaults.removeObject(forKey: key) }
        pending.removeAll()
        current = nil
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
