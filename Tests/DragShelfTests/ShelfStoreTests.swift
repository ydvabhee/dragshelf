import Foundation
import Testing
@testable import DragShelf

private func tempCache() -> ItemCache {
    ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("DragShelfTests-\(UUID().uuidString)", isDirectory: true))
}

private func cachedItem(_ cache: ItemCache) throws -> ShelfItem {
    let file = try cache.newItemDir().appendingPathComponent("a.txt")
    try Data("x".utf8).write(to: file)
    return ShelfItem(kind: .file(file), isCached: true)
}

@Test func addKeepsOrderAndDedupes() {
    let store = ShelfStore(cache: tempCache())
    let f = URL(fileURLWithPath: "/tmp/a.txt")
    let u = URL(string: "https://example.com")!
    store.add(ShelfItem(kind: .file(f)))
    store.add(ShelfItem(kind: .url(u)))
    store.add(ShelfItem(kind: .text("hi")))
    #expect(!store.add(ShelfItem(kind: .file(f))))
    store.add(ShelfItem(kind: .url(u)))
    store.add(ShelfItem(kind: .text("hi")))
    store.add(ShelfItem(kind: .text("Hi")))
    #expect(store.items.map(\.kind) == [.file(f), .url(u), .text("hi"), .text("Hi")])
}

@Test func removeAndClearUpdateSelectionAndCache() throws {
    let cache = tempCache()
    defer { cache.wipe(); cache.remove(dir: cache.root) }
    let store = ShelfStore(cache: cache)
    let cached = try cachedItem(cache)
    let plain = ShelfItem(kind: .text("t"))
    store.add(cached); store.add(plain)
    store.selection = [cached.id, plain.id]
    guard case .file(let url) = cached.kind else { return }
    store.remove(ids: [cached.id])
    #expect(store.items == [plain])
    #expect(store.selection == [plain.id])
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

    let again = try cachedItem(cache)
    store.add(again)
    store.clear()
    #expect(store.items.isEmpty && store.selection.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: cache.root.path).isEmpty)
}
