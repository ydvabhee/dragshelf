import CryptoKit
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
    /// File items whose file was gone at the last `refreshMissing()` (panel show).
    private(set) var missingIDs: Set<UUID> = []
    /// Bumped by `clear()`; async work (file promises) started before a clear must not land after it.
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored let cache: ItemCache
    /// Dedupe index beside `items` (O(1) add). Image items key by content hash, everything else by kind.
    @ObservationIgnored private(set) var keys: [Key: UUID] = [:]

    enum Key: Hashable {
        case file(String), url(String), text(String), image(SHA256.Digest)
    }

    init(cache: ItemCache = ItemCache()) {
        self.cache = cache
    }

    /// Appends in drop order. Same file path, URL, or exact text keeps one item; returns false on duplicate.
    /// Same `contentHash` replaces the old item (its cache dir deleted) and appends the new one.
    /// Caller owns any cache dir of a rejected duplicate.
    @discardableResult
    func add(_ item: ShelfItem) -> Bool {
        let key = Self.key(for: item)
        if let old = keys[key] {
            guard case .image = key, let i = items.firstIndex(where: { $0.id == old }) else { return false }
            removeCacheDir(of: items[i])
            selection.remove(old)
            // One assignment: the shelf never looks empty mid-replace (empty → panel hides).
            var next = items
            next.remove(at: i)
            items = next + [item]
        } else {
            items.append(item)
        }
        keys[key] = item.id
        return true
    }

    /// `deletingCache: false` leaves cache dirs for the clear/quit wipe (drag out: targets read files late).
    func remove(ids: Set<UUID>, deletingCache: Bool = true) {
        if deletingCache { items.filter { ids.contains($0.id) }.forEach(removeCacheDir(of:)) }
        items.removeAll { ids.contains($0.id) }
        keys = keys.filter { !ids.contains($0.value) }
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

    /// Arrow keys: selects the tile `delta` away (±1 left/right, ±columns up/down); none selected → first.
    /// Down onto a shorter last row lands on the last item; any other move off the grid is ignored.
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = selection.isEmpty ? nil
            : items.firstIndex { $0.id == anchor && selection.contains($0.id) } ?? items.lastIndex { selection.contains($0.id) }
        guard let current else { return select(items[0].id, command: false, shift: false) }
        var next = current + delta
        if delta > 1, next >= items.count, current / delta < (items.count - 1) / delta { next = items.count - 1 }
        guard items.indices.contains(next) else { return }
        select(items[next].id, command: false, shift: false)
    }

    /// Ids a tile action (Remove, Quick Look) applies to: the selection if the tile is in it, else the tile.
    func targetIDs(for id: UUID) -> Set<UUID> {
        selection.contains(id) ? selection : [id]
    }

    /// Dragging a selected tile drags the whole selection; an unselected tile drags alone; `nil` = all.
    /// Missing files never drag.
    func dragItems(for id: UUID?) -> [ShelfItem] {
        let ids = id.map(targetIDs(for:))
        return items.filter { (ids?.contains($0.id) ?? true) && !missing(id: $0.id) }
    }

    /// Selected, present files: what Quick Look shows.
    var previewURLs: [URL] {
        selectedItems.compactMap { if case .file(let url) = $0.kind, !missing(id: $0.id) { url } else { nil } }
    }

    /// Bounds-safe: Quick Look may ask with an index from before the last change.
    func previewURL(at index: Int) -> URL? {
        let urls = previewURLs
        return urls.indices.contains(index) ? urls[index] : nil
    }

    func missing(id: UUID) -> Bool { missingIDs.contains(id) }

    /// Marks file items whose file no longer exists. Runs each time the panel shows.
    func refreshMissing() {
        let gone = Set(items.filter {
            if case .file(let url) = $0.kind { !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) } else { false }
        }.map(\.id))
        if gone != missingIDs { missingIDs = gone }
    }

    func clear() {
        generation += 1
        cache.wipe()
        items.removeAll()
        keys.removeAll()
        selection.removeAll()
        missingIDs.removeAll()
    }

    /// File paths compare after resolving `..`, trailing slash, and symlinks (/tmp vs /private/tmp), once per add.
    static func key(for item: ShelfItem) -> Key {
        if let hash = item.contentHash { return .image(hash) }
        switch item.kind {
        case .file(let url):
            let u = url.standardizedFileURL
            // Resolve the parent so symlinks normalize even when the file itself is gone.
            return .file(u.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(u.lastPathComponent).path(percentEncoded: false))
        case .url(let url): return .url(url.absoluteString)
        case .text(let text): return .text(text)
        }
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
