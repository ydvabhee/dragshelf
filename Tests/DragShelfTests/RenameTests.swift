import Foundation
import Testing
@testable import DragShelf

private let fm = FileManager.default

private func tempDir(_ name: String) throws -> URL {
    let dir = fm.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func tempStore() throws -> ShelfStore {
    ShelfStore(cache: ItemCache(root: try tempDir("RenameTests-cache")))
}

private func rm(_ urls: URL...) { urls.forEach { try? fm.removeItem(at: $0) } }

private func url(_ item: ShelfItem?) -> URL? {
    if case .file(let url) = item?.kind { url } else { nil }
}

/// Original file `photo.jpg` with known bytes, on the shelf between two others; selected.
private func originalOnShelf() throws -> (store: ShelfStore, src: URL, item: ShelfItem, bytes: Data) {
    let store = try tempStore(), dir = try tempDir("RenameTests-src")
    let src = dir.appendingPathComponent("photo.jpg"), bytes = Data((0..<2048).map { UInt8($0 % 253) })
    try bytes.write(to: src)
    let item = ShelfItem(kind: .file(src))
    store.add(ShelfItem(kind: .text("before")))
    store.add(item)
    store.add(ShelfItem(kind: .url(URL(string: "https://example.com")!)))
    store.selection = [item.id]
    return (store, src, item, bytes)
}

/// Cached file in its own item dir, on the shelf.
private func cachedOnShelf(_ store: ShelfStore, name: String = "image.png") throws -> ShelfItem {
    let file = try store.cache.newItemDir().appendingPathComponent(name)
    try Data("cached".utf8).write(to: file)
    let item = ShelfItem(kind: .file(file), isCached: true)
    store.add(item)
    return item
}

@Test func validateRejectsBadNamesAcceptsUnicode() {
    for bad in ["", "   ", "a/b", "a:b", ".hidden", String(repeating: "é", count: 128)] { // é = 2 UTF-8 bytes
        #expect(Renamer.validate(bad) != nil, "\(bad)")
    }
    for good in ["Résumé 2024 ✓.pdf", "my file", "日本語.txt", String(repeating: "a", count: 255)] {
        #expect(Renamer.validate(good) == nil, "\(good)")
    }
}

@Test func fileNameKeepsExtensionUnlessTypedAndSelectsBase() {
    #expect(Renamer.fileName(" new ", replacing: "photo.jpg", isFolder: false) == "new.jpg")
    #expect(Renamer.fileName("new.png", replacing: "photo.jpg", isFolder: false) == "new.png")
    #expect(Renamer.fileName("New", replacing: "v1.2", isFolder: true) == "New")
    #expect(Renamer.fileName("", replacing: "photo.jpg", isFolder: false) == "")
    #expect(Renamer.baseRange(of: "photo.jpg", isFolder: false) == NSRange(location: 0, length: 5))
    #expect(Renamer.baseRange(of: "v1.2", isFolder: true) == NSRange(location: 0, length: 4))
    #expect(Renamer.baseRange(of: "README", isFolder: false) == NSRange(location: 0, length: 6))
}

@Test func renamingOriginalClonesIntoCacheAndLeavesOriginal() throws {
    let (store, src, item, bytes) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    #expect(store.actions.rename(item, to: "holiday", in: store) == nil)
    // Original untouched: same path, name, bytes (OQ-17).
    #expect(try Data(contentsOf: src) == bytes)
    #expect(try fm.contentsOfDirectory(atPath: src.deletingLastPathComponent().path) == ["photo.jpg"])
    // Same id, index, and selection; new cached clone with the new name and the same bytes.
    let renamed = store.items[1]
    #expect(renamed.id == item.id && renamed.isCached && store.selection == [item.id] && store.items.count == 3)
    let new = try #require(url(renamed))
    #expect(new.lastPathComponent == "holiday.jpg" && new.path.hasPrefix(store.cache.root.path))
    #expect(try Data(contentsOf: new) == bytes)
    // Keys follow: the clone dedupes, the original path no longer does.
    #expect(!store.add(ShelfItem(kind: .file(new))))
    #expect(store.add(ShelfItem(kind: .file(src))))
}

@Test func renamingCachedItemMovesInPlace() throws {
    let store = try tempStore()
    defer { rm(store.cache.root) }
    let item = try cachedOnShelf(store)
    let old = try #require(url(item)), dir = old.deletingLastPathComponent()
    #expect(store.actions.rename(item, to: "Screenshot", in: store) == nil)
    let new = try #require(url(store.items.first))
    #expect(new.deletingLastPathComponent() == dir && new.lastPathComponent == "Screenshot.png")
    #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["Screenshot.png"])
    #expect(try fm.contentsOfDirectory(atPath: store.cache.root.path) == [dir.lastPathComponent])
    #expect(store.items.first?.id == item.id && !store.add(ShelfItem(kind: .file(new), isCached: true)))
    // Case-only rename works on the case-insensitive volume.
    #expect(store.actions.rename(store.items[0], to: "SCREENSHOT", in: store) == nil)
    #expect(url(store.items.first)?.lastPathComponent == "SCREENSHOT.png")
}

@Test func renamingItemInRecentKeepsRecentFile() throws {
    let store = try tempStore()
    defer { rm(store.cache.root) }
    let item = try cachedOnShelf(store)
    let old = try #require(url(item))
    store.recordDragOut([item]) // dragged out, kept on the shelf
    #expect(store.actions.rename(item, to: "kept", in: store) == nil)
    #expect(fm.fileExists(atPath: old.path) && store.recent.first?.items == [item])
    let new = try #require(url(store.items.first))
    #expect(new.lastPathComponent == "kept.png" && new.deletingLastPathComponent() != old.deletingLastPathComponent())
}

@Test func invalidNameRejectedAndOldNameStays() throws {
    let (store, src, item, _) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    store.actions.run(.rename, on: [item], in: store)
    #expect(store.renamingID == item.id)
    for bad in ["a/b", ".x", "  "] {
        #expect(store.actions.rename(item, to: bad, in: store) != nil)
        #expect(store.items[1] == item && store.renamingID == item.id && store.actions.message != nil)
    }
    #expect((try fm.contentsOfDirectory(atPath: store.cache.root.path)).isEmpty)
}

@Test func renameOnlyForOnePresentFile() throws {
    let (store, src, item, _) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    #expect(store.actions.canRun(.rename, on: [item]))
    #expect(!store.actions.canRun(.rename, on: [store.items[0]])) // text
    #expect(!store.actions.canRun(.rename, on: [store.items[2]])) // link
    #expect(!store.actions.canRun(.rename, on: store.items)) // more than one
    rm(src)
    #expect(!store.actions.canRun(.rename, on: [item])) // missing
}

@Test func uniqueNameAddsFinderSuffixOnShelfCollision() throws {
    let store = try tempStore()
    defer { rm(store.cache.root) }
    let a = try cachedOnShelf(store, name: "a.txt"), b = try cachedOnShelf(store, name: "b.txt")
    #expect(store.uniqueName("A.TXT") == "A 2.TXT" && store.uniqueName("c.txt") == "c.txt")
    #expect(store.uniqueName("A.txt", except: a.id) == "A.txt")
    #expect(store.actions.rename(b, to: "a", in: store) == nil)
    #expect(url(store.items[1])?.lastPathComponent == "a 2.txt")
}

@Test func secondArchiveGetsSuffix() async throws {
    let (store, src, item, _) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    let other = src.deletingLastPathComponent().appendingPathComponent("other.txt")
    try Data("o".utf8).write(to: other)
    store.add(ShelfItem(kind: .file(other)))
    let targets = [item, store.items[3]]
    await store.actions.run(.compress, on: targets, in: store)?.value
    await store.actions.run(.compress, on: targets, in: store)?.value
    #expect(store.items.suffix(2).compactMap { url($0)?.lastPathComponent } == ["Archive.zip", "Archive 2.zip"])
    #expect(fm.fileExists(atPath: try #require(url(store.items.last)).path))
}

@Test func crossVolumeRenameRunsAsJob() async throws {
    let (store, src, item, bytes) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    #expect(store.actions.rename(item, to: "slow", in: store, offMain: true) == nil)
    #expect(store.actions.running == .rename && store.inFlight.count == 1)
    while store.actions.running != nil { try await Task.sleep(for: .milliseconds(10)) }
    #expect(url(store.items[1])?.lastPathComponent == "slow.jpg" && store.items[1].id == item.id && store.inFlight.isEmpty)
    #expect(try Data(contentsOf: src) == bytes)

}

@Test func cancelledRenameJobChangesNothing() async throws {
    let (store, src, item, _) = try originalOnShelf()
    defer { rm(src.deletingLastPathComponent(), store.cache.root) }
    store.actions.rename(item, to: "never", in: store, offMain: true)
    store.actions.cancel()
    while store.actions.running != nil { try await Task.sleep(for: .milliseconds(10)) }
    #expect(try store.items[1] == item && fm.contentsOfDirectory(atPath: store.cache.root.path).isEmpty)
    #expect(store.actions.message == nil)
}
