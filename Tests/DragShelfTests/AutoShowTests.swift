import AppKit
import Testing
@testable import DragShelf

@Test func dragStartNeedsPasteboardWriteAndDistance() {
    let o = NSPoint(x: 100, y: 100)
    #expect(DragMonitor.isDragStart(downCount: 1, currentCount: 2, from: o, to: NSPoint(x: 110, y: 100)))
    #expect(DragMonitor.isDragStart(downCount: 1, currentCount: 2, from: o, to: NSPoint(x: 92, y: 106)))
    // Window move/resize or selection rectangle: pasteboard untouched.
    #expect(!DragMonitor.isDragStart(downCount: 5, currentCount: 5, from: o, to: NSPoint(x: 400, y: 400)))
    // Pasteboard written but cursor barely moved.
    #expect(!DragMonitor.isDragStart(downCount: 1, currentCount: 2, from: o, to: NSPoint(x: 105, y: 105)))
}

@Test func autoHideDecisionTable() {
    typealias C = ShelfPanelController
    #expect(C.shouldAutoHide(reason: .autoDrag, droppedOnShelf: false, isEmpty: true, dragActive: false))
    #expect(!C.shouldAutoHide(reason: .autoDrag, droppedOnShelf: true, isEmpty: true, dragActive: false))
    #expect(!C.shouldAutoHide(reason: .autoDrag, droppedOnShelf: false, isEmpty: false, dragActive: false))
    #expect(!C.shouldAutoHide(reason: .autoDrag, droppedOnShelf: false, isEmpty: true, dragActive: true))
    #expect(!C.shouldAutoHide(reason: .manual, droppedOnShelf: false, isEmpty: true, dragActive: false))
    #expect(!C.shouldAutoHide(reason: nil, droppedOnShelf: false, isEmpty: true, dragActive: false))
}

@Test(arguments: [
    NSRect(x: 0, y: 0, width: 1512, height: 944),        // laptop, menu bar removed
    NSRect(x: -1920, y: 200, width: 1920, height: 1055), // display left of main
    NSRect(x: 1512, y: -1080, width: 2560, height: 1415), // display below-right
])
func topCenterFrame(visible: NSRect) {
    let size = NSSize(width: 288, height: 160)
    let f = ShelfPanelController.topCenterFrame(size: size, in: visible)
    #expect(f.size == size)
    #expect(abs(f.midX - visible.midX) <= 0.5)
    #expect(f.maxY == visible.maxY - 12)
    #expect(visible.contains(f))
}
