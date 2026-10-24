import Foundation
import Testing
@testable import DragShelf

/// A store whose cache and Pinned roots are separate temp dirs (like ~/Library/Caches vs Application Support).
private struct Env {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("PinTests-\(UUID().uuidString)", isDirectory: true)
    var cache: ItemCache { ItemCache(root: base.appendingPathComponent("Caches/Shelf", isDirectory: true)) }
    var pins: PinStore { PinStore(root: base.appendingPathComponent("AppSupport/Pinned", isDirectory: true)) }
    func store() -> ShelfStore { ShelfStore(cache: cache, pins: pins) }
    /// A new store from the manifest only: what a relaunch sees (after the launch wipe).
    func relaunch() -> ShelfStore {
        let s = store()
        s.cache.wipe()
        s.loadPins()
        return s
    }
    func file(_ name: String, _ text: String = "hello") throws -> URL {
        let dir = base.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
    func cached(_ store: ShelfStore, _ name: String = "Image.png") throws -> ShelfItem {
        let url = try store.cache.newItemDir().appendingPathComponent(name)
        try Data("png".utf8).write(to: url)
        return ShelfItem(kind: .file(url), isCached: true)
    }
    func cleanup() { try? FileManager.default.removeItem(at: base) }
}

private func path(_ item: ShelfItem) -> String? {
    if case .file(let url) = item.kind { url.path } else { nil }
}
private func exists(_ path: String?) -> Bool { path.map(FileManager.default.fileExists(atPath:)) ?? false }

@Test func pinMovesFirstAndUnpinMovesAfterPinnedGroup() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let a = ShelfItem(kind: .text("a")), b = ShelfItem(kind: .text("b")), c = ShelfItem(kind: .url(URL(string: "https://c.example")!))
    [a, b, c].forEach { store.add($0) }
    store.pin([c])
    store.pin([b])
    #expect(store.items.map(\.id) == [c.id, b.id, a.id])
    #expect(store.isPinned(c.id) && store.isPinned(b.id) && !store.isPinned(a.id))
    store.unpin([c.id])
    #expect(store.items.map(\.id) == [b.id, c.id, a.id] && !store.isPinned(c.id))
}

@Test func pinnedSurvivesClearRemoveAndDragOut() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let original = ShelfItem(kind: .file(try env.file("doc.txt")))
    let image = try env.cached(store), other = ShelfItem(kind: .text("loose"))
    [original, image, other].forEach { store.add($0) }
    store.pin([original, image])
    store.remove(ids: [original.id])
    // A move removes the dragged batch whatever the settings say: pinned ones stay.
    DragOutSource(store: store, items: store.items).ended(operation: .move)
    #expect(store.items.map(\.id) == [original.id, image.id])
    store.add(other)
    store.clear()
    #expect(store.items.map(\.id) == [original.id, image.id])
    #expect(store.items.allSatisfy { exists(path($0)) })
    // Dedupe keys still hold the pinned items.
    #expect(!store.add(ShelfItem(kind: .file(try env.file("doc.txt")))))
}

@Test func pinnedFilesNeverMoveOnDragOut() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let item = ShelfItem(kind: .file(try env.file("a.txt"))), loose = ShelfItem(kind: .file(try env.file("b.txt")))
    store.add(item); store.add(loose)
    #expect(DragOutSource(store: store, items: [item, loose]).canMove)
    store.pin([item])
    #expect(!DragOutSource(store: store, items: [item, loose]).canMove)
    #expect(DragOutSource(store: store, items: [loose]).canMove)
}

@Test func cachedItemIsStoredOutsideCacheAndSurvivesWipeAndSweep() async throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let image = try env.cached(store)
    store.add(image)
    store.pin([image])
    let stored = try #require(path(store.items[0]))
    #expect(stored.hasPrefix(env.pins.root.path) && !exists(path(image)))  // cache dir released, copy in Pinned
    await store.sweep(now: .now.addingTimeInterval(3600))
    store.clear()
    store.cache.wipe()
    #expect(exists(stored))
}

