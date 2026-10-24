import CryptoKit
import Foundation
import Observation
import os

private let log = Logger(subsystem: PromoConfig.selfBundleID, category: "cache")

/// One successful drag out: the batch of items dragged (T-17).
struct RecentEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    /// `var`: re-pointed when a pinned copy it references moves (V2-10 AC-6).
    var items: [ShelfItem]
}

@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []
    /// Shift-click range start: the last plain or Cmd-clicked item.
    @ObservationIgnored private var anchor: UUID?
    /// True while a drag hovers the panel (set by `DropReceiver`).
    var isDropTargeted = false { didSet { hints.dragging = isDragging || isDropTargeted } }
    /// True while a system drag (auto-show) or a drag out runs; hides the promo footer (T-14) and holds back hints (T-18).
    var isDragging = false { didSet { hints.dragging = isDragging || isDropTargeted } }
    /// File items whose file was gone at the last `refreshMissing()` (panel show).
    private(set) var missingIDs: Set<UUID> = []
    /// Last drag outs, newest first, at most `recentLimit`. Memory only (OQ-03); their cache dirs are kept.
    private(set) var recent: [RecentEntry] = []
    static let recentLimit = 5
    // ponytail: fixed limits; upgrade path is a Settings entry.
    static let cacheCapBytes = 1 << 30
    static let recentMaxAge: TimeInterval = 24 * 3600
    /// In-flight guard: a dir changed within this window may belong to a drop still landing (not on the shelf yet).
    static let sweepGrace: TimeInterval = 10
    /// Cache dir names of drops still receiving (file promise, image write): `sweep` never deletes them.
    @ObservationIgnored private(set) var inFlight: Set<String> = []
    func beginInFlight(_ dir: URL) { inFlight.insert(dir.lastPathComponent) }
    func endInFlight(_ dir: URL) { inFlight.remove(dir.lastPathComponent) }
    /// Clock button: the Recent list replaces the grid. Reset on show and on any drop (T-20 AC-8).
    var showRecent = false
    /// Image items in the Custom… resize form (V2-05), shown in place of the grid; nil = no form. Reset like Recent.
    var resizing: [ShelfItem]?
    /// Bumped by `clear()`; async work (file promises) started before a clear must not land after it.
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored let cache: ItemCache
    @ObservationIgnored let hints: HintEngine
    /// Shelf actions (V2-01): one job at a time; Clear cancels it.
    @ObservationIgnored let actions = ActionRunner()
    /// Dedupe index beside `items` (O(1) add). Image items key by content hash, everything else by kind.
    @ObservationIgnored private(set) var keys: [Key: UUID] = [:]

    enum Key: Hashable {
        case file(String), url(String), text(String), image(SHA256.Digest)
    }

    init(cache: ItemCache = ItemCache(), hints: HintEngine = HintEngine(), pins: PinStore = PinStore()) {
        self.cache = cache
        self.hints = hints
        self.pins = pins
    }

    /// Appends in drop order. Same file path, URL, or exact text keeps one item; returns false on duplicate.
    /// Same `contentHash` replaces the old item (its cache dir deleted) and appends the new one, unless the old one is
    /// pinned (then rejected like any duplicate). Caller owns any cache dir of a rejected duplicate.
    @discardableResult
    func add(_ item: ShelfItem) -> Bool {
        let key = Self.key(for: item)
        if let old = keys[key] {
            guard case .image = key, !pinnedIDs.contains(old), let i = items.firstIndex(where: { $0.id == old }) else { return false }
            let replaced = items[i]
            selection.remove(old)
            // One assignment: the shelf never looks empty mid-replace (empty → panel hides).
            var next = items
            next.remove(at: i)
            items = next + [item]
            release([replaced])
        } else {
            items.append(item)
        }
        keys[key] = item.id
        return true
    }

    /// `deletingCache: false` leaves cache dirs for the clear/quit wipe (drag out: targets read files late).
    /// Pinned items are never removed (unpin first).
    func remove(ids: Set<UUID>, deletingCache: Bool = true) {
        let ids = ids.subtracting(pinnedIDs)
        let gone = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        keys = keys.filter { !ids.contains($0.value) }
        selection.subtract(ids)
        if deletingCache { release(gone) }
    }

    // MARK: Rename (V2-04)

    /// Tile whose caption is an inline rename field; nil when not renaming.
    var renamingID: UUID?

    /// Swaps the item at `id`'s index (same id: position and selection stay) and its `keys` entry, then frees the
    /// old cache dir if nothing uses it any more. False when `id` is no longer on the shelf.
    @discardableResult
    func replace(id: UUID, with item: ShelfItem) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        let old = items[i]
        swap(at: i, to: item)
        missingIDs.remove(id)
        release([old])
        // A renamed pinned item (now a clone in the cache) is stored again, then its previous stored copy goes.
        // If storing fails, the manifest and the old copy stay as they were (the next launch shows the old name).
        if pinnedIDs.contains(id), let stored = storedForPin(item) {
            swap(at: i, to: stored)
            release([item])
            if let dir = pinDir(of: old), dir != pinDir(of: stored) {
                repointRecent(old, to: stored)
                try? FileManager.default.removeItem(at: dir)
            }
            savePins()
        }
        return true
    }

    /// Puts `item` at index `i` (same id) and re-keys it.
    private func swap(at i: Int, to item: ShelfItem) {
        items[i] = item
        keys = keys.filter { $0.value != item.id }
        keys[Self.key(for: item)] = item.id
    }

    // MARK: Pin (V2-08)

    /// Pinned items lead `items` (pinned group, then the rest) and survive Clear, drag out, and quit (saved in `pins`).
    private(set) var pinnedIDs: Set<UUID> = []
    @ObservationIgnored let pins: PinStore
    /// Bookmark data of pinned original files, by item id.
    @ObservationIgnored private var bookmarks: [UUID: Data] = [:]

    func isPinned(_ id: UUID) -> Bool { pinnedIDs.contains(id) }

    /// Launch: the saved pinned items become the shelf. Call once, before anything is added.
    func loadPins() {
        let loaded = pins.load()
        items = loaded.items
        bookmarks = loaded.bookmarks
        pinnedIDs = Set(loaded.items.map(\.id))
        loaded.items.forEach { keys[Self.key(for: $0)] = $0.id }
    }

    /// Pins the present items of `targets`; each joins the end of the pinned group. Cached files are cloned into the
    /// Pinned folder (the cache dir is released), originals are saved as bookmarks. A failure skips that item (logged).
    func pin(_ targets: [ShelfItem]) {
        for target in targets where !pinnedIDs.contains(target.id) && Self.exists(target) {
            guard let i = items.firstIndex(where: { $0.id == target.id }) else { continue }
            let old = items[i]
            guard let stored = storedForPin(old) else { continue }
            swap(at: i, to: stored)
            move(from: i, to: pinnedIDs.count)
            pinnedIDs.insert(target.id)
            release([old])
        }
        savePins()
    }

    /// Unpins `ids`; each goes to the top of the unpinned items. A stored copy leaves the Pinned folder: its dir moves
    /// into the cache, so the item stays usable and is deleted like any cached item (remove, Clear, quit).
    func unpin(_ ids: Set<UUID>) {
        for id in ids where pinnedIDs.contains(id) {
            guard let i = items.firstIndex(where: { $0.id == id }) else { continue }
            let item = items[i]
            if case .file(let url) = item.kind, let dir = pins.dir(of: url) {
                let dest = cache.root.appendingPathComponent(dir.lastPathComponent, isDirectory: true)
                if FileManager.default.fileExists(atPath: dir.path) {
                    do {
                        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: dir, to: dest)
                    } catch {
                        log.error("unpin kept the item pinned: \(error.localizedDescription, privacy: .public)")
                        continue
                    }
                }
                let moved = ShelfItem(id: id, kind: .file(dest.appendingPathComponent(url.lastPathComponent)),
                                      isCached: true, contentHash: item.contentHash)
                swap(at: i, to: moved)
                repointRecent(item, to: moved)
            }
            bookmarks[id] = nil
            pinnedIDs.remove(id)
            move(from: i, to: pinnedIDs.count)
        }
        savePins()
    }

    /// What a pinned item points at: a cached file is cloned into the Pinned folder; an original file gets a bookmark;
    /// a stored copy, link, or text stays as it is. Nil when the clone or bookmark fails.
    private func storedForPin(_ item: ShelfItem) -> ShelfItem? {
        guard case .file(let url) = item.kind, pinDir(of: item) == nil else {
            bookmarks[item.id] = nil
            return item
        }
        do {
            if item.isCached {
                let copy = try pins.store(url)
                bookmarks[item.id] = nil
                return ShelfItem(id: item.id, kind: .file(copy), isCached: true, contentHash: item.contentHash)
            }
            bookmarks[item.id] = try url.bookmarkData()
            return item
        } catch {
            log.error("pin failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Recent rows that point at `old`'s file follow it to `new` when a pinned copy moves (unpin) or is replaced
    /// (rename), so they never show "Missing" for a file that still exists (V2-10 AC-6).
    private func repointRecent(_ old: ShelfItem, to new: ShelfItem) {
        for i in recent.indices {
            for j in recent[i].items.indices where recent[i].items[j].kind == old.kind {
                let row = recent[i].items[j]
                recent[i].items[j] = ShelfItem(id: row.id, kind: new.kind, isCached: new.isCached, contentHash: row.contentHash)
            }
        }
    }

    private func pinDir(of item: ShelfItem) -> URL? {
        if case .file(let url) = item.kind { pins.dir(of: url) } else { nil }
    }

    /// One assignment, so the grid animates a single move.
    private func move(from i: Int, to j: Int) {
        var next = items
        next.insert(next.remove(at: i), at: j)
        items = next
    }

    private func savePins() {
        pins.save(items.filter { pinnedIDs.contains($0.id) }, bookmarks: bookmarks)
    }

    /// Finder-style "name 2.ext" when a file item named `name` is already on the shelf (case-insensitive).
    /// `except`: the item being renamed (a case-only rename keeps its name).
    func uniqueName(_ name: String, except id: UUID? = nil) -> String {
        var used = Set(items.compactMap { item -> String? in
            guard item.id != id, case .file(let url) = item.kind else { return nil }
            return Zipper.key(url.lastPathComponent)
        })
        return Zipper.uniqueName(name, used: &used)
    }

    /// A cached file can be renamed in place unless a Recent entry still points into its cache dir.
    func canRenameInPlace(_ item: ShelfItem) -> Bool {
        guard let dir = cacheDir(of: item) else { return false }
        return !recent.flatMap(\.items).compactMap(cacheDir(of:)).contains(dir)
    }

    // MARK: Recent (T-17)

    /// Records one successful drag out; the oldest entry beyond `recentLimit` falls off with its cache dirs.
    func recordDragOut(_ batch: [ShelfItem], at date: Date = .now) {
        guard !batch.isEmpty else { return }
        recent.insert(RecentEntry(date: date, items: batch), at: 0)
        if recent.count > Self.recentLimit { release(recent.removeLast().items) }
    }

    /// Puts an entry's present items back (normal dedupe) and drops the entry. Missing files are skipped.
    func restore(_ id: RecentEntry.ID) {
        guard let i = recent.firstIndex(where: { $0.id == id }) else { return }
        let entry = recent[i]
        entry.items.filter(Self.exists).forEach { add($0) }
        recent.remove(at: i)
        release(entry.items)
    }

    /// Cmd-Z: restores the newest entry; false when Recent is empty.
    @discardableResult
    func undoDragOut() -> Bool {
        guard let newest = recent.first else { return false }
        restore(newest.id)
        return true
    }

    func clearRecent() {
        let gone = recent.flatMap(\.items)
        recent.removeAll()
        release(gone)
    }

    // MARK: Search and filter (V2-10)

    enum Filter: String, CaseIterable {
        case all = "All", files = "Files", images = "Images", links = "Links", text = "Text", pinned = "Pinned"
    }

    /// Search field shown in the header (⌘F or the magnifying glass).
    var isSearching = false
    /// Bumped to (re)focus the search field (⌘F while it is already shown).
    var searchFocus = 0
    var query = "" { didSet { pruneSelection() } }
    var filter = Filter.all { didSet { pruneSelection() } }

    /// Folded, trimmed `query`; empty = no text filter.
    private var foldedQuery: String { ShelfItem.fold(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var isFiltering: Bool { filter != .all || !foldedQuery.isEmpty }

    /// What the grid shows and what Drag All, Clear, select-all, arrows, Quick Look and ⌘C act on (AC-3).
    var visibleItems: [ShelfItem] {
        let q = foldedQuery, filter = filter
        guard filter != .all || !q.isEmpty else { return items }
        return items.filter { item in
            let kindMatches = switch (filter, item.kind) {
            case (.all, _): true
            case (.files, .file): !item.isImage
            case (.images, .file): item.isImage
            case (.links, .url), (.text, .text): true
            case (.pinned, _): pinnedIDs.contains(item.id)
            default: false
            }
            return kindMatches && (q.isEmpty || item.searchKey.contains(q))
        }
    }

    /// Hide: back to all items, field hidden (AC-4). Esc in or after the field does the same (AC-1).
    func resetSearch() {
        isSearching = false
        query = ""
        filter = .all
    }

    /// Tiles a search or filter hides leave the selection.
    private func pruneSelection() {
        guard !selection.isEmpty, isFiltering else { return }
        let visible = Set(visibleItems.map(\.id))
        if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
    }

    /// Selected items the user can see: a new hidden item (an action output) may be in `selection`.
    var selectedItems: [ShelfItem] { visibleItems.filter { selection.contains($0.id) } }
    var selectedIDs: Set<UUID> { Set(selectedItems.map(\.id)) }

    /// ⌘A: selects every visible item.
    func selectAll() { selection = Set(visibleItems.map(\.id)) }

    /// Finder-style click: plain selects one, Cmd toggles, Shift selects the range from the anchor.
    func select(_ id: UUID, command: Bool, shift: Bool) {
        let items = visibleItems
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
        let items = visibleItems
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
        selection.contains(id) ? selectedIDs : [id]
    }

    /// Dragging a selected tile drags the whole selection; an unselected tile drags alone; `nil` = all visible.
    /// Missing files never drag.
    func dragItems(for id: UUID?) -> [ShelfItem] {
        let ids = id.map(targetIDs(for:))
        return visibleItems.filter { (ids?.contains($0.id) ?? true) && !missing(id: $0.id) }
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
        let gone = Set(items.filter { !Self.exists($0) }.map(\.id))
        if gone != missingIDs { missingIDs = gone }
    }

    /// False for a file item whose file is gone; links and text always exist.
    static func exists(_ item: ShelfItem) -> Bool {
        guard case .file(let url) = item.kind else { return true }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// T-21: frees cache dirs nothing references (shelf items, Recent). Expires Recent entries older than 24 h,
    /// then evicts the oldest Recent entries while the cache is over 1 GB. Listing and deleting run off the main actor.
    /// Dirs changed < `sweepGrace` ago are skipped, and a `clear()` during the scan aborts the pass.
    func sweep(now: Date = .now) async {
        recent.removeAll { now.timeIntervalSince($0.date) > Self.recentMaxAge }
        let gen = generation, cache = cache
        let found = await Task.detached { cache.scan() }.value
        guard !found.isEmpty, gen == generation else { return }
        func orphans() -> [ItemCache.Entry] {
            let kept = Set((items + recent.flatMap(\.items)).compactMap(cacheDir(of:)).map(\.lastPathComponent))
            return found.filter { !kept.contains($0.name) && !inFlight.contains($0.name) && now.timeIntervalSince($0.modified) > Self.sweepGrace }
        }
        var gone = orphans()
        while found.reduce(0, { $0 + $1.bytes }) - gone.reduce(0, { $0 + $1.bytes }) > Self.cacheCapBytes, recent.popLast() != nil {
            gone = orphans()
        }
        let doomed = gone.map { cache.root.appendingPathComponent($0.name, isDirectory: true) }
        await Task.detached { doomed.forEach(cache.remove(dir:)) }.value
        log.debug("cache sweep freed \(gone.reduce(0) { $0 + $1.bytes }) bytes")
    }

    /// Keeps pinned items, Recent, and the cache dirs Recent still references (T-17 AC-5, V2-08).
    func clear() {
        generation += 1
        actions.cancel()
        resizing = nil
        cache.wipe(keeping: Set(recent.flatMap(\.items).compactMap(cacheDir(of:)).map(\.lastPathComponent)))
        items.removeAll { !pinnedIDs.contains($0.id) }
        keys = keys.filter { pinnedIDs.contains($0.value) }
        selection.removeAll()
        missingIDs.formIntersection(pinnedIDs)
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

    /// Direct child of the cache root that holds a cached item's file (handles nested files).
    private func cacheDir(of item: ShelfItem) -> URL? {
        guard item.isCached, case .file(let url) = item.kind else { return nil }
        let root = cache.root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parts.count > root.count + 1, Array(parts.prefix(root.count)) == root else { return nil }
        return cache.root.appendingPathComponent(parts[root.count], isDirectory: true)
    }

    /// Deletes the cache dirs of `gone` that no shelf item or Recent entry still uses.
    private func release(_ gone: [ShelfItem]) {
        let used = Set((items + recent.flatMap(\.items)).compactMap(cacheDir(of:)))
        Set(gone.compactMap(cacheDir(of:))).subtracting(used).forEach(cache.remove(dir:))
    }
}
