import Foundation
import os

private let log = Logger(subsystem: PromoConfig.selfBundleID, category: "pins")

/// Pinned items on disk (V2-08): `root/pinned.json` plus stored copies in `root/<UUID>/<name>`.
/// `root` lives in Application Support, never under the cache root, so the launch/quit wipe and the T-21 sweep never
/// see it. Injectable; under a test runner the default is a fresh temp dir, so tests never touch the user's folder.
struct PinStore {
    let root: URL

    init(root: URL = PinStore.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        // V2-10 AC-8: a test that forgets to inject a root still never writes Application Support.
        if TestRun.active {
            return FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfTests-Pinned-\(UUID().uuidString)", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.abhishekyadav.DragShelf/Pinned", isDirectory: true)
    }

    var manifest: URL { root.appendingPathComponent("pinned.json") }
    var backup: URL { root.appendingPathComponent("pinned.json.bad") }

    static let version = 1

    struct Manifest: Codable { let version: Int; let items: [Entry] }
    struct Entry: Codable { let id: UUID; let item: Stored }
    /// Original files: bookmark data plus the last known path (shown as Missing when the bookmark does not resolve).
    /// Stored copies: path relative to `root`, exactly "<UUID>/<name>".
    enum Stored: Codable { case original(bookmark: Data, path: String), copy(String), url(String), text(String) }

    struct Invalid: Error {}

    /// Pinned items in manifest order and the bookmarks of the originals. No manifest → empty. A corrupt, unknown-version
    /// or invalid manifest is moved to `pinned.json.bad` (or `.bad.1`, `.bad.2`, … so the first backup is kept) and
    /// loading starts empty; stored copies are then never deleted. After a clean load, `<UUID>/` dirs the manifest does
    /// not reference (a pin or rename interrupted before its save) are removed. Stale bookmarks are refreshed and the
    /// manifest is rewritten.
    func load() -> (items: [ShelfItem], bookmarks: [UUID: Data]) {
        guard let data = try? Data(contentsOf: manifest) else { return ([], [:]) }
        var items: [ShelfItem] = [], bookmarks: [UUID: Data] = [:], refreshed = false
        do {
            let m = try JSONDecoder().decode(Manifest.self, from: data)
            guard m.version == Self.version, Set(m.items.map(\.id)).count == m.items.count else { throw Invalid() }
            for entry in m.items {
                switch entry.item {
                case .url(let s):
                    guard let url = URL(string: s) else { throw Invalid() }
                    items.append(ShelfItem(id: entry.id, kind: .url(url)))
                case .text(let text):
                    items.append(ShelfItem(id: entry.id, kind: .text(text)))
                case .copy(let rel):
                    guard let url = storedURL(rel) else { throw Invalid() }
                    items.append(ShelfItem(id: entry.id, kind: .file(url), isCached: true))
                case .original(let bookmark, let path):
                    guard path.hasPrefix("/") else { throw Invalid() }
                    var stale = false, url = URL(fileURLWithPath: path)
                    bookmarks[entry.id] = bookmark
                    if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                               relativeTo: nil, bookmarkDataIsStale: &stale) {
                        // Same file under another spelling (/var vs /private/var) keeps the saved path.
                        let moved = resolved.resolvingSymlinksInPath() != url.resolvingSymlinksInPath()
                        if moved { url = resolved }
                        if stale || moved, let fresh = try? resolved.bookmarkData() {
                            bookmarks[entry.id] = fresh
                            refreshed = true
                        }
                    }
                    items.append(ShelfItem(id: entry.id, kind: .file(url)))
                }
            }
        } catch {
            log.error("pinned.json unreadable (\(error.localizedDescription, privacy: .public)); kept as pinned.json.bad")
            var dest = backup, n = 0
            while FileManager.default.fileExists(atPath: dest.path) {
                n += 1
                dest = root.appendingPathComponent("pinned.json.bad.\(n)")
            }
            try? FileManager.default.moveItem(at: manifest, to: dest)
            return ([], [:])
        }
        let kept = Set(items.compactMap { if case .file(let url) = $0.kind { dir(of: url)?.lastPathComponent } else { nil } })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        where UUID(uuidString: name) != nil && !kept.contains(name) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
        if refreshed { save(items, bookmarks: bookmarks) }
        return (items, bookmarks)
    }

    /// Writes the manifest atomically. A file item is a stored copy when it lives under `root`, else an original with
    /// its bookmark (an original without one is skipped and logged).
    func save(_ items: [ShelfItem], bookmarks: [UUID: Data]) {
        let entries = items.compactMap { item -> Entry? in
            let stored: Stored
            switch item.kind {
            case .url(let url): stored = .url(url.absoluteString)
            case .text(let text): stored = .text(text)
            case .file(let url):
                if let rel = relativePath(of: url) { stored = .copy(rel) }
                else if let bookmark = bookmarks[item.id] { stored = .original(bookmark: bookmark, path: url.path) }
                else { log.error("pinned file has no bookmark; not saved"); return nil }
            }
            return Entry(id: item.id, item: stored)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Manifest(version: Self.version, items: entries)).write(to: manifest, options: .atomic)
        } catch {
            log.error("pinned.json not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clones `url` into a new `root/<UUID>/` (APFS clone on the same volume) and returns the copy.
    // ponytail: copies on the caller's thread; a cross-volume multi-GB copy would block. Upgrade = an ActionRunner job.
    func store(_ url: URL) throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        do { try FileManager.default.copyItem(at: url, to: dest) } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        return dest
    }

    /// The `root/<UUID>/` dir that holds a stored copy, or nil when `url` is not one.
    func dir(of url: URL) -> URL? {
        relativePath(of: url).map { root.appendingPathComponent(String($0.split(separator: "/")[0]), isDirectory: true) }
    }

    /// "<UUID>/<name>" for a file directly inside a stored-copy dir, else nil.
    func relativePath(of url: URL) -> String? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parts.count == base.count + 2, Array(parts.prefix(base.count)) == base else { return nil }
        let rel = parts.suffix(2).joined(separator: "/")
        return storedURL(rel) == nil ? nil : rel
    }

    /// Strict: exactly "<UUID>/<name>" with a plain name, so a manifest can never point outside `root`.
    private func storedURL(_ rel: String) -> URL? {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, UUID(uuidString: String(parts[0])) != nil,
              !parts[1].isEmpty, parts[1] != ".", parts[1] != ".." else { return nil }
        return root.appendingPathComponent(String(parts[0]), isDirectory: true).appendingPathComponent(String(parts[1]))
    }
}
