import Foundation
import Testing
@testable import DragShelf

private func tempStore() -> ShelfStore {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("SearchTests-\(UUID().uuidString)", isDirectory: true)
    return ShelfStore(cache: ItemCache(root: base.appendingPathComponent("cache")), pins: PinStore(root: base.appendingPathComponent("pins")))
}

private func file(_ name: String) -> ShelfItem { ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/\(name)"))) }
private func names(_ items: [ShelfItem]) -> [String] { items.map(\.displayName) }

@Test func matchesNameLinkAndTextIgnoringCaseAndDiacritics() {
    let store = tempStore()
    let resume = file("Résumé Final.PDF"), link = ShelfItem(kind: .url(URL(string: "https://example.com/caf%C3%A9-menu")!))
    let text = ShelfItem(kind: .text("Meeting notes\nBring the CAFÉ order"))
    [resume, link, text, file("photo.png")].forEach { store.add($0) }
    #expect(store.visibleItems.count == 4 && !store.isFiltering)
    store.query = "resume"
    #expect(store.visibleItems == [resume] && store.isFiltering)
    store.query = "FINAL.pdf"
    #expect(store.visibleItems == [resume])
    store.query = "cafe"
    #expect(store.visibleItems == [link, text]) // percent-decoded link text, text content
    store.query = "example.com"
    #expect(store.visibleItems == [link])
    store.query = "   "
    #expect(store.visibleItems.count == 4 && !store.isFiltering) // blank = all
    store.query = "zzz"
    #expect(store.visibleItems.isEmpty)
}

@Test func filterKinds() {
    let store = tempStore()
    let doc = file("a.pdf"), image = file("b.PNG"), folder = file("Folder")
    let link = ShelfItem(kind: .url(URL(string: "https://a.com")!)), text = ShelfItem(kind: .text("hello"))
    [doc, image, folder, link, text].forEach { store.add($0) }
    let expected: [ShelfStore.Filter: [ShelfItem]] = [
        .all: [doc, image, folder, link, text], .files: [doc, folder], .images: [image], .links: [link], .text: [text], .pinned: [],
    ]
    for (filter, items) in expected {
        store.filter = filter
        #expect(store.visibleItems == items, "\(filter)")
    }
    store.pin([text])
    store.filter = .pinned
    #expect(store.visibleItems.map(\.id) == [text.id])
    store.filter = .files
    store.query = "fold"
    #expect(store.visibleItems == [folder]) // filter and query combine
    store.resetSearch()
    #expect(!store.isSearching && store.query.isEmpty && store.filter == .all && store.visibleItems.count == 5)
}

@Test func renameUpdatesSearchKey() {
    let store = tempStore()
    let item = file("old.txt")
    store.add(item)
    store.query = "new"
    #expect(store.visibleItems.isEmpty)
    store.replace(id: item.id, with: ShelfItem(id: item.id, kind: .file(URL(fileURLWithPath: "/tmp/new.txt"))))
    #expect(store.visibleItems.map(\.id) == [item.id])
}

@Test func actionsApplyToVisibleItemsOnly() {
    let store = tempStore()
    let a = file("apple.txt"), b = file("banana.txt"), c = file("apricot.txt"), d = file("cherry.txt")
    [a, b, c, d].forEach { store.add($0) }
    store.selection = [a.id, b.id]
    store.query = "ap"
    // Hidden tiles leave the selection; what is left is what ⌘C, Quick Look, actions use.
    #expect(store.selection == [a.id] && store.selectedItems == [a])
    #expect(store.dragItems(for: nil) == [a, c]) // Drag All
    store.selectAll()
    #expect(store.selection == [a.id, c.id])
    #expect(store.targetIDs(for: a.id) == [a.id, c.id])
    // Arrows walk the visible items only.
    store.select(a.id, command: false, shift: false)
    store.moveSelection(by: 1)
    #expect(store.selection == [c.id])
    store.moveSelection(by: 1)
    #expect(store.selection == [c.id])
    // Shift range spans visible items only.
    store.select(a.id, command: false, shift: false)
    store.select(c.id, command: false, shift: true)
    #expect(store.selection == [a.id, c.id])
    // A hidden item selected by something else (an action output) is not acted on.
    store.selection.insert(d.id)
    #expect(store.selectedIDs == [a.id, c.id])
    // Clear while filtered removes the shown items (what the header button does); a drop still adds, filter stays.
    store.remove(ids: Set(store.visibleItems.map(\.id)))
    #expect(store.items == [b, d] && store.visibleItems.isEmpty)
    let added = file("apex.txt")
    store.add(added)
    store.add(file("date.txt"))
    #expect(store.visibleItems == [added] && store.query == "ap")
}

@Test func pinnedSurviveFilteredRemove() {
    let store = tempStore()
    let a = ShelfItem(kind: .text("alpha one")), b = ShelfItem(kind: .text("alpha two"))
    [a, b].forEach { store.add($0) }
    store.pin([a])
    store.query = "alpha"
    store.remove(ids: Set(store.visibleItems.map(\.id)))
    #expect(store.items.map(\.id) == [a.id])
}

@Test func filtering5000ItemsIsFast() {
    let store = tempStore()
    for i in 0..<5000 {
        let kind: ShelfItem.Kind = switch i % 3 {
        case 0: .file(URL(fileURLWithPath: "/Users/me/Documents/Project \(i)/Résumé draft \(i).pdf"))
        case 1: .url(URL(string: "https://example.com/articles/\(i)/some-long-title")!)
        default: .text("Note \(i): the quick brown fox jumps over the lazy dog, café au lait")
        }
        store.add(ShelfItem(kind: kind))
    }
    store.filter = .files
    _ = store.visibleItems // warm up
    var worst = Duration.zero
    for query in ["resume", "CAFÉ", "4999", "nothing-matches-this", "e"] {
        store.query = query
        worst = max(worst, ContinuousClock().measure { _ = store.visibleItems })
    }
    store.filter = .all
    worst = max(worst, ContinuousClock().measure { _ = store.visibleItems })
    #expect(worst < .milliseconds(16), "worst \(worst)")
}
