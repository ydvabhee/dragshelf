import AppKit
import SwiftUI
import Testing
@testable import DragShelf

private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let pb: NSPasteboard
    init(_ pb: NSPasteboard) { self.pb = pb }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var source: Any?
    var draggingSource: Any? { source }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@Test func performDragOperationAddsFilesAndText() async {
    let pb = NSPasteboard(name: .init("test-drop-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    let a = URL(fileURLWithPath: "/tmp/a.txt"), b = URL(fileURLWithPath: "/tmp/b.txt")
    pb.writeObjects([a as NSURL, b as NSURL, "hello" as NSString])
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())")))
    let receiver = DropReceiver(rootView: EmptyView())
    receiver.store = store
    let info = FakeDraggingInfo(pb)
    #expect(receiver.draggingEntered(info) == .copy)
    #expect(store.isDropTargeted)
    #expect(receiver.performDragOperation(info))
    #expect(!store.isDropTargeted)
    await pendingIngest?.value  // queued behind a concurrent test's image drop, if any
    #expect(store.items.map(\.kind) == [.file(a), .file(b), .text("hello")])
}

@Test func duplicateOnlyDropLeavesRecentView() async {
    let pb = NSPasteboard(name: .init("test-drop-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: "/tmp/dup.txt") as NSURL])
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())")))
    let receiver = DropReceiver(rootView: EmptyView())
    receiver.store = store
    let info = FakeDraggingInfo(pb)
    _ = receiver.performDragOperation(info)
    await pendingIngest?.value
    store.showRecent = true
    _ = receiver.performDragOperation(info)
    #expect(!store.showRecent)
}

@Test func finishPromiseAddsCachedFile() throws {
    let cache = ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())"))
    let store = ShelfStore(cache: cache)
    let dir = try cache.newItemDir()
    let file = dir.appendingPathComponent("a.pdf")
    try Data("x".utf8).write(to: file)
    #expect(DropReceiver<EmptyView>.finishPromise(url: file, dir: dir, store: store, generation: store.generation))
    #expect(store.items.count == 1)
    #expect(store.items[0].kind == .file(file))
    #expect(store.items[0].isCached)
    cache.wipe()
}

@Test func finishPromiseFailureLeavesNoDir() throws {
    let cache = ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())"))
    let store = ShelfStore(cache: cache)
    let dir = try cache.newItemDir()
    #expect(!DropReceiver<EmptyView>.finishPromise(url: nil, error: CocoaError(.fileReadUnknown), dir: dir, store: store, generation: 0))
    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
    cache.wipe()
}

@Test func draggingUpdatedRejectsUnacceptableDrag() {
    let pb = NSPasteboard(name: .init("test-drop-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    let receiver = DropReceiver(rootView: EmptyView())
    let info = FakeDraggingInfo(pb)
    #expect(receiver.draggingEntered(info) == [])
    #expect(receiver.draggingUpdated(info) == [])
    pb.writeObjects(["hi" as NSString])
    #expect(receiver.draggingUpdated(info) == .copy)
}

@Test func ownDragOutIsRejected() {
    let pb = NSPasteboard(name: .init("test-drop-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.writeObjects(["hi" as NSString])
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())")))
    let receiver = DropReceiver(rootView: EmptyView())
    receiver.store = store
    let info = FakeDraggingInfo(pb)
    info.source = DragOutSource(store: store, items: [])
    #expect(receiver.draggingEntered(info) == [])
    #expect(!store.isDropTargeted)
    #expect(!receiver.performDragOperation(info))
    #expect(store.items.isEmpty)
}

@Test func promiseFinishingAfterClearAddsNothingAndLeavesNoFile() throws {
    let cache = ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())"))
    defer { cache.remove(dir: cache.root) }
    let store = ShelfStore(cache: cache)
    let generation = store.generation
    let dir = try cache.newItemDir()
    store.clear()
    // The promise writes its file after Clear (recreating the wiped dir), then completes.
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("late.pdf")
    try Data("x".utf8).write(to: file)
    #expect(!DropReceiver<EmptyView>.finishPromise(url: file, dir: dir, store: store, generation: generation))
    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

/// AppKit calls the promise reader on a background queue; a MainActor-isolated reader traps there.
@Test func promiseHandlerCalledOffMainAddsItem() async throws {
    let cache = ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())"))
    defer { cache.wipe() }
    let store = ShelfStore(cache: cache)
    let dir = try cache.newItemDir()
    let file = dir.appendingPathComponent("image.png")
    try Data("x".utf8).write(to: file)
    let handler = DropReceiver<EmptyView>.promiseHandler(dir: dir, store: store, generation: store.generation) {}
    OperationQueue().addOperation { handler(file, nil) }
    for _ in 0..<200 where store.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(store.items.map(\.kind) == [.file(file)])
}

@Test func promiseHandlerErrorOffMainCallsOnFailAndRemovesDir() async throws {
    let cache = ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("drt-\(UUID())"))
    defer { cache.wipe() }
    let store = ShelfStore(cache: cache)
    let dir = try cache.newItemDir()
    await confirmation { failed in
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let handler = DropReceiver<EmptyView>.promiseHandler(dir: dir, store: store, generation: store.generation) {
                failed()
                done.resume()
            }
            DispatchQueue.global().async { handler(dir.appendingPathComponent("gone"), CocoaError(.fileReadUnknown)) }
        }
    }
    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}
