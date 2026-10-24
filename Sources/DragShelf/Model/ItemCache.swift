import Foundation

/// True only inside `swift test` / Xcode tests, so default roots never point at the user's folders (V2-10 AC-8).
nonisolated enum TestRun {
    static let active = detect(bundlePath: Bundle.main.bundlePath, arguments: ProcessInfo.processInfo.arguments,
                               environment: ProcessInfo.processInfo.environment)

    /// The app bundle is never a test run, whatever its arguments. Otherwise: Xcode's test config variable, or a
    /// runner argument with a `.xctest` bundle in its path (`swift test` passes `…/X.xctest/Contents/MacOS/X`).
    static func detect(bundlePath: String, arguments: [String], environment: [String: String]) -> Bool {
        guard !bundlePath.hasSuffix(".app") else { return false }
        return environment["XCTestConfigurationFilePath"] != nil
            || arguments.dropFirst().contains { URL(fileURLWithPath: $0).pathComponents.contains { $0.hasSuffix(".xctest") } }
    }
}

/// Cache dirs for materialized items. `root` is injectable so tests never touch ~/Library/Caches.
nonisolated struct ItemCache: Sendable {
    let root: URL

    init(root: URL = ItemCache.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        // Like `PinStore.defaultRoot`: a test that forgets to inject a root never touches the user's cache.
        if TestRun.active {
            return FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfTests-Cache-\(UUID().uuidString)", isDirectory: true)
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
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
