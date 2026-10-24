import AppKit
import SwiftUI
import Testing
@testable import DragShelf

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TextFileTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func nameFromFirstLine() {
    #expect(TextFile.name(for: "Hello world\nsecond") == "Hello world.txt")
    #expect(TextFile.name(for: "\n  \n  Notes: a/b \u{7}\r\nx") == "Notes ab.txt")
    #expect(TextFile.name(for: "...hidden") == "hidden.txt")
    #expect(TextFile.name(for: "") == "Text.txt")
    #expect(TextFile.name(for: " / : \n\t") == "Text.txt")
    #expect(TextFile.name(for: "\u{202E}evil") == "evil.txt")  // bidi override is a control (format) character
    #expect(TextFile.name(for: String(repeating: "é", count: 80)) == String(repeating: "é", count: 60) + ".txt")
    #expect(TextFile.name(for: String(repeating: "👨‍👩‍👧‍👦", count: 60)).utf8.count <= 255)
}

@Test func decodesBOMsAndFallsBack() {
    let s = "Grüße ✓"
    #expect(TextFile.decode(Data(s.utf8)) == s)
    #expect(TextFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data(s.utf8)) == s)
    #expect(TextFile.decode(Data([0xFF, 0xFE]) + s.data(using: .utf16LittleEndian)!) == s)
    #expect(TextFile.decode(Data([0xFE, 0xFF]) + s.data(using: .utf16BigEndian)!) == s)
    #expect(TextFile.decode(Data([0x63, 0x61, 0x66, 0xE9])) == "café")  // Latin-1, invalid UTF-8
}

@Test func readHonorsSizeLimit() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let small = dir.appendingPathComponent("a.txt"), big = dir.appendingPathComponent("b.txt"), empty = dir.appendingPathComponent("c.txt")
    try Data("hi".utf8).write(to: small)
    try Data(count: TextFile.maxBytes + 1).write(to: big)
    try Data().write(to: empty)
    #expect(TextFile.read(small) == "hi")
    #expect(TextFile.fits(small) && !TextFile.fits(big))
    #expect(TextFile.read(big) == nil)
    #expect(TextFile.read(empty) == nil)
    #expect(TextFile.isPlainText(ShelfItem(kind: .file(small))))
    #expect(!TextFile.isPlainText(ShelfItem(kind: .file(dir.appendingPathComponent("gone.txt")))))
    #expect(!TextFile.isPlainText(ShelfItem(kind: .text("x"))))
}

@Test func useAsTextAndSaveAsText() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ShelfStore(cache: ItemCache(root: dir.appendingPathComponent("cache")))
    let txt = dir.appendingPathComponent("note.txt")
    try ("Line one\nLine two".data(using: .utf16)!).write(to: txt)
    let file = ShelfItem(kind: .file(txt)), text = ShelfItem(kind: .text("Line one\nLine two"))
    store.add(file)
    store.useAsText([file])
    #expect(store.items.count == 2)
    #expect(store.selectedItems.map(\.kind) == [.text("Line one\nLine two")])
    store.useAsText([file])  // same text again: selects the existing item
    #expect(store.items.count == 2)

    store.saveAsText([text, file])
    store.saveAsText([text])
    let names = store.items.compactMap { if case .file(let url) = $0.kind, $0.isCached { url.lastPathComponent } else { nil } }
    #expect(names == ["Line one.txt", "Line one 2.txt"])
    #expect(store.items.contains { $0.kind == text.kind })  // text item stays
    let saved = try #require(store.selectedItems.first)
    guard case .file(let url) = saved.kind else { Issue.record("not a file"); return }
    #expect(try Data(contentsOf: url) == Data("Line one\nLine two".utf8))
}

@Test func providerOffersStringAndPromise() {
    let provider = TextPromiseProvider(text: "Hello\nworld")
    let types = provider.writableTypes(for: NSPasteboard(name: .drag))
    #expect(types.first == .string)
    #expect(types.count > 1)  // plus the file promise types
    #expect(provider.pasteboardPropertyList(forType: .string) as? String == "Hello\nworld")
    #expect(provider.filePromiseProvider(provider, fileNameForType: provider.fileType) == "Hello.txt")
    #expect(provider.fileType == "public.plain-text")
    let pb = NSPasteboard(name: .init("test-provider-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    #expect(pb.writeObjects([provider]))
    #expect(pb.string(forType: .string) == "Hello\nworld")  // what a text field reads on drop
    #expect(DragOutSource.dragWriter(for: ShelfItem(kind: .text("x"))) is TextPromiseProvider)
    #expect(DragOutSource.writer(for: ShelfItem(kind: .text("x"))) as? NSString == "x")  // Cmd-C and Share stay string
}

/// ADR-016: AppKit calls the promise writer on its operation queue; writing off main must not trap.
@Test func providerWritesExactBytesOffMain() async throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = "Grüße\r\n✓ ok", dest = dir.appendingPathComponent("out.txt")
    let provider = TextPromiseProvider(text: text)
    let errors: [Bool] = await withCheckedContinuation { done in
        DispatchQueue.global().async {
            provider.filePromiseProvider(provider, writePromiseTo: dest) { first in
                provider.filePromiseProvider(provider, writePromiseTo: dest) { second in  // never overwrites
                    done.resume(returning: [first != nil, second != nil])
                }
            }
        }
    }
    #expect(errors == [false, true])
    #expect(try Data(contentsOf: dest) == Data(text.utf8))
}

@Test @MainActor func repeatPasteCancelsMessageTimer() {
    let pb = NSPasteboard(name: .init("test-timer-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    let receiver = DropReceiver(rootView: EmptyView())
    receiver.store = ShelfStore(cache: ItemCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("timer-\(UUID())")))
    receiver.pasteboard = pb
    receiver.pasteItems()
    let first = receiver.messageTimer
    #expect(first != nil)
    receiver.pasteItems()
    #expect(first?.isCancelled == true)
    #expect(receiver.messageTimer?.isCancelled == false)
    pb.setString("x", forType: .string)
    receiver.pasteItems()
    #expect(receiver.messageTimer?.isCancelled == true)
}
