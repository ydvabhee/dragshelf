import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DragShelf

private let fm = FileManager.default

private func tempDir(_ name: String) throws -> URL {
    let dir = fm.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func rm(_ urls: URL...) { urls.forEach { try? fm.removeItem(at: $0) } }

/// `width`×`height` sRGB image; `clear` = fully transparent, else an opaque gradient.
private func makeImage(_ width: Int, _ height: Int, clear: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if !clear {
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 3))
    }
    return ctx.makeImage()!
}

private func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
}

private func info(_ url: URL) -> (type: String?, width: Int, height: Int, props: [CFString: Any]) {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    return (CGImageSourceGetType(src) as String?, props[kCGImagePropertyPixelWidth] as? Int ?? 0,
            props[kCGImagePropertyPixelHeight] as? Int ?? 0, props)
}

@Test func writableTypesAreTheFourFormatsOnly() {
    #expect(ImageConverter.writableTypes.allSatisfy { [UTType.heic, .jpeg, .png, .tiff].contains($0) })
    #expect([UTType.jpeg, .png, .tiff].allSatisfy { ImageConverter.writableTypes.contains($0) })
    #expect(ShelfAction.conversions.map(\.menuTitle).allSatisfy { ["HEIC", "JPEG", "PNG", "TIFF"].contains($0) })
    #expect(ShelfAction.resizes.map(\.menuTitle) == ["512 px", "1024 px", "2048 px", "3840 px"])
    #expect(ImageConverter.isImage(URL(fileURLWithPath: "/x/photo.webp"))) // WebP input (AC-7)
    #expect(!ImageConverter.isImage(URL(fileURLWithPath: "/x/notes.txt")))
}

@Test func convertsToEachFormatAndResizesWithoutUpscaling() throws {
    let dir = try tempDir("ImageTests"), src = dir.appendingPathComponent("big.png")
    let small = dir.appendingPathComponent("small.png"), out = try tempDir("ImageTests-out")
    defer { rm(dir, out) }
    write(makeImage(4000, 3000), to: src, type: .png)
    write(makeImage(300, 200), to: small, type: .png)
    var used = Set<String>()
    for type in ImageConverter.writableTypes {
        let url = try ImageConverter.convert(src, to: type, maxPixel: nil, into: out, used: &used)
        let got = info(url)
        #expect(got.type == type.identifier && got.width == 4000 && got.height == 3000)
    }
    for px in ImageConverter.presets {
        let url = try ImageConverter.convert(src, to: nil, maxPixel: px, into: out, used: &used)
        let got = info(url)
        #expect(got.type == UTType.png.identifier && max(got.width, got.height) == px)
        #expect(url.lastPathComponent == "big (\(px)px).png")
    }
    let kept = info(try ImageConverter.convert(small, to: nil, maxPixel: 512, into: out, used: &used))
    #expect(kept.width == 300 && kept.height == 200)
    #expect(try ImageConverter.convert(src, to: .jpeg, maxPixel: nil, into: out, used: &used).lastPathComponent == "big 2.jpg")
}

@Test func transparentPNGToJPEGIsWhite() throws {
    let dir = try tempDir("ImageTests"), src = dir.appendingPathComponent("clear.png")
    defer { rm(dir) }
    write(makeImage(16, 16, clear: true), to: src, type: .png)
    var used = Set<String>()
    let url = try ImageConverter.convert(src, to: .jpeg, maxPixel: nil, into: dir, used: &used)
    let image = try #require(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil))
    var pixel = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1)) // whole image, corners included, averaged
    #expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245)
}

