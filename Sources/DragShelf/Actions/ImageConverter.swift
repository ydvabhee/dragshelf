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

    /// One output per source, in order. Cancel stops after the current image; finished outputs are returned.
    /// `taken`: lowercased names already on the shelf; outputs get a Finder-style " 2" instead of a duplicate name.
    static func run(_ urls: [URL], to type: UTType?, maxPixel: Int?, into dir: URL, taken: Set<String>,
                    progress: @Sendable (Double) -> Void) throws -> [URL] {
        var used = taken, outputs: [URL] = []
        for (i, url) in urls.enumerated() {
            if Task.isCancelled { break }
            progress(Double(i) / Double(urls.count))
            outputs.append(try convert(url, to: type, maxPixel: maxPixel, into: dir, used: &used))
        }
        return outputs
    }

    /// `type` nil = keep the source format (Resize; falls back to JPEG when ImageIO can't write it, e.g. WebP).
    /// `maxPixel` nil = full size. Never upscales. Names: `<base>.<ext>` or `<base> (<N>px).<ext>` (US-14 AC-3).
    static func convert(_ src: URL, to type: UTType?, maxPixel: Int?, into dir: URL, used: inout Set<String>) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw Failed(url: src) }
        let srcType = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        let outType = type ?? srcType.flatMap { writable.contains($0.identifier) ? $0 : nil } ?? .jpeg
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? .max, max(w, h)),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failed(url: src) }
        if outType == .jpeg, ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) {
            guard let flat = onWhite(image) else { throw Failed(url: src) }
            image = flat
        }

        let base = src.deletingPathExtension().lastPathComponent
        let ext = UTType(filenameExtension: src.pathExtension) == outType ? src.pathExtension
            : outType == .jpeg ? "jpg" : outType.preferredFilenameExtension ?? "img"
        let name = Zipper.uniqueName(base + (maxPixel.map { " (\($0)px)" } ?? "") + ".\(ext)", used: &used)
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
