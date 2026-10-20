import AppKit
import SwiftUI
import Testing
@testable import DragShelf

private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pb = NSPasteboard(name: .init("test-\(UUID())"))
    defer { pb.releaseGlobally() }
    try body(pb)
}

private func png() throws -> Data {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    return try #require(rep.representation(using: .png, properties: [:]))
}

@Test func fileURLsReadAsFiles() {
    withPasteboard { pb in
        pb.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(fileURLWithPath: "/tmp") as NSURL])
        #expect(PasteboardReader.read(pb) == [.file(URL(fileURLWithPath: "/tmp/a.txt")), .file(URL(fileURLWithPath: "/tmp"))])
    }
}

@Test func webURLReadsAsURL() {
    withPasteboard { pb in
        let url = URL(string: "https://example.com/x")!
        pb.writeObjects([url as NSURL])
        #expect(PasteboardReader.read(pb) == [.url(url)])
    }
}

@Test func stringReadsAsText() {
    withPasteboard { pb in
        pb.writeObjects(["hello\nworld" as NSString])
        #expect(PasteboardReader.read(pb) == [.text("hello\nworld")])
    }
}

@Test func imageDataReadsAsImage() throws {
    let data = try png()
    withPasteboard { pb in
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        pb.writeObjects([item])
        #expect(PasteboardReader.read(pb) == [.image(data, .png)])
    }
    try withPasteboard { pb in
        let tiff = try #require(NSBitmapImageRep(data: data)?.tiffRepresentation)
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        pb.writeObjects([item])
        #expect(PasteboardReader.read(pb) == [.image(tiff, .tiff)])
    }
}

@Test func imageBeatsURLInSameItem() throws {
    let data = try png()
    withPasteboard { pb in
        let item = NSPasteboardItem()
        item.setString("https://example.com/pic.png", forType: .URL)
        item.setData(data, forType: .png)
        pb.writeObjects([item])
        #expect(PasteboardReader.read(pb) == [.image(data, .png)])
    }
}

@Test func emptyPasteboardRejected() {
    withPasteboard { pb in
        pb.clearContents()
        #expect(!PasteboardReader.canAccept(pb))
    }
}

@Test func ingestCachesImageAndAddsOthers() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DragShelfTest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ShelfStore(cache: ItemCache(root: root))
    let image = try png()
    let added = DropReceiver<EmptyView>.ingest(
        [.image(image, .png), .url(URL(string: "https://a.com")!), .text("hi")], into: store)
    #expect(added)
    // Image hashing runs off main; a drop queued behind it keeps drop order (T-11 AC-7).
    DropReceiver<EmptyView>.ingest([.text("later")], into: store)
    await pendingIngest?.value
    #expect(store.items.dropFirst().map(\.kind) == [.url(URL(string: "https://a.com")!), .text("hi"), .text("later")])
    guard case .file(let file) = store.items.first?.kind else { Issue.record("not file"); return }
    #expect(store.items[0].isCached && file.pathExtension == "png" && FileManager.default.fileExists(atPath: file.path))
    #expect(file.path.hasPrefix(root.path))
    // Same image again replaces the first one (moved to the end, old cache dir gone).
    DropReceiver<EmptyView>.ingest([.image(image, .png)], into: store)
    await pendingIngest?.value
    #expect(store.items.count == 4 && store.items.last?.isCached == true)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}
