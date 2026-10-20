import Foundation

/// Cache dirs for materialized items. `root` is injectable so tests never touch ~/Library/Caches.
nonisolated struct ItemCache: Sendable {
    let root: URL

    init(root: URL = ItemCache.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.abhishekyadav.DragShelf/Shelf", isDirectory: true)
    }

    /// Creates `root/<UUID>/`.
    func newItemDir() throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func remove(dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Removes everything under `root`.
    func wipe() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        contents.forEach(remove(dir:))
    }
}
