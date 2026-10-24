import AppKit
import SwiftUI
import Testing
@testable import DragShelf

nonisolated private let snapshotDir = ProcessInfo.processInfo.environment["DRAGSHELF_SNAPSHOT_DIR"]

/// Review aid for the shelf pet (V3-01): `DRAGSHELF_SNAPSHOT_DIR=/path swift test --filter petSnapshots` writes
/// `<dir>/pet/pet-<pose>.png` (each pose on a shelf edge, light and dark, 2x), the yarn ball, one contact sheet,
/// and the cat on a real 360 pt shelf.
@Test(.enabled(if: snapshotDir != nil))
func petSnapshots() throws {
    let out = URL(fileURLWithPath: try #require(snapshotDir), isDirectory: true).appendingPathComponent("pet")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    /// Cat on a strip of "shelf" so the edge, peek and paws read in context.
    func tile(_ pose: PetPose, step: Int, progress: Double, dark: Bool, ball: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dark ? Color(white: 0.24) : Color(white: 0.93))
                .frame(width: 96, height: 20)
                .offset(y: PetArt.ground + 8)
            PetSprite(pose: pose, step: step, progress: progress)
                .offset(x: 16, y: 8)
            if ball {
                YarnView().offset(x: 66, y: PetArt.ground - 8)
            }
        }
        .frame(width: 96, height: 92, alignment: .topLeading)
        .background(dark ? Color(white: 0.12) : .white)
    }

    func write(_ view: some View, _ name: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name))
    }

    let frames: [(PetPose, Int, Double)] = [
        (.sit, 0, 0), (.walk, 0, 0), (.walk, 1, 0), (.walk, 2, 0), (.walk, 3, 0), (.stretch, 0, 0.8),
        (.yawn, 0, 0.5), (.sleep, 0, 0), (.peek, 0, 1), (.pounce, 0, 0.5), (.bat, 0, 0.15), (.purr, 0, 0),
    ]
    for (pose, step, progress) in frames {
        let suffix = pose == .walk ? "-\(step)" : ""
        try write(HStack(spacing: 0) {
            tile(pose, step: step, progress: progress, dark: false)
            tile(pose, step: step, progress: progress, dark: true)
        }, "pet-\(pose.rawValue)\(suffix).png")
    }
    try write(HStack(spacing: 0) { tile(.bat, step: 0, progress: 0.3, dark: false, ball: true) }, "pet-ball.png")
    try write(VStack(spacing: 0) {
        HStack(spacing: 0) { ForEach(0..<6, id: \.self) { i in tile(frames[i].0, step: frames[i].1, progress: frames[i].2, dark: false) } }
        HStack(spacing: 0) { ForEach(6..<12, id: \.self) { i in tile(frames[i].0, step: frames[i].1, progress: frames[i].2, dark: false) } }
    }, "pet-sheet.png")
    // Close-up for detail review (4x).
    try write(VStack(spacing: 0) {
        ForEach(0..<3, id: \.self) { row in
            HStack(spacing: 0) { ForEach(0..<4, id: \.self) { i in let f = frames[row * 4 + i]; tile(f.0, step: f.1, progress: f.2, dark: false) } }
        }
    }, "pet-zoom.png", scale: 4)

    // In context: walking on a 360 pt shelf with items, ball out (NSHostingView: ImageRenderer drops ScrollView).
    let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PetSnap-\(UUID())")
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let store = ShelfStore(cache: ItemCache(root: cacheRoot))
    for i in 1...5 { store.add(ShelfItem(kind: .text("Snippet \(i)"))) }
    PetHub.shared.available = true // Header yarn button.
    PetHub.shared.ballOut = true
    defer { PetHub.shared.available = false; PetHub.shared.ballOut = false }
    for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: -PetController.overlap) {
            ZStack(alignment: .topLeading) {
                PetSprite(pose: .walk, step: 1).offset(x: PetController.inset + 90 - 32)
                YarnView(spin: 1).offset(x: PetController.inset + 200 - 22, y: PetArt.ground - 15)
            }
            .frame(width: ShelfView.defaultWidth, height: PetController.height, alignment: .topLeading)
            .zIndex(1) // The pet window sits above the shelf.
            // Glass does not render offscreen: a plain fill shows the shelf's edge.
            ShelfView(store: store, maxHeight: 420)
                .background(RoundedRectangle(cornerRadius: shelfCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)))
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor)))
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent("pet-on-shelf-\(scheme).png"))
    }
}
