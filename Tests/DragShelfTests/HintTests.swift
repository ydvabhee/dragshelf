import AppKit
import Foundation
import Testing
@testable import DragShelf

private func engine() -> (HintEngine, UserDefaults) {
    let d = UserDefaults(suiteName: "HintTests-\(UUID().uuidString)")!
    let e = HintEngine(defaults: d)
    e.shortcutRegistered = { true }
    e.visible = true
    return (e, d)
}

private let promo = PromoFeed.decode(Data(#"{"version":1,"promos":[{"id":"p","title":"App","url":"https://example.com/p"}]}"#.utf8))!.promos[0]

@Test func eventsPickTheirHint() {
    let (e, _) = engine()
    e.record(.dropped)
    #expect(e.current == .firstDrop)
    e.record(.draggedOut(removed: true))
    #expect(e.current == .dragOut)
    e.record(.draggedOut(removed: false))
    #expect(e.current == .recent)
}

@Test func showTriggers() {
    let (e, _) = engine()
    e.record(.shown(.hotkey, hasFile: false, hasRecent: false))
    #expect(e.current == nil)
    e.record(.shown(.hotkey, hasFile: true, hasRecent: false))
    #expect(e.current == .holdCommand)
    // 3rd show: move/resize; holdCommand not triggered this time.
    e.record(.shown(.hotkey, hasFile: false, hasRecent: false))
    #expect(e.current == .moveResize)
    // 1st menu show: no hotkey tip; 2nd: hotkey tip wins over the others.
    e.visible = false
    e.record(.shown(.manual, hasFile: false, hasRecent: false))
    e.visible = true
    #expect(e.current == .moveResize)
    e.record(.shown(.manual, hasFile: true, hasRecent: true))
    #expect(e.current == .hotkey)
}

@Test func hotkeyTipNeedsShortcutOn() {
    let (e, d) = engine()
    d.set(false, forKey: Preferences.hotKeyEnabled)
    e.record(.shown(.manual, hasFile: false, hasRecent: false))
    e.record(.shown(.manual, hasFile: false, hasRecent: false))
    #expect(e.current == nil)
}

@Test func hotkeyTipNeedsRegisteredShortcut() {
    let (e, _) = engine()
    e.shortcutRegistered = { false } // On, but Carbon refused it at launch.
    e.record(.shown(.manual, hasFile: false, hasRecent: false))
    e.record(.shown(.manual, hasFile: false, hasRecent: false))
    #expect(e.current == nil)
}

@Test func retiresAfterThreeShows() {
    let (e, _) = engine()
    for _ in 0..<HintEngine.maxShows {
        e.visible = false
        e.record(.dropped)
        e.visible = true
        #expect(e.current == .firstDrop)
    }
    e.visible = false
    e.record(.dropped)
    e.visible = true
    #expect(e.current == nil)
    #expect(e.count(.firstDrop) == 3)
}

@Test func dismissIsForeverAndPersists() {
    let (e, d) = engine()
    e.record(.dropped)
    e.dismiss()
    #expect(e.current == nil)
    let again = HintEngine(defaults: d)
    again.visible = true
    again.record(.dropped)
    #expect(again.current == nil)
    again.record(.cleared)
    #expect(again.current == .clear)
    again.reset()
    #expect(again.current == nil)
    again.record(.dropped)
    #expect(again.current == .firstDrop)
    #expect(again.count(.firstDrop) == 1)
}

@Test func neverDuringDragAndWaitsForShow() {
    let (e, _) = engine()
    e.dragging = true
    e.record(.dropped)
    #expect(e.current == nil)
    e.dragging = false
    #expect(e.current == .firstDrop)
    // Hidden (Clear hides the panel): pending until the next show, then highest priority.
    e.visible = false
    #expect(e.current == nil)
    e.record(.cleared)
    #expect(e.count(.clear) == 0)
    e.record(.shown(.hotkey, hasFile: true, hasRecent: false))
    e.visible = true
    #expect(e.current == .clear)
}

@Test func tipsOffShowsNothing() {
    let (e, d) = engine()
    d.set(false, forKey: Preferences.showTips)
    e.record(.dropped)
    e.record(.cleared)
    #expect(e.current == nil)
}

@Test func hintBeatsPromo() {
    #expect(ShelfView.footer(hint: .recent, promo: promo) == .hint(.recent))
    #expect(ShelfView.footer(hint: nil, promo: promo) == .promo(promo))
    #expect(ShelfView.footer(hint: nil, promo: nil) == nil)
}

@Test func storeDragFlagsHoldBackHints() {
    let (e, _) = engine()
    let store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("HintTests-\(UUID().uuidString)", isDirectory: true)), hints: e)
    store.isDropTargeted = true
    e.record(.dropped)
    #expect(e.current == nil)
    store.isDropTargeted = false
    #expect(e.current == .firstDrop)
}

