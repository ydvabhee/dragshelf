import Foundation
import Observation

@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []
    /// Shift-click range start: the last plain or Cmd-clicked item.
    @ObservationIgnored private var anchor: UUID?
    /// True while a drag hovers the panel (set by `DropReceiver`).
    var isDropTargeted = false
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

    /// `deletingCache: false` leaves cache dirs for the clear/quit wipe (drag out: targets read files late).
    func remove(ids: Set<UUID>, deletingCache: Bool = true) {
        if deletingCache { items.filter { ids.contains($0.id) }.forEach(removeCacheDir(of:)) }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    var selectedItems: [ShelfItem] { items.filter { selection.contains($0.id) } }

    /// Finder-style click: plain selects one, Cmd toggles, Shift selects the range from the anchor.
    func select(_ id: UUID, command: Bool, shift: Bool) {
        if shift, let anchor, let from = items.firstIndex(where: { $0.id == anchor }),
           let to = items.firstIndex(where: { $0.id == id }) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
            return
        }
        if command { selection.formSymmetricDifference([id]) } else { selection = [id] }
        anchor = id
    }

    /// Dragging a selected tile drags the whole selection; an unselected tile drags alone.
    func dragItems(for id: UUID) -> [ShelfItem] {
        selection.contains(id) ? selectedItems : items.filter { $0.id == id }
    }

    func clear() {
        cache.wipe()
        items.removeAll()
        selection.removeAll()
    }

    /// File paths compare after resolving `..`, trailing slash, and symlinks (/tmp vs /private/tmp).
    private static func dedupeKey(_ kind: ShelfItem.Kind) -> ShelfItem.Kind {
        if case .file(let url) = kind { let u = url.standardizedFileURL
            // Resolve the parent so symlinks normalize even when the file itself is gone.
            return .file(u.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(u.lastPathComponent))
        }
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
