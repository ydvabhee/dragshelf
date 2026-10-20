import AppKit
import Testing
@testable import DragShelf

private func tempStore() -> ShelfStore {
    ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("DragOutTests-\(UUID().uuidString)", isDirectory: true)))
}

private let file = URL(fileURLWithPath: "/tmp/a.txt")
private let web = URL(string: "https://example.com/x")!

@Test func writerPerKind() {
    #expect(DragOutSource.writer(for: ShelfItem(kind: .file(file))) as? NSURL == file as NSURL)
    #expect(DragOutSource.writer(for: ShelfItem(kind: .url(web))) as? NSURL == web as NSURL)
    #expect(DragOutSource.writer(for: ShelfItem(kind: .text("hi"))) as? NSString == "hi")
}

@Test func copyRoundTripsThroughReader() {
    let pb = NSPasteboard(name: .init("test-copy-\(UUID())"))
    defer { pb.releaseGlobally() }
    DragOutSource.copy([ShelfItem(kind: .file(file)), ShelfItem(kind: .url(web)), ShelfItem(kind: .text("hi"))], to: pb)
    #expect(PasteboardReader.read(pb) == [.file(file), .url(web), .text("hi")])
}

@Test func operationMask() {
    for cmd in [false, true] {
        let m: NSEvent.ModifierFlags = cmd ? .command : []
        #expect(DragOutSource.mask(for: .withinApplication, modifiers: m, allFiles: true) == [])
        #expect(DragOutSource.mask(for: .outsideApplication, modifiers: m, allFiles: false) == .copy)
        #expect(DragOutSource.mask(for: .outsideApplication, modifiers: m, allFiles: true) == (cmd ? .move : .copy))
    }
    #expect(DragOutSource.mask(for: .outsideApplication, modifiers: [.option, .shift], allFiles: true) == .copy)
}

@Test func sessionEndRemovesOnlyOnDrop() throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let dir = try store.cache.newItemDir()
    let cached = dir.appendingPathComponent("img.png")
    try Data("x".utf8).write(to: cached)
    let a = ShelfItem(kind: .file(cached), isCached: true), b = ShelfItem(kind: .text("keep"))
    store.add(a); store.add(b)
    store.selection = [a.id]
    let source = DragOutSource(store: store, ids: [a.id])
    source.ended(operation: [])
    #expect(store.items.count == 2)
    source.ended(operation: .copy)
    #expect(store.items == [b])
    #expect(store.selection.isEmpty)
    // Drop targets may still be reading it; deleted by clear/quit wipe.
    #expect(FileManager.default.fileExists(atPath: cached.path))
}

@Test func selectClickCommandShift() {
    let store = tempStore()
    let items = (0..<4).map { ShelfItem(kind: .text("\($0)")) }
    items.forEach { store.add($0) }
    let ids = items.map(\.id)
    store.select(ids[1], command: false, shift: false)
    #expect(store.selection == [ids[1]])
    store.select(ids[3], command: true, shift: false)
    #expect(store.selection == [ids[1], ids[3]])
    store.select(ids[3], command: true, shift: false)
    #expect(store.selection == [ids[1]])
    store.select(ids[0], command: false, shift: true) // anchor = ids[3]
    #expect(store.selection == Set(ids[0...3]))
    store.select(ids[2], command: false, shift: false)
    store.select(ids[0], command: false, shift: true)
    #expect(store.selection == Set(ids[0...2]))
    #expect(store.dragItems(for: ids[1]).map(\.id) == Array(ids[0...2]))
    #expect(store.dragItems(for: ids[3]).map(\.id) == [ids[3]])
}

@Test func removalHonorsKeepAfterDragOut() {
    #expect(DragOutSource.shouldRemove(operation: .copy, keepAfterDragOut: false))
    #expect(!DragOutSource.shouldRemove(operation: .copy, keepAfterDragOut: true))
    #expect(!DragOutSource.shouldRemove(operation: [], keepAfterDragOut: false))
    #expect(DragOutSource.shouldRemove(operation: .move, keepAfterDragOut: true))
    #expect(DragOutSource.shouldRemove(operation: .move, keepAfterDragOut: false))
}

@Test func movedCachedItemLeavesNoEmptyDir() throws {
    let store = tempStore()
    defer { store.cache.wipe() }
    let dir = try store.cache.newItemDir()
    let f = dir.appendingPathComponent("img.png")
    try Data("x".utf8).write(to: f)
    let a = ShelfItem(kind: .file(f), isCached: true)
    store.add(a)
    try FileManager.default.removeItem(at: f) // receiver moved it away
    DragOutSource(store: store, ids: [a.id]).ended(operation: .move)
    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

@Test func preferencesDefaults() {
    let d = UserDefaults(suiteName: "prefs-\(UUID())")!
    #expect(Preferences.autoShowEnabled(d) && Preferences.hotKeyOn(d) && !Preferences.keepAfterDrag(d))
    d.set(false, forKey: Preferences.autoShow)
    #expect(!Preferences.autoShowEnabled(d))
}
