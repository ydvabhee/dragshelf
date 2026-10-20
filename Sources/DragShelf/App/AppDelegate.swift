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
        // `autoShow` key per ARCHITECTURE §4; T-10 adds the UI and live start/stop.
        if UserDefaults.standard.object(forKey: "autoShow") as? Bool != false { dragMonitor.start() }
        hotKey.onPress = { [weak self] in self?.panelController.toggle() }
        // `hotKeyEnabled` per ARCHITECTURE §4 (default on); T-10 calls hotKey.register()/unregister() live.
        if UserDefaults.standard.object(forKey: "hotKeyEnabled") as? Bool != false { hotKey.register() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        store.cache.wipe()
    }
}