@Test func survivesRelaunch() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let original = ShelfItem(kind: .file(try env.file("doc.txt")))
    let image = try env.cached(store), text = ShelfItem(kind: .text("Grüße ✓\nline 2"))
    let link = ShelfItem(kind: .url(URL(string: "https://example.com/a?b=c")!)), loose = ShelfItem(kind: .text("loose"))
    [original, image, text, link, loose].forEach { store.add($0) }
    store.pin([original, image, text, link])
    let before = store.items.filter { store.isPinned($0.id) }

    let next = env.relaunch()
    #expect(next.items == before)
    #expect(next.items.allSatisfy { next.isPinned($0.id) })
    #expect(next.items.allSatisfy(ShelfStore.exists))
    #expect(!next.add(ShelfItem(kind: .text("Grüße ✓\nline 2"))))
}

@Test func bookmarkFollowsMovedOriginal() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let url = try env.file("before.txt", "keep me")
    let item = ShelfItem(kind: .file(url))
    store.add(item)
    store.pin([item])
    let moved = url.deletingLastPathComponent().appendingPathComponent("after.txt")
    try FileManager.default.moveItem(at: url, to: moved)

    let next = env.relaunch()
    #expect(path(next.items[0]).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() } == moved.resolvingSymlinksInPath())
    // Refreshed: a second relaunch still finds it.
    #expect(path(env.relaunch().items[0]).map { URL(fileURLWithPath: $0).lastPathComponent } == "after.txt")
}

@Test func unresolvableOriginalStaysListedAsMissing() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let url = try env.file("gone.txt")
    let item = ShelfItem(kind: .file(url))
    store.add(item)
    store.pin([item])
    try FileManager.default.removeItem(at: url)

    let next = env.relaunch()
    next.refreshMissing()
    #expect(next.items.map(\.id) == [item.id] && next.missing(id: item.id) && next.isPinned(item.id))
    next.unpin([item.id])
    next.remove(ids: [item.id])
    #expect(next.items.isEmpty && env.relaunch().items.isEmpty)
}

@Test func unpinFreesStoredCopy() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let image = try env.cached(store)
    store.add(image)
    store.pin([image])
    let stored = try #require(path(store.items[0]))
    store.unpin([image.id])
    // The copy left the Pinned folder; the item still works from the cache until removed.
    #expect(!exists(stored) && exists(path(store.items[0])))
    #expect(path(store.items[0])?.hasPrefix(store.cache.root.path) == true)
    store.remove(ids: [image.id])
    let left = (try? FileManager.default.contentsOfDirectory(atPath: env.pins.root.path)) ?? []
    #expect(left == ["pinned.json"])
    #expect(env.relaunch().items.isEmpty)
}

@Test func corruptManifestIsBackedUpAndStartsEmpty() throws {
    let env = Env(); defer { env.cleanup() }
    try FileManager.default.createDirectory(at: env.pins.root, withIntermediateDirectories: true)
    for bad in ["{not json", #"{"version":2,"items":[]}"#,
                #"{"version":1,"items":[{"id":"\#(UUID())","item":{"copy":{"_0":"../../etc/passwd"}}}]}"#] {
        try Data(bad.utf8).write(to: env.pins.manifest)
        let store = env.relaunch()
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.pins.manifest.path))
        #expect(try String(contentsOf: env.pins.backup, encoding: .utf8) == bad)
    }
}

@Test func renamedPinnedCopyIsStoredAgain() throws {
    let env = Env(); defer { env.cleanup() }
    let store = env.store()
    let image = try env.cached(store)
    store.add(image)
    store.pin([image])
    let oldStored = try #require(path(store.items[0]))
    // Rename clones into a new cache dir and replaces the item (V2-04).
    let clone = ShelfItem(id: image.id, kind: .file(try env.cached(store, "Renamed.png").kind.url!), isCached: true)
    #expect(store.replace(id: image.id, with: clone))
    let stored = try #require(path(store.items[0]))
    #expect(stored.hasPrefix(env.pins.root.path) && stored.hasSuffix("Renamed.png") && exists(stored))
    #expect(!exists(oldStored) && !exists(path(clone)) && store.isPinned(image.id))
    #expect(path(env.relaunch().items[0]) == stored)
}

private extension ShelfItem.Kind {
    var url: URL? { if case .file(let url) = self { url } else { nil } }
}