@Test func stripsMetadataAndAppliesOrientation() throws {
    let dir = try tempDir("ImageTests"), src = dir.appendingPathComponent("phone.jpg")
    defer { rm(dir) }
    write(makeImage(40, 20), to: src, type: .jpeg, properties: [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.85, kCGImagePropertyGPSLatitudeRef: "N",
                                        kCGImagePropertyGPSLongitude: 2.35, kCGImagePropertyGPSLongitudeRef: "E"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Camera Co", kCGImagePropertyTIFFModel: "X1"],
    ])
    #expect(info(src).props[kCGImagePropertyGPSDictionary] != nil) // the fixture really has GPS
    var used = Set<String>()
    let got = info(try ImageConverter.convert(src, to: .jpeg, maxPixel: nil, into: dir, used: &used))
    #expect(got.props[kCGImagePropertyGPSDictionary] == nil)
    #expect((got.props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    #expect((got.props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
    #expect(got.width == 20 && got.height == 40) // upright: width/height swapped
    #expect([nil, 1].contains(got.props[kCGImagePropertyOrientation] as? Int))
}

@Test func cancelStopsAfterCurrentImageAndKeepsFinished() async throws {
    let dir = try tempDir("ImageTests"), out = try tempDir("ImageTests-out")
    defer { rm(dir, out) }
    let urls = (0..<5).map { dir.appendingPathComponent("p\($0).png") }
    urls.forEach { write(makeImage(64, 64), to: $0, type: .png) }
    // Cancel while image 2 is about to start: it still finishes, 3 and 4 are not made.
    let outputs = try await Task {
        try ImageConverter.run(urls, to: .jpeg, maxPixel: nil, into: out, taken: []) { p in
            if p >= 0.4 { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }.value
    #expect(outputs.map(\.lastPathComponent) == ["p0.jpg", "p1.jpg", "p2.jpg"])
    #expect(Set(try fm.contentsOfDirectory(atPath: out.path)) == ["p0.jpg", "p1.jpg", "p2.jpg"])
}

@Test func convertSkipsNonImagesAvoidsShelfNamesSelectsOutputs() async throws {
    let store = ShelfStore(cache: ItemCache(root: try tempDir("ImageTests-cache")))
    let dir = try tempDir("ImageTests"), other = try tempDir("ImageTests-other")
    defer { rm(dir, other, store.cache.root) }
    let png = dir.appendingPathComponent("a.png"), txt = dir.appendingPathComponent("a.txt")
    let sameName = other.appendingPathComponent("a.jpg")
    write(makeImage(32, 32), to: png, type: .png)
    write(makeImage(8, 8), to: sameName, type: .jpeg)
    try Data("hi".utf8).write(to: txt)
    [png, txt, sameName].forEach { store.add(ShelfItem(kind: .file($0))) }
    store.add(ShelfItem(kind: .text("hi")))
    let targets = Array(store.items.prefix(2)) + [store.items[3]] // a.png, a.txt, text
    #expect(ShelfAction.resize(512).applicable(targets).count == 1)
    await store.actions.run(.convert(.jpeg), on: targets, in: store)?.value
    #expect(store.items.count == 5)
    let made = try #require(store.items.last)
    #expect(made.isCached && store.selection == [made.id])
    if case .file(let url) = made.kind { #expect(url.lastPathComponent == "a 2.jpg") } else { Issue.record("not a file") }
    #expect(store.actions.message == "Skipped 2 items" && fm.fileExists(atPath: png.path))
}

@Test func runnerKeepsFinishedImagesOnCancel() async throws {
    let store = ShelfStore(cache: ItemCache(root: try tempDir("ImageTests-cache"))), dir = try tempDir("ImageTests")
    defer { rm(dir, store.cache.root) }
    let first = dir.appendingPathComponent("p0.png")
    write(makeImage(3000, 3000), to: first, type: .png)
    for i in 0..<20 {
        let url = dir.appendingPathComponent("p\(i).png")
        if i > 0 { try fm.copyItem(at: first, to: url) } // APFS clone: instant
        store.add(ShelfItem(kind: .file(url)))
    }
    let job = try #require(store.actions.run(.convert(.heic), on: store.items, in: store))
    while (store.actions.progress ?? 0) == 0, store.actions.running != nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(store.actions.step?.hasSuffix(" of 20") == true)
    store.actions.cancel()
    await job.value
    let added = store.items.count - 20
    #expect((1..<20).contains(added) && store.selection.count == added && store.actions.message == nil)
}
