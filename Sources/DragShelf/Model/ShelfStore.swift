import Foundation
import Observation

@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []
    @ObservationIgnored let cache: ItemCache

    init(cache: ItemCache = ItemCache()) {
        self.cache = cache
    }

    /// Appends in drop order. Same file path, URL, or exact text keeps one item; returns false on duplicate.
    /// Caller owns any cache dir of a rejected duplicate.
    @discardableResult
    func add(_ item: ShelfItem) -> Bool {
        let key = Self.dedupeKey(item.kind)
        guard !items.contains(where: { Self.dedupeKey($0.kind) == key }) else { return false }
        items.append(item)
        return true
    }

    func remove(ids: Set<UUID>) {
        items.filter { ids.contains($0.id) }.forEach(removeCacheDir(of:))
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func clear() {
        cache.wipe()
        items.removeAll()
        selection.removeAll()
    }

    /// File paths compare after resolving `..`, trailing slash, and symlinks (/tmp vs /private/tmp).
    private static func dedupeKey(_ kind: ShelfItem.Kind) -> ShelfItem.Kind {
        if case .file(let url) = kind { return .file(url.standardizedFileURL.resolvingSymlinksInPath()) }
        return kind
    }

    private func removeCacheDir(of item: ShelfItem) {
        guard item.isCached, case .file(let url) = item.kind else { return }
        let root = cache.root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        // Delete the direct child of root that contains the file (handles nested files).
        guard parts.count > root.count + 1, Array(parts.prefix(root.count)) == root else { return }
        cache.remove(dir: cache.root.appendingPathComponent(parts[root.count], isDirectory: true))
    }
}
