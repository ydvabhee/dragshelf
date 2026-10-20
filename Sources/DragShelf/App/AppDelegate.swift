import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    lazy var panelController = ShelfPanelController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.cache.wipe()
    }
}