@Test func spokenTextSpellsKeys() {
    #expect(HintEngine.Hint.hotkey.spokenText == "Tip: Control-Option-Command-D shows DragShelf from anywhere.")
    #expect(HintEngine.Hint.dragOut.spokenText == "Tip: Removed from DragShelf, Command-Z to bring it back")
}

// MARK: Pet tips (V3-01)

@Test func tipGoesToCatOrFooterNeverBoth() {
    #expect(ShelfView.tipRoute(hint: .recent, petOnStage: true) == (nil, .recent))
    #expect(ShelfView.tipRoute(hint: .recent, petOnStage: false) == (.recent, nil)) // Pet off or hidden: footer.
    #expect(ShelfView.tipRoute(hint: nil, petOnStage: true) == (nil, nil))
    for hint in HintEngine.Hint.allCases {
        for onStage in [true, false] {
            let r = ShelfView.tipRoute(hint: hint, petOnStage: onStage)
            #expect((r.footer == nil) != (r.bubble == nil))
        }
    }
}

@Test func oneTipAtATime() {
    let (e, _) = engine()
    e.record(.dropped)
    e.record(.cleared)
    #expect(e.current == .clear) // Highest priority wins; the rest wait for a later show.
    e.record(.draggedOut(removed: false))
    #expect(e.current == .recent)
}

@Test func pastePinSearchTriggers() {
    let (e, _) = engine()
    e.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 1))
    #expect(e.current == nil)
    e.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 1))
    #expect(e.current == .paste)
    let (p, _) = engine()
    p.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 4))
    #expect(p.current == .pin)
    let (f, _) = engine()
    f.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 8))
    #expect(f.current == .pin) // Pin first, then search on a later show.
    f.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 8))
    f.dismiss()
    f.record(.shown(.hotkey, hasFile: false, hasRecent: false, itemCount: 8))
    #expect(f.current == .search || f.current == .moveResize)
}

@Test func bubbleTextIsShortFirstPersonAndUsesTheShortcut() {
    for hint in HintEngine.Hint.allCases {
        #expect(hint.bubbleText.count <= 60, "\(hint)")
        // Branding: the panel is "DragShelf", never a bare "Shelf".
        #expect(hint.bubbleText.range(of: #"(?<!Drag)Shelf\b"#, options: .regularExpression) == nil, "\(hint)")
    }
    #expect(HintEngine.Hint.hotkey.bubbleText == "\(Preferences.shortcut().display) brings DragShelf back from anywhere")
    #expect(HintEngine.Hint.paste.spokenBubble == "Tip: Command-V pastes your clipboard here")
}

@MainActor @Test func introFirstThenClickDismissesIntroAndTipUnlearned() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Intro-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let d = try #require(UserDefaults(suiteName: "Intro-\(UUID().uuidString)"))
    let store = ShelfStore(cache: ItemCache(root: root), hints: HintEngine(defaults: d))
    d.set(true, forKey: Preferences.petEnabled)
    d.set("Pixel", forKey: Preferences.petName)
    let pet = PetController(shelf: NSPanel(), store: store, defaults: d)
    #expect(PetController.introText(name: pet.name) == "Hey, I'm Pixel!")
    #expect(pet.introPending) // Tips wait for it.
    pet.showIntro()
    #expect(pet.introShowing)
    pet.shelfClicked()
    #expect(!pet.introShowing && !pet.introPending)
    #expect(d.bool(forKey: Preferences.petIntroSeen))
    // A click hides a tip bubble without learning it.
    store.hints.visible = true
    store.hints.record(.cleared)
    pet.tip = .clear
    pet.shelfClicked()
    #expect(pet.tip == nil)
    #expect(store.hints.dismissed.isEmpty)
    pet.tip = .clear
    pet.tipLearned()
    #expect(store.hints.dismissed == [HintEngine.Hint.clear.rawValue])
}

@Test func resetTipsResetsIntro() {
    let (e, d) = engine()
    d.set(true, forKey: Preferences.petIntroSeen)
    e.reset()
    #expect(!d.bool(forKey: Preferences.petIntroSeen))
}

@Test func mochiLinesHaveNoEmoji() {
    let lines = HintEngine.Hint.allCases.map(\.bubbleText) + [PetController.introText(name: "Mochi")]
    for line in lines {
        #expect(!line.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000) }, "\(line)")
    }
}
