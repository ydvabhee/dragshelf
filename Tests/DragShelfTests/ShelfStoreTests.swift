import CryptoKit
import Foundation
import Testing
@testable import DragShelf

private func tempCache() -> ItemCache {
    ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("DragShelfTests-\(UUID().uuidString)", isDirectory: true))
}

private func cachedItem(_ cache: ItemCache, hash: SHA256.Digest? = nil) throws -> ShelfItem {
    let file = try cache.newItemDir().appendingPathComponent("a.txt")
    try Data("x".utf8).write(to: file)
    return ShelfItem(kind: .file(file), isCached: true, contentHash: hash)
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

@Test func dedupeNormalizesFilePaths() {
    let store = ShelfStore(cache: tempCache())
    store.add(ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/x"))))
    store.add(ShelfItem(kind: .file(URL(fileURLWithPath: "/private/tmp/x"))))
    store.add(ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/a/../x"))))
    #expect(store.items.count == 1)
}

@Test func removeNestedCachedFileDeletesItemDir() throws {
    let cache = tempCache()
    defer { cache.wipe(); cache.remove(dir: cache.root) }
    let store = ShelfStore(cache: cache)
    let dir = try cache.newItemDir()
    let sub = dir.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let file = sub.appendingPathComponent("f")
    try Data("x".utf8).write(to: file)
    let item = ShelfItem(kind: .file(file), isCached: true)
    store.add(item)
    store.remove(ids: [item.id])
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

@Test func sameImageHashReplacesOldItemAndCacheDir() throws {
    let cache = tempCache()
    defer { cache.wipe(); cache.remove(dir: cache.root) }
    let store = ShelfStore(cache: cache)
    let hash = SHA256.hash(data: Data("png".utf8))
    let first = try cachedItem(cache, hash: hash)
    let other = ShelfItem(kind: .text("t"))
    store.add(first); store.add(other)
    store.selection = [first.id]
    let second = try cachedItem(cache, hash: hash)
    #expect(store.add(second))
    #expect(store.items == [other, second])
    #expect(store.selection.isEmpty)
    guard case .file(let old) = first.kind, case .file(let new) = second.kind else { return }
    #expect(!FileManager.default.fileExists(atPath: old.deletingLastPathComponent().path))
    #expect(FileManager.default.fileExists(atPath: new.path))
    // Different content is a separate item.
    #expect(store.add(try cachedItem(cache, hash: SHA256.hash(data: Data("other".utf8)))))
    #expect(store.items.count == 3)
}

@Test func missingFilesDetectedAndNeverDraggedOrPreviewed() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfMissing-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let present = dir.appendingPathComponent("a.txt"), gone = dir.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: present)
    try Data("b".utf8).write(to: gone)
    let store = ShelfStore(cache: tempCache())
    let a = ShelfItem(kind: .file(present)), b = ShelfItem(kind: .file(gone)), t = ShelfItem(kind: .text("t"))
    [a, b, t].forEach { store.add($0) }
    store.refreshMissing()
    #expect(store.missingIDs.isEmpty)
    try FileManager.default.removeItem(at: gone)
    store.refreshMissing()
    #expect(store.missingIDs == [b.id])
    #expect(store.dragItems(for: nil).map(\.id) == [a.id, t.id])
    store.selection = [a.id, b.id, t.id]
    #expect(store.dragItems(for: b.id).map(\.id) == [a.id, t.id])
    #expect(store.previewURLs == [present])
    store.selection = [b.id]
    #expect(store.dragItems(for: b.id).isEmpty && store.previewURLs.isEmpty)
    // Restored file is no longer missing at the next show.
    try Data("b".utf8).write(to: gone)
    store.refreshMissing()
    #expect(!store.missing(id: b.id))
}

@Test func arrowKeysMoveSelectionInGrid() {
    let store = ShelfStore(cache: tempCache())
    let ids = (0..<5).map { i in let item = ShelfItem(kind: .text("\(i)")); store.add(item); return item.id }
    store.moveSelection(by: 1)
    #expect(store.selection == [ids[0]])  // none selected → first
    store.moveSelection(by: -1)
    #expect(store.selection == [ids[0]])  // off the grid → ignored
    store.moveSelection(by: 1)
    store.moveSelection(by: 1)
    #expect(store.selection == [ids[2]])
    store.moveSelection(by: 3)
    #expect(store.selection == [ids[4]])  // down onto shorter last row → last item
    store.moveSelection(by: 3)
    #expect(store.selection == [ids[4]])
    store.moveSelection(by: -3)
    #expect(store.selection == [ids[1]])
    store.selection = [ids[0], ids[3]]
    store.moveSelection(by: 1)
    #expect(store.selection == [ids[4]])  // from the last selected when the anchor is not selected
}
