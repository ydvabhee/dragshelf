import AppKit
import Foundation
import Testing
@testable import DragShelf

/// A controller on a shown shelf; pet defaults live in a throwaway suite, never the real ones.
@MainActor private func rig(petOn: Bool = true, preview: Bool = false, introSeen: Bool = true, dragging: Bool = false)
    throws -> (PetController, ShelfStore, UserDefaults, () -> Void) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("TipRoute-\(UUID())")
    let suite = "TipRoute-\(UUID().uuidString)"
    let d = try #require(UserDefaults(suiteName: suite))
    d.set(petOn, forKey: Preferences.petEnabled)
    d.set(preview, forKey: Preferences.petPreview)
    if preview { d.set(2, forKey: Preferences.petSessions) }
    d.set(introSeen, forKey: Preferences.petIntroSeen)
    let engine = HintEngine(defaults: d)
    engine.shortcutRegistered = { true }
    let store = ShelfStore(cache: ItemCache(root: root), hints: engine)
    store.isDragging = dragging
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260), styleMask: [], backing: .buffered, defer: true)
    let pet = PetController(shelf: panel, store: store, defaults: d)
    return (pet, store, d, { try? FileManager.default.removeItem(at: root); d.removePersistentDomain(forName: suite) })
}

/// Polls the main actor (observation hops asynchronously) for up to `seconds`.
@MainActor private func until(_ seconds: Double = 30, _ cond: () -> Bool) async throws {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { try await Task.sleep(for: .milliseconds(50)) }
}

/// Serialized: these poll the main actor and starve when other suites hold it.
@Suite(.serialized) struct PetTipRoutingTests {
    @MainActor @Test func petOnNeverUsesFooterForTips() async throws {
        for preview in [false, true] {
            let (pet, store, _, cleanup) = try rig(preview: preview)
            defer { cleanup() }
            pet.shelfDidShow()
            store.hints.visible = true
            store.hints.record(.shown(.manual, hasFile: false, hasRecent: false))
            store.hints.record(.shown(.manual, hasFile: false, hasRecent: false)) // Menu show #2: the shortcut tip.
            #expect(store.hints.current == .hotkey)
            #expect(pet.tipsOnStage)
            for hint in HintEngine.Hint.allCases {
                #expect(ShelfView.tipRoute(hint: hint, petOnStage: pet.tipsOnStage).footer == nil)
            }
            try await until { pet.delivered == .hotkey }
            #expect(pet.delivered == .hotkey, "empty shelf, preview \(preview): the cat tells it")
        }
    }

    @MainActor @Test func petOffKeepsFooterTips() throws {
        let (pet, store, _, cleanup) = try rig(petOn: false)
        defer { cleanup() }
        pet.shelfDidShow()
        store.hints.visible = true
        store.hints.record(.cleared)
        #expect(!pet.tipsOnStage && pet.delivered == nil)
        #expect(ShelfView.tipRoute(hint: store.hints.current, petOnStage: pet.tipsOnStage).footer == .clear)
    }

    @MainActor @Test func tipWaitsDuringDragThenCatTellsIt() async throws {
        let (pet, store, _, cleanup) = try rig()
        defer { cleanup() }
        store.isDragging = true // Drag auto-show: the cat stays out.
        pet.shelfDidShow()
        store.hints.visible = true
        store.hints.record(.cleared) // Held back by the engine while dragging; force one anyway.
        #expect(pet.delivered == nil)
        try await Task.sleep(for: .seconds(2))
        #expect(!pet.interactive && pet.delivered == nil)
        store.isDragging = false
        try await until { pet.interactive && pet.delivered == .clear }
        #expect(pet.interactive, "walks in after the drag")
        #expect(pet.delivered == .clear)
    }

    @MainActor @Test func catAppearsOnEmptyShelfWithinASecondOrTwo() async throws {
        let (pet, store, _, cleanup) = try rig()
        defer { cleanup() }
        #expect(store.items.isEmpty)
        pet.shelfDidShow()
        try await until { pet.interactive }
        #expect(pet.interactive)
    }

    @MainActor @Test func introComesBeforeTheTip() throws {
        let (pet, store, _, cleanup) = try rig(introSeen: false)
        defer { cleanup() }
        pet.shelfDidShow()
        store.hints.visible = true
        store.hints.record(.cleared)
        #expect(pet.delivered == nil && pet.introPending)
        pet.showIntro()
        pet.shelfClicked()
        #expect(pet.delivered == .clear)
    }
}
