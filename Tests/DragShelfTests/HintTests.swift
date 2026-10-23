import Foundation
import Testing
@testable import DragShelf

private func engine() -> (HintEngine, UserDefaults) {
    let d = UserDefaults(suiteName: "HintTests-\(UUID().uuidString)")!
    let e = HintEngine(defaults: d)
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
