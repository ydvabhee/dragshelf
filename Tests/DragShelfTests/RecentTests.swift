import Foundation
import Testing
@testable import DragShelf

private func tempStore() -> ShelfStore {
    ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("RecentTests-\(UUID().uuidString)", isDirectory: true)))
}

private func cachedItem(_ store: ShelfStore) throws -> (item: ShelfItem, dir: URL) {
    let dir = try store.cache.newItemDir()
    let file = dir.appendingPathComponent("img.png")
    try Data("x".utf8).write(to: file)
    return (ShelfItem(kind: .file(file), isCached: true), dir)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

@Test func dragOutRecordsOneEntryPerBatch() {
    let store = tempStore()
    let batch = (0..<30).map { ShelfItem(kind: .text("\($0)")) }
    batch.forEach { store.add($0) }
    DragOutSource(store: store, items: batch).ended(operation: [])
    #expect(store.recent.isEmpty) // cancelled
    DragOutSource(store: store, items: batch).ended(operation: .copy)
    #expect(store.recent.count == 1 && store.recent[0].items == batch)
    #expect(store.items.isEmpty)
    // Dragging a Recent row out again keeps its entry as is.
    DragOutSource(store: store, items: batch, fromRecent: true).ended(operation: .copy)
    #expect(store.recent.count == 1)
}

@Test func recentKeepsLastFiveNewestFirst() {
    let store = tempStore()
    for i in 0..<7 { store.recordDragOut([ShelfItem(kind: .text("\(i)"))]) }
    #expect(store.recent.map { $0.items[0].kind } == (2..<7).reversed().map { .text("\($0)") })
    store.recordDragOut([])
    #expect(store.recent.count == ShelfStore.recentLimit)
}

@Test func undoWalksBackNewestFirst() {
    let store = tempStore()
    let a = ShelfItem(kind: .text("a")), b = ShelfItem(kind: .text("b"))
    store.recordDragOut([a]); store.recordDragOut([b])
    #expect(store.undoDragOut())
    #expect(store.items == [b] && store.recent.count == 1)
    #expect(store.undoDragOut())
    #expect(store.items == [b, a] && store.recent.isEmpty)
    #expect(!store.undoDragOut())
}

@Test func restoreDedupesAndSkipsMissing() {
    let store = tempStore()
    let onShelf = ShelfItem(kind: .text("same"))
    store.add(onShelf)
    let gone = ShelfItem(kind: .file(URL(fileURLWithPath: "/nonexistent-\(UUID())/x.txt")))
    let link = ShelfItem(kind: .url(URL(string: "https://example.com")!))
    store.recordDragOut([ShelfItem(kind: .text("same")), gone, link])
    store.restore(store.recent[0].id)
    #expect(store.items == [onShelf, link])
    #expect(store.recent.isEmpty)
}

@Test func recentCacheDirLifetime() throws {
    let store = tempStore()
    defer { store.cache.remove(dir: store.cache.root) }
    let (a, dirA) = try cachedItem(store)
    store.add(a)
    DragOutSource(store: store, items: [a]).ended(operation: .copy)
    #expect(store.items.isEmpty && exists(dirA))

    // Clear shelf keeps Recent and its dirs; unreferenced dirs go.
    let (b, dirB) = try cachedItem(store)
    store.add(b)
    store.clear()
    #expect(exists(dirA) && !exists(dirB) && store.recent.count == 1)

    // Restore hands the dir back to the shelf; removing it from the shelf then deletes it.
    store.undoDragOut()
    #expect(store.items == [a] && exists(dirA))
    // Keep-after-drag case: on the shelf and in Recent; a shelf remove keeps the dir.
    store.recordDragOut([a])
    store.remove(ids: [a.id])
    #expect(exists(dirA))
    store.clearRecent()
    #expect(!exists(dirA))

    // Falling off the end deletes the dir.
    let (c, dirC) = try cachedItem(store)
    store.recordDragOut([c])
    for i in 0..<ShelfStore.recentLimit - 1 { store.recordDragOut([ShelfItem(kind: .text("\(i)"))]) }
    #expect(exists(dirC))
    store.recordDragOut([ShelfItem(kind: .text("last"))])
    #expect(!exists(dirC))
}

@Test func recentRowText() {
    let f = ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/photo.heic")))
    #expect(RecentList.title([f]) == "photo.heic")
    #expect(RecentList.title([f, f, f]) == "3 files")
    #expect(RecentList.title([f, ShelfItem(kind: .text("t"))]) == "2 items")
    let now = Date()
    #expect(RecentList.age(now.addingTimeInterval(-10), now: now) == "just now")
    #expect(RecentList.age(now.addingTimeInterval(-120), now: now, style: .full).contains("2 minutes"))
}
