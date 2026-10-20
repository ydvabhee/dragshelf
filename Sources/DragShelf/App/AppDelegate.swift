import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    lazy var panelController = ShelfPanelController(store: store)
    let dragMonitor = DragMonitor()
    let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
        dragMonitor.onDragStart = { [weak self] point in self?.panelController.dragStarted(at: point) }
        dragMonitor.onDragEnd = { [weak self] in self?.panelController.dragEnded() }
        hotKey.onPress = { [weak self] in self?.panelController.toggle() }
        applyPreferences()
        // Settings toggles apply immediately; both calls are idempotent.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    private func applyPreferences() {
        if Preferences.autoShowEnabled() { dragMonitor.start() } else { dragMonitor.stop() }
        if Preferences.hotKeyOn() { hotKey.register() } else { hotKey.unregister() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        store.cache.wipe()
    }
}
