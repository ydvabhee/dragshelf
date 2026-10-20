import AppKit
import CryptoKit
import SwiftUI
import Testing
@testable import DragShelf

private let visible = NSRect(x: 0, y: 0, width: 1512, height: 945)

@Test func fitKeepsTopEdgeAndClampsAtScreenBottom() {
    let f = NSRect(x: 600, y: 600, width: 288, height: 160)
    let grown = ShelfPanelController.fit(f, height: 400, in: visible)
    #expect(grown.maxY == f.maxY && grown.height == 400 && grown.minX == f.minX)
    #expect(ShelfPanelController.fit(grown, height: 160, in: visible) == f)
    // Near the bottom: grows past visible.minY → shifted up, never outside.
    let low = NSRect(x: 600, y: 20, width: 288, height: 160)
    let g = ShelfPanelController.fit(low, height: 400, in: visible)
    #expect(g.minY == visible.minY && g.height == 400)
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
