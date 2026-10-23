import Foundation
import SwiftUI
import Testing
@testable import DragShelf

private func tempStore() -> ShelfStore {
    ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("SweepTests-\(UUID().uuidString)", isDirectory: true)))
}

private func cached(_ store: ShelfStore, bytes: Int = 1) throws -> (item: ShelfItem, dir: URL) {
    let dir = try store.cache.newItemDir()
    let file = dir.appendingPathComponent("f.bin")
    try Data(count: bytes).write(to: file)
    return (ShelfItem(kind: .file(file), isCached: true), dir)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
/// A clock past the in-flight grace, so fresh test dirs count as settled.
private func later(_ s: TimeInterval = 60) -> Date { .now.addingTimeInterval(s) }

@Test func sweepRemovesOrphanKeepsShelfAndRecent() async throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let orphan = try cached(store), onShelf = try cached(store), inRecent = try cached(store)
    store.add(onShelf.item)
    store.recordDragOut([inRecent.item])
    await store.sweep(now: later())
    #expect(!exists(orphan.dir) && exists(onShelf.dir) && exists(inRecent.dir))
}

@Test func sweepSkipsDirsYoungerThanGrace() async throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let fresh = try cached(store)
    await store.sweep() // real clock: just created = maybe an in-flight drop
    #expect(exists(fresh.dir))
}

@Test func sizeCapEvictsOldestRecentFirstNeverShelf() async throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let per = ShelfStore.cacheCapBytes / 2 + 1
    let shelf = try cached(store, bytes: 1), old = try cached(store, bytes: per), new = try cached(store, bytes: per)
    store.add(shelf.item)
    store.recordDragOut([old.item]); store.recordDragOut([new.item])
    await store.sweep(now: later())
    #expect(!exists(old.dir) && exists(new.dir) && exists(shelf.dir) && store.recent.count == 1)
}

@Test func recentOlderThan24hExpires() async throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let stale = try cached(store), fresh = try cached(store)
    store.recordDragOut([stale.item], at: .now.addingTimeInterval(-25 * 3600))
    store.recordDragOut([fresh.item], at: .now)
    await store.sweep(now: later())
    #expect(!exists(stale.dir) && exists(fresh.dir) && store.recent.count == 1)
}

@Test func sweepOnEmptyCacheIsNoOp() async {
    let store = tempStore()
    await store.sweep(now: later())
    #expect(!exists(store.cache.root))
}

@Test func inFlightDirIsNotSweptUntilFinished() async throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let slow = try store.cache.newItemDir() // empty, like a promise still receiving
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: slow.path)
    store.beginInFlight(slow)
    await store.sweep(now: later())
    #expect(exists(slow))
    // Failure path: finishPromise ends the in-flight mark and removes the dir.
    #expect(!DropReceiver<EmptyView>.finishPromise(url: nil, dir: slow, store: store, generation: store.generation))
    #expect(!exists(slow) && store.inFlight.isEmpty)
    // Dir left behind after the mark ends is swept as an orphan.
    let late = try store.cache.newItemDir()
    store.beginInFlight(late); store.endInFlight(late)
    await store.sweep(now: later())
    #expect(!exists(late))
}
