import AppKit
import CryptoKit
import SwiftUI
import Testing
@testable import DragShelf

private let visible = NSRect(x: 0, y: 0, width: 1512, height: 945)

@Test func fitKeepsTopEdgeAndClampsAtScreenBottom() {
    let f = NSRect(x: 600, y: 600, width: 288, height: 160)
    let grown = ShelfPanelController.fit(f, size: NSSize(width: 288, height: 400), in: visible)
    #expect(grown.maxY == f.maxY && grown.height == 400 && grown.minX == f.minX)
    #expect(ShelfPanelController.fit(grown, size: f.size, in: visible) == f)
    // Near the bottom: grows past visible.minY → shifted up, never outside.
    let low = NSRect(x: 600, y: 20, width: 288, height: 160)
    let g = ShelfPanelController.fit(low, size: NSSize(width: 288, height: 400), in: visible)
    #expect(g.minY == visible.minY && g.height == 400)
    // Width change (reset, other screen) keeps the top center.
    let wide = ShelfPanelController.fit(f, size: NSSize(width: 400, height: 160), in: visible)
    #expect(wide.midX == f.midX && wide.maxY == f.maxY)
}

/// T-16 AC-5, AC-6: defaults when never resized; user size is the cap, clamped to min size … visibleFrame.
@Test func sizeLimitsClampToMinAndVisible() {
    let d = ShelfPanelController.limits(saved: nil, in: visible)
    #expect(d.width == ShelfView.defaultWidth && d.maxHeight == min(ShelfView.maxContentHeight, (visible.height / 2).rounded()))
    let user = ShelfPanelController.limits(saved: NSSize(width: 420, height: 700), in: visible)
    #expect(user.width == 420 && user.maxHeight == 700)
    let tiny = ShelfPanelController.limits(saved: NSSize(width: 10, height: 10), in: visible)
    #expect(tiny.width == ShelfView.minSize.width && tiny.maxHeight == ShelfView.minSize.height)
    let huge = ShelfPanelController.limits(saved: NSSize(width: 9000, height: 9000), in: visible)
    #expect(huge.width == visible.width && huge.maxHeight == visible.height)
}

@Test func columnsFollowWidth() {
    #expect(ShelfView.columnCount(width: ShelfView.minSize.width) == 1)
    #expect(ShelfView.columnCount(width: ShelfView.defaultWidth) == 3)
    #expect(ShelfView.columnCount(width: 360) == 3 && ShelfView.columnCount(width: 368) == 4)
    #expect(ShelfView.columnCount(width: 0) == 1)
    #expect(ShelfView.columnCount(width: visible.width) > 4)
}

/// T-16 AC-4: an edge drag never moves the top edge (header move area); bottom/side drags pass through.
@Test func liveResizeKeepsTopEdge() {
    let f = NSRect(x: 100, y: 300, width: 288, height: 300)
    let bottom = NSRect(x: 100, y: 200, width: 288, height: 400)
    #expect(ShelfPanel.pinTop(bottom, current: f) == bottom)
    let left = NSRect(x: 60, y: 300, width: 328, height: 300)
    #expect(ShelfPanel.pinTop(left, current: f) == left)
    let top = NSRect(x: 80, y: 300, width: 308, height: 350)
    #expect(ShelfPanel.pinTop(top, current: f) == NSRect(x: 80, y: 300, width: 308, height: 300))
}

/// T-16 AC-7: size saved per screen next to the offset; reset forgets both.
@Test func savedSizePerScreenAndReset() throws {
    let suite = "DragShelfTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    typealias C = ShelfPanelController
    C.save([400, 500], as: C.sizesKey, screen: "A", in: defaults)
    C.save([10, 20], as: C.offsetsKey, screen: "A", in: defaults)
    C.save([300, 350], as: C.sizesKey, screen: "B", in: defaults)
    #expect(C.saved(C.sizesKey, screen: "A", in: defaults) == [400, 500])
    #expect(C.saved(C.sizesKey, screen: "B", in: defaults) == [300, 350])
    #expect(C.saved(C.sizesKey, screen: "C", in: defaults) == nil)
    C.forgetPlacement(in: defaults)
    #expect(C.saved(C.sizesKey, screen: "A", in: defaults) == nil)
    #expect(C.saved(C.offsetsKey, screen: "A", in: defaults) == nil)
}

private func scrollViews(in view: NSView) -> [NSScrollView] {
    ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
}

/// T-16 AC-3: overlay scroller, inset off the right edge and clear of the rounded bottom corner.
@Test func scrollerIsOverlayAndInset() throws {
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("DragShelfTests-\(UUID().uuidString)")))
    for i in 0..<12 { store.add(ShelfItem(kind: .text("item \(i)"))) }
    let view = NSHostingView(rootView: ShelfView(store: store, maxHeight: 400))
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    view.setFrameSize(view.fittingSize)
    view.layoutSubtreeIfNeeded()
    let scroll = try #require(scrollViews(in: view).first)
    #expect(scroll.scrollerStyle == .overlay)
    #expect(scroll.scrollerInsets.right >= 4 && scroll.scrollerInsets.bottom >= shelfCornerRadius)
    #expect(view.fittingSize.height <= 400)
}

@Test func savedOffsetRoundTripsPerScreenAndClampsOffScreen() {
    let size = NSSize(width: 288, height: 300)
    let moved = NSRect(x: 100, y: 400, width: 288, height: 300)
    let o = ShelfPanelController.offset(of: moved, in: visible)
    #expect(ShelfPanelController.frame(size: size, offset: o, in: visible) == moved)
    // Same offset on a smaller screen at another origin: keeps distance from the top center.
    let other = NSRect(x: 1512, y: 0, width: 1280, height: 775)
    let f = ShelfPanelController.frame(size: size, offset: CGPoint(x: 0, y: 12), in: other)
    #expect(f.midX == other.midX && f.maxY == other.maxY - 12)
    // Spot saved on a bigger display / removed area → clamped into visibleFrame.
    let far = ShelfPanelController.frame(size: size, offset: CGPoint(x: 5000, y: 5000), in: other)
    #expect(other.contains(far))
}

