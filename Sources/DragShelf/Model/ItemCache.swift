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

    /// Removes everything under `root` except the item dirs named in `keeping`.
    func wipe(keeping: Set<String> = []) {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        contents.filter { !keeping.contains($0.lastPathComponent) }.forEach(remove(dir:))
    }

    /// One top-level item dir: size on disk (sum of file sizes) and last change time.
    struct Entry: Sendable { let name: String; let bytes: Int; let modified: Date }

    /// One listing of `root`; empty when the cache is empty. Blocking: call off the main actor.
    func scan() -> [Entry] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return dirs.map { dir in
            var bytes = 0, modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let files = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            while let f = files?.nextObject() as? URL {
                let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                bytes += v?.fileSize ?? 0
                if let m = v?.contentModificationDate, m > modified { modified = m }
            }
            return Entry(name: dir.lastPathComponent, bytes: bytes, modified: modified)
        }
    }
}
