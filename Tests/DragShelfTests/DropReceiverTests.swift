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
    var draggingSource: Any? { nil }
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

@Test func performDragOperationAddsFilesAndText() {
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
    #expect(store.items.map(\.kind) == [.file(a), .file(b), .text("hello")])
}
