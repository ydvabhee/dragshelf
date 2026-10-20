import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    lazy var panelController = ShelfPanelController(store: store)
    let dragMonitor = DragMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
        dragMonitor.onDragStart = { [weak self] point in self?.panelController.dragStarted(at: point) }
        dragMonitor.onDragEnd = { [weak self] in self?.panelController.dragEnded() }
        // `autoShow` key per ARCHITECTURE §4; T-10 adds the UI and live start/stop.
        if UserDefaults.standard.object(forKey: "autoShow") as? Bool != false { dragMonitor.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.cache.wipe()
    }
}
