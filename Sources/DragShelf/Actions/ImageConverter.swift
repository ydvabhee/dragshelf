import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Convert To / Resize (V2-03, ADR-014): ImageIO only. Writes only into `dir`; sources are only read.
/// Output is upright (orientation applied), keeps the color profile, and carries no source metadata (OQ-21).
nonisolated enum ImageConverter {
    struct Failed: Error { let url: URL }

    /// Resize presets: longest edge in px (OQ-23).
    static let presets = [512, 1024, 2048, 3840]
    static let quality = 0.85
    /// Convert To targets this Mac can write (HEIC needs encoder support). No WebP/AVIF (OQ-22).
    static let writableTypes: [UTType] = [.heic, .jpeg, .png, .tiff].filter { writable.contains($0.identifier) }
    private static let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
    private static let readable = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    /// By extension only (no disk read): menus call this on every redraw.
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension).map { readable.contains($0.identifier) } ?? false
    }

    /// One output per source, in order. A bad image is skipped and counted in `failed`; the rest still convert.
    /// Cancel stops after the current image; finished outputs are returned.
    /// `taken`: lowercased names already on the shelf; outputs get a Finder-style " 2" instead of a duplicate name.
    static func run(_ urls: [URL], to type: UTType?, maxPixel: Int?, resize: ResizeSpec? = nil, into dir: URL,
                    taken: Set<String>, progress: @Sendable (Double) -> Void) -> (outputs: [URL], failed: Int) {
        var used = taken, outputs: [URL] = [], failed = 0
        for (i, url) in urls.enumerated() {
            if Task.isCancelled { break }
            progress(Double(i) / Double(urls.count))
            if let out = try? convert(url, to: type, maxPixel: maxPixel, resize: resize, into: dir, used: &used) {
                outputs.append(out)
            } else {
                failed += 1
            }
        }
        return (outputs, failed)
    }

    /// `type` nil = keep the source format (Resize; falls back to JPEG when ImageIO can't write it, e.g. WebP).
    /// `maxPixel` nil = full size. Never upscales. Names: `<base>.<ext>` or `<base> (<N>px).<ext>` (US-14 AC-3).
    /// `resize` (Custom…, V2-05) wins over `maxPixel`: exact output size, may upscale, named `<base> (<W>×<H>).<ext>`.
    static func convert(_ src: URL, to type: UTType?, maxPixel: Int?, resize: ResizeSpec? = nil, into dir: URL,
                        used: inout Set<String>) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              case let (w, h)? = size(props)
        else { throw Failed(url: src) }
        let target = resize?.size(width: w, height: h)
        if let target, ResizeSpec.limitError(target) != nil { throw Failed(url: src) }
        let srcType = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        let outType = type ?? srcType.flatMap { writable.contains($0.identifier) ? $0 : nil } ?? .jpeg
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target.map { thumbnailEdge(for: $0, width: w, height: h) }
                ?? min(maxPixel ?? .max, max(w, h)),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failed(url: src) }
        if let target, target != (image.width, image.height) {
            guard let scaled = scaled(image, to: target) else { throw Failed(url: src) }
            image = scaled
        }
        if outType == .jpeg, ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) {
            guard let flat = onWhite(image) else { throw Failed(url: src) }
            image = flat
        }

        let base = src.deletingPathExtension().lastPathComponent
        let ext = UTType(filenameExtension: src.pathExtension) == outType ? src.pathExtension
            : outType == .jpeg ? "jpg" : outType.preferredFilenameExtension ?? "img"
        let suffix = target.map { " (\($0.width)×\($0.height))" } ?? maxPixel.map { " (\($0)px)" } ?? ""
        let name = Zipper.uniqueName(base + suffix + ".\(ext)", used: &used)
        let out = dir.appendingPathComponent(name)
        // Image only, no source properties: strips EXIF/GPS/TIFF; the color space travels with `image`.
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, outType.identifier as CFString, 1, nil) else {
            throw Failed(url: src)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw Failed(url: src)
        }
        return out
    }

    /// Upright pixel size from image properties: orientations 5–8 rotate by 90°, so width and height swap.
    static func size(_ props: [CFString: Any]) -> (width: Int, height: Int)? {
        guard let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (props[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 ? (h, w) : (w, h)
    }

    /// Upright pixel size of the image at `url` (header only); nil when unreadable. The custom resize form uses it.
    static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        CGImageSourceCreateWithURL(url as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            .flatMap(size)
    }

    /// Longest edge to decode at: just enough for `target` in both directions (a stretch may need more in one),
    /// never above the source (ImageIO thumbnails can't upscale; `scaled` does that).
    static func thumbnailEdge(for target: (width: Int, height: Int), width w: Int, height h: Int) -> Int {
        let need = max(Double(target.width) / Double(w), Double(target.height) / Double(h))
        return min(max(w, h), Int((Double(max(w, h)) * need).rounded(.up)))
    }

    /// Exact `size` with high-quality interpolation (up or down). Keeps an RGB color profile (else sRGB), 16-bit
    /// depth, and alpha only when the source has it.
    private static func scaled(_ image: CGImage, to size: (width: Int, height: Int)) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height,
                                  bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx.makeImage()
    }

    /// JPEG has no alpha: draw onto white so transparent areas don't turn black (US-14 AC-5).
    private static func onWhite(_ image: CGImage) -> CGImage? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? srgb
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}

