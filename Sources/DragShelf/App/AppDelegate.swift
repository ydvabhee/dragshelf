import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    let promos = PromoLoader()
    lazy var panelController = ShelfPanelController(store: store, promos: promos)
    let dragMonitor = DragMonitor()
    let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
        dragMonitor.onDragStart = { [weak self] point in self?.panelController.dragStarted(at: point) }
        dragMonitor.onDragEnd = { [weak self] in self?.panelController.dragEnded() }
        hotKey.onPress = { [weak self] in self?.panelController.toggle(reason: .hotkey) }
        applyPreferences()
        // Settings toggles apply immediately; both calls are idempotent.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    private var appliedAutoShow: Bool?
    private var appliedHotKey: Bool?
    private var appliedPromos: Bool?

    /// Fires on every UserDefaults change (incl. shelf moves): act only when a value changed.
    private func applyPreferences() {
        let autoShow = Preferences.autoShowEnabled(), hotKeyOn = Preferences.hotKeyOn()
        if autoShow != appliedAutoShow {
            appliedAutoShow = autoShow
            if autoShow { dragMonitor.start() } else { dragMonitor.stop() }
        }
        if hotKeyOn != appliedHotKey {
            appliedHotKey = hotKeyOn
            if hotKeyOn { hotKey.register() } else { hotKey.unregister() }
        }
        // Launch and toggle-on: fetch if the cached feed is > 24 h old. Off: no request at all.
        let promosOn = Preferences.promosOn()
        if promosOn != appliedPromos {
            appliedPromos = promosOn
            if promosOn { Task { await promos.refreshIfStale() } }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        store.cache.wipe()
    }
}
