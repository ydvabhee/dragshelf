import AppKit
import SwiftUI
import Testing
@testable import DragShelf

nonisolated private let snapshotDir = ProcessInfo.processInfo.environment["DRAGSHELF_SNAPSHOT_DIR"]

/// Review aid, not an assertion: `DRAGSHELF_SNAPSHOT_DIR=/path swift test --filter shelfSnapshots`
/// writes ShelfView PNGs (empty / 4 items incl. a missing file / 12 items scrolling with a selected tile at the default
/// and a resized width × light / dark, 2x). Glass does not render offscreen.
/// Uses NSHostingView.cacheDisplay: ImageRenderer drops everything inside `glassEffect` and ScrollView.
@Test(.enabled(if: snapshotDir != nil))
func shelfSnapshots() throws {
    let out = URL(fileURLWithPath: try #require(snapshotDir), isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfSnap-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let pdf = tmp.appendingPathComponent("Quarterly Report – Final Draft v3.pdf")
    try Data().write(to: pdf)
    let items = ShelfStore(cache: ItemCache(root: tmp.appendingPathComponent("cache")))
    items.add(ShelfItem(kind: .file(pdf)))
    items.add(ShelfItem(kind: .url(URL(string: "https://developer.apple.com/design/human-interface-guidelines")!)))
    items.add(ShelfItem(kind: .text("Meeting notes for Thursday\nSecond line")))
    items.add(ShelfItem(kind: .file(tmp.appendingPathComponent("Deleted Since.key"))))
    items.refreshMissing()
    let empty = ShelfStore(cache: ItemCache(root: tmp.appendingPathComponent("cache")))
    let many = ShelfStore(cache: ItemCache(root: tmp.appendingPathComponent("cache")))
    for i in 1...12 { many.add(ShelfItem(kind: .text("Snippet \(i)"))) }
    many.selection = [many.items[4].id]

    let cases: [(String, ShelfStore, CGFloat)] = [("empty", empty, ShelfView.defaultWidth), ("items", items, ShelfView.defaultWidth),
                                                  ("scroll", many, ShelfView.defaultWidth), ("scroll-wide", many, 400)]
    for (name, store, width) in cases {
        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = NSHostingView(rootView: ShelfView(store: store, width: width, maxHeight: 420)
                .padding(32)
                .background(Color(nsColor: .underPageBackgroundColor)))
            view.appearance = NSAppearance(named: appearance)
            // Backing scale follows the main screen (2x on Retina).
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.setFrameSize(view.fittingSize)
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("shelf-\(name)-\(scheme).png"))
        }
    }
}
