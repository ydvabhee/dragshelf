import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.cache.wipe()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.cache.wipe()
    }
}
