import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    let promos = PromoLoader()
    lazy var panelController = ShelfPanelController(store: store, promos: promos)
    let dragMonitor = DragMonitor()
    let hotKey = HotKey.shared
    private var sweepTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
        // Pinned items live outside the cache (V2-08), so the wipe above never touches them.
        store.loadPins()
        dragMonitor.onDragStart = { [weak self] point in self?.panelController.dragStarted(at: point) }
        dragMonitor.onDragEnd = { [weak self] in self?.panelController.dragEnded() }
        hotKey.onPress = { [weak self] in self?.panelController.toggle(reason: .hotkey) }
        applyPreferences()
        // T-21: periodic cache sweep; each pass is a single directory listing when the cache is empty.
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let store = self?.store { Task { await store.sweep() } } }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
        // Settings toggles apply immediately; both calls are idempotent.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    private var appliedAutoShow: Bool?
    private var appliedShortcut: Shortcut?
    private var appliedPromos: Bool?

    /// Fires on every UserDefaults change (incl. shelf moves): act only when a value changed.
    private func applyPreferences() {
        let autoShow = Preferences.autoShowEnabled(), hotKeyOn = Preferences.hotKeyOn()
        if autoShow != appliedAutoShow {
            appliedAutoShow = autoShow
            if autoShow { dragMonitor.start() } else { dragMonitor.stop() }
        }
        // Settings registers a new shortcut itself first (to report a refusal), so this is then a no-op.
        let shortcut = hotKeyOn ? Preferences.shortcut() : nil
        if shortcut != appliedShortcut {
            appliedShortcut = shortcut
            if let shortcut { hotKey.register(shortcut) } else { hotKey.unregister() }
        }
        // Launch and toggle-on: fetch if the cached feed is > 24 h old. Off: no request at all.
        let promosOn = Preferences.promosOn()
        if promosOn != appliedPromos {
            appliedPromos = promosOn
            if promosOn { Task { await promos.refreshIfStale() } }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sweepTimer?.invalidate()
        hotKey.unregister()
        store.actions.cancel()
        store.cache.wipe()
    }
}
