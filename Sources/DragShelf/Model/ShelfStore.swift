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
        guard !items.contains(where: { $0.kind == item.kind }) else { return false }
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

    private func removeCacheDir(of item: ShelfItem) {
        guard item.isCached, case .file(let url) = item.kind else { return }
        let dir = url.deletingLastPathComponent()
        // Only ever delete a direct child of the cache root.
        if dir.deletingLastPathComponent().standardizedFileURL == cache.root.standardizedFileURL {
            cache.remove(dir: dir)
        }
    }
}