@Test func tileHeightMatchesLayout() {
    let tile = NSHostingView(rootView: ShelfItemView(item: ShelfItem(kind: .text("x"))).frame(width: 88))
    #expect(abs(tile.fittingSize.height - ShelfView.tileHeight) < 1, "\(tile.fittingSize.height)")
    let footer = NSHostingView(rootView: HintFooter(hint: .clear, onDismiss: {}).frame(width: ShelfView.defaultWidth))
    #expect(abs(footer.fittingSize.height - ShelfView.footerRowHeight) < 1, "\(footer.fittingSize.height)")
}

/// Defaults: 360 pt wide = 3 columns; the footer row is reserved in min and max heights.
@Test func defaultSizeReservesFooterRow() {
    #expect(ShelfView.defaultWidth == 360 && ShelfView.columnCount(width: ShelfView.defaultWidth) == 3)
    #expect(ShelfView.footerRowHeight == 28)
    #expect(ShelfView.maxContentHeight == 52 + 4 * (ShelfView.tileHeight + 12) + ShelfView.tileHeight / 2 + 28)
    #expect(ShelfView.minSize.height == 52 + ShelfView.tileHeight + 14 + 28)
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString)")))
    let empty = NSHostingView(rootView: ShelfView(store: store)).fittingSize.height
    let tip = NSHostingView(rootView: ShelfView(store: store, hint: .clear)).fittingSize.height
    #expect(empty == tip && empty >= ShelfView.minHeight, "\(empty) \(tip)")
}

@Test func dedupeKeys() {
    let hash = SHA256.hash(data: Data("png".utf8))
    #expect(ShelfStore.key(for: ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/a/../x"))))
            == ShelfStore.key(for: ShelfItem(kind: .file(URL(fileURLWithPath: "/private/tmp/x")))))
    #expect(ShelfStore.key(for: ShelfItem(kind: .url(URL(string: "https://a.com")!))) == .url("https://a.com"))
    #expect(ShelfStore.key(for: ShelfItem(kind: .text("t"))) == .text("t"))
    #expect(ShelfStore.key(for: ShelfItem(kind: .file(URL(fileURLWithPath: "/c/i.png")), contentHash: hash)) == .image(hash))
}

@Test func removeAndClearDropKeys() {
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("DragShelfTests-\(UUID().uuidString)")))
    let a = ShelfItem(kind: .text("a"))
    store.add(a)
    store.remove(ids: [a.id])
    #expect(store.add(ShelfItem(kind: .text("a"))))
    store.clear()
    #expect(store.add(ShelfItem(kind: .text("a"))))
}

/// T-13 AC-8: 5000 real files add in < 1 s, then one more add < 1 ms.
@Test func addFiveThousandFilesIsFast() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfPerf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = try (0...5000).map { i in
        let u = dir.appendingPathComponent("f\(i)")
        try Data().write(to: u)
        return u
    }
    let store = ShelfStore(cache: ItemCache(root: dir.appendingPathComponent("cache")))
    let clock = ContinuousClock()
    let bulk = clock.measure { for u in urls.dropLast() { store.add(ShelfItem(kind: .file(u))) } }
    let one = clock.measure { store.add(ShelfItem(kind: .file(urls[5000]))) }
    #expect(store.items.count == 5001)
    #expect(bulk < .seconds(1), "5000 adds took \(bulk)")
    #expect(one < .milliseconds(1), "add at N=5000 took \(one)")
    #expect(!store.add(ShelfItem(kind: .file(urls[0]))))
}

/// V3-01: the pet's play floor adds its band on top of the default / saved size and the minimum (saved sizes never
/// include it), and the shelf grows by exactly the band.
@Test func petFloorAddsToLayout() throws {
    let f = PetController.floorHeight
    let d = ShelfPanelController.limits(saved: nil, in: visible, floor: f)
    #expect(d.maxHeight == min(ShelfView.maxContentHeight, (visible.height / 2).rounded()) + f)
    let user = ShelfPanelController.limits(saved: NSSize(width: 420, height: 500), in: visible, floor: f)
    #expect(user.width == 420 && user.maxHeight == 500 + f)
    let tiny = ShelfPanelController.limits(saved: NSSize(width: 10, height: 10), in: visible, floor: f)
    #expect(tiny.maxHeight == ShelfView.minSize.height + f)
    let huge = ShelfPanelController.limits(saved: NSSize(width: 9000, height: 9000), in: visible, floor: f)
    #expect(huge.maxHeight == visible.height)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ShelfStore(cache: ItemCache(root: root))
    for i in 0..<4 { store.add(ShelfItem(kind: .text("item \(i)"))) }
    let suite = "DragShelfTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pet = PetController(shelf: NSPanel(), store: store, defaults: defaults)
    let without = NSHostingView(rootView: ShelfView(store: store, maxHeight: 600)).fittingSize.height
    let with = NSHostingView(rootView: ShelfView(store: store, maxHeight: 600 + f, pet: pet)).fittingSize.height
    #expect(abs(with - without - f) < 0.5, "\(without) \(with)")
    let empty = ShelfStore(cache: ItemCache(root: root))
    #expect(NSHostingView(rootView: ShelfView(store: empty, pet: pet)).fittingSize.height >= ShelfView.minHeight + f)
}
