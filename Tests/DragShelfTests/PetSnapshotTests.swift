import AppKit
import SwiftUI
import Testing
@testable import DragShelf

nonisolated private let snapshotDir = ProcessInfo.processInfo.environment["DRAGSHELF_SNAPSHOT_DIR"]

/// Review aid for the shelf pet (V3-01): `DRAGSHELF_SNAPSHOT_DIR=/path swift test --filter petSnapshots` writes
/// `<dir>/pet/`: each pose on a strip of floor (light and dark, 2x), a contact sheet and a 4x close-up, and the
/// shelf with the cat on its bottom rim (light and dark) in several poses, with its ball, and leaving.
@Test(.enabled(if: snapshotDir != nil))
func petSnapshots() throws {
    let out = URL(fileURLWithPath: try #require(snapshotDir), isDirectory: true).appendingPathComponent("pet")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    func tile(_ f: PetFrame, facingRight: Bool = true, dark: Bool, ball: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(dark ? Color(white: 0.3) : Color(red: 0.93, green: 0.88, blue: 0.82))
                .frame(width: 96, height: 9)
                .offset(y: PetArt.ground + 8)
            PetSprite(frame: f, facingRight: facingRight).offset(x: 16, y: 8)
            if ball { YarnView(spin: 1).offset(x: 66, y: PetArt.ground - 9) }
        }
        .frame(width: 96, height: 84, alignment: .topLeading)
        .background(dark ? Color(white: 0.12) : .white)
    }

    func write(_ view: some View, _ name: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name))
    }

    let frames: [(String, PetFrame)] = [
        ("sit", PetFrame(pose: .sit)), ("look", PetFrame(pose: .look, turn: 0.8)), ("perk", PetFrame(pose: .perk, turn: 0.7)),
        ("sad", PetFrame(pose: .sad, turn: 0.4)), ("sniff", PetFrame(pose: .sniff)), ("purr", PetFrame(pose: .purr)),
        ("yawn", PetFrame(pose: .yawn, progress: 0.5)), ("bat", PetFrame(pose: .bat, progress: 0.15)),
        ("sleep", PetFrame(pose: .sleep)),
        ("walk-0", PetFrame(pose: .walk, step: 0, turn: 1)), ("walk-1", PetFrame(pose: .walk, step: 1, turn: 1)),
        ("walk-2", PetFrame(pose: .walk, step: 2, turn: 1)), ("walk-3", PetFrame(pose: .walk, step: 3, turn: 1)),
        ("head-turn", PetFrame(pose: .walk, step: 1, turn: 0)), ("run", PetFrame(pose: .run, step: 0, turn: 1)),
        ("carry", PetFrame(pose: .carry, step: 1, turn: 1)), ("crouch", PetFrame(pose: .crouch, step: 1, turn: 1)),
        ("pounce", PetFrame(pose: .pounce, progress: 0.5, turn: 1)), ("stretch", PetFrame(pose: .stretch, progress: 0.8)),
        ("back-roll", PetFrame(pose: .backRoll, progress: 0.1)), ("peek", PetFrame(pose: .peek, progress: 0.4)),
        ("hide", PetFrame(pose: .hide, progress: 1)),
        ("pounce-up", PetFrame(pose: .pounceUp, progress: 0.5, turn: 1)), ("bat-up", PetFrame(pose: .batUp, progress: 0.5)),
        ("bat-up-start", PetFrame(pose: .batUp, progress: 0.05)), ("head-rub", PetFrame(pose: .headRub, step: 1, progress: 0.3)),
        ("body-rub", PetFrame(pose: .bodyRub, step: 0, progress: 0.3, turn: 1)), ("peek-eye", PetFrame(pose: .peekEye)),
        ("sleep-twitch", PetFrame(pose: .sleep, turn: 1)), ("watch-up", PetFrame(pose: .perk, turn: 0.1)),
    ]
    for (name, f) in frames {
        try write(HStack(spacing: 0) { tile(f, dark: false); tile(f, dark: true) }, "pet-\(name).png")
    }
    try write(HStack(spacing: 0) {
        tile(PetFrame(pose: .walk, step: 1, turn: 1), facingRight: true, dark: false)
        tile(PetFrame(pose: .walk, step: 1, turn: 1), facingRight: false, dark: false)
    }, "pet-walk-left-right.png")
    try write(tile(PetFrame(pose: .crouch, step: 0, turn: 1), dark: false, ball: true), "pet-ball.png")
    try write(VStack(spacing: 0) {
        ForEach(0..<(frames.count + 5) / 6, id: \.self) { row in
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    if row * 6 + i < frames.count { tile(frames[row * 6 + i].1, dark: false) }
                }
            }
        }
    }.background(.white), "pet-sheet.png")
    try write(VStack(spacing: 0) {
        ForEach(0..<(frames.count + 3) / 4, id: \.self) { row in
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    if row * 4 + i < frames.count { tile(frames[row * 4 + i].1, dark: false) }
                }
            }
        }
    }.background(.white), "pet-zoom.png", scale: 4)

    // The shelf with the cat on its bottom rim.
    let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PetSnap-\(UUID())")
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let store = ShelfStore(cache: ItemCache(root: cacheRoot))
    for i in 1...5 { store.add(ShelfItem(kind: .text("Snippet \(i)"))) }
    let suite = "PetSnap-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pet = PetController(shelf: NSPanel(), store: store, defaults: defaults)
    let scenes: [(String, PetSnapshot)] = [
        ("sleep", PetSnapshot(frame: PetFrame(pose: .sleep), x: 20, facingRight: true)),
        ("walk", PetSnapshot(frame: PetFrame(pose: .walk, step: 1, turn: 1), x: 120, facingRight: true)),
        ("walk-left", PetSnapshot(frame: PetFrame(pose: .walk, step: 2, turn: 1), x: 200, facingRight: false)),
        ("lookup", PetSnapshot(frame: PetFrame(pose: .perk, turn: 0.7), x: 150, facingRight: true)),
        ("purr", PetSnapshot(frame: PetFrame(pose: .purr, progress: 0.4), x: 60, facingRight: true, bubble: "purrr…")),
        ("ball", PetSnapshot(frame: PetFrame(pose: .crouch, step: 0, turn: 1), x: 160, facingRight: true, ball: 195)),
        ("exit", PetSnapshot(frame: PetFrame(pose: .run, step: 1, turn: 1), x: 262, facingRight: true)),
        ("pounce-up", PetSnapshot(frame: PetFrame(pose: .pounceUp, progress: 0.5, turn: 1), x: 140, facingRight: true, lift: 38)),
        ("bat-up", PetSnapshot(frame: PetFrame(pose: .batUp, progress: 0.5), x: 100, facingRight: false)),
        ("head-rub", PetSnapshot(frame: PetFrame(pose: .headRub, step: 1, progress: 0.4), x: 180, facingRight: true,
                                 bubble: "purrr…")),
        ("body-rub", PetSnapshot(frame: PetFrame(pose: .bodyRub, progress: 0.4, turn: 1), x: 120, facingRight: false,
                                 bubble: "purrr…")),
        ("petting-hearts", PetSnapshot(frame: PetFrame(pose: .purr, step: 1, progress: 0.5), x: 90, facingRight: true,
                                       bubble: "purrr…")),
        ("ball-play", PetSnapshot(frame: PetFrame(pose: .backRoll, progress: 0.1), x: 150, facingRight: true)),
        ("ball-bat", PetSnapshot(frame: PetFrame(pose: .bat, progress: 0.2), x: 150, facingRight: true, ball: 178, ballSpin: 2)),
        ("call", PetSnapshot(frame: PetFrame(pose: .perk, turn: 0.7), x: 70, facingRight: true, bubble: "!")),
        ("peek-eye", PetSnapshot(frame: PetFrame(pose: .peekEye), x: 30, facingRight: true)),
    ]
    for (scene, snap) in scenes {
        pet.snapshot = snap
        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // Glass does not render offscreen: a plain fill stands in for it.
            let view = NSHostingView(rootView: ShelfView(store: store, maxHeight: 600, pet: pet)
                .background(RoundedRectangle(cornerRadius: shelfCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)))
                .padding(24)
                .background(Color(nsColor: .underPageBackgroundColor)))
            view.appearance = NSAppearance(named: appearance)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.setFrameSize(view.fittingSize)
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: out.appendingPathComponent("rim-\(scene)-\(scheme).png"))
        }
    }
}