/// Resize ▸ Custom… (V2-05): what the form asked for. Pure size math, shared by the form and the converter.
nonisolated enum ResizeSpec: Hashable, Sendable {
    /// Target box in px; nil = that side is free. `fit`: scale each image into the box keeping its aspect
    /// (several images, lock on). Not `fit` with both sides set: exactly that size (one image, or lock off).
    case pixels(width: Int?, height: Int?, fit: Bool)
    /// Percent of each side.
    case percent(width: Int, height: Int)

    static let pixelRange = 1...16384, percentRange = 1...400
    // ponytail: fixed output caps (a 16384² RGBA bitmap is already 1 GB); raise only with tiled/streamed drawing.
    static let maxSide = 16384, maxPixels = 100_000_000

    /// Output over the caps (per side or total): the form's error text; the converter refuses it too.
    static func limitError(_ size: (width: Int, height: Int)) -> String? {
        if size.width > maxSide || size.height > maxSide { return "Too large: max \(maxSide) px per side" }
        return size.width * size.height > maxPixels ? "Too large: max 100 megapixels" : nil
    }

    /// First cap error over a batch of upright source sizes (Pixels and Percent alike), checked before running.
    func limitError(for sizes: [(width: Int, height: Int)]) -> String? {
        sizes.lazy.compactMap { ResizeSpec.limitError(self.size(width: $0.width, height: $0.height)) }.first
    }

    /// Output size for a `w`×`h` (upright) image. One side set: the other follows the image's aspect.
    /// Custom sizes may upscale (AC-4).
    func size(width w: Int, height h: Int) -> (width: Int, height: Int) {
        func scaled(_ sx: Double, _ sy: Double) -> (width: Int, height: Int) {
            (max(1, Int((Double(w) * sx).rounded())), max(1, Int((Double(h) * sy).rounded())))
        }
        switch self {
        case .percent(let pw, let ph): return scaled(Double(pw) / 100, Double(ph) / 100)
        case .pixels(let tw?, let th?, false): return (tw, th)
        case .pixels(let tw, let th, _):
            let s = [tw.map { Double($0) / Double(w) }, th.map { Double($0) / Double(h) }].compactMap(\.self).min() ?? 1
            return scaled(s, s)
        }
    }

    /// Aspect lock: the other field's value when one side changes from `from` to `value` (other side `to`).
    static func linked(_ value: Int, from: Int, to: Int) -> Int {
        max(1, Int((Double(value) * Double(to) / Double(from)).rounded()))
    }

    /// Form text → spec, or the one-line error (AC-5). Whole numbers only; Percent with one side empty keeps the
    /// aspect (the empty side copies the other).
    static func parse(width: String, height: String, percent: Bool, fit: Bool) -> Result<ResizeSpec, Invalid> {
        let range = percent ? percentRange : pixelRange
        var values: [Int?] = []
        for text in [width, height].map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if text.isEmpty { values.append(nil); continue }
            guard let n = Int(text), range.contains(n) else {
                return .failure(Invalid(message: percent ? "Enter a whole number from 1 to 400 %."
                                                         : "Enter a whole number from 1 to 16384 px."))
            }
            values.append(n)
        }
        let (w, h) = (values[0], values[1])
        guard w != nil || h != nil else { return .failure(Invalid(message: "Enter a width or a height.")) }
        if percent, let p = w ?? h { return .success(.percent(width: w ?? p, height: h ?? p)) }
        return .success(.pixels(width: w, height: h, fit: fit))
    }

    struct Invalid: Error, Equatable { let message: String }
}
