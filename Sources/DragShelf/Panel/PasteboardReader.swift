import AppKit
import UniformTypeIdentifiers

/// Parses a pasteboard into shelf-ready values (ARCHITECTURE §4).
/// Per pasteboard item precedence: file URL > image data > web URL > string.
/// ponytail: file promises (`.promise`) arrive with T-05.
enum PasteboardReader {
    enum Incoming: Equatable {
        case file(URL)
        case image(Data, UTType)
        case url(URL)
        case text(String)
    }

    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff]

    static func read(_ pb: NSPasteboard) -> [Incoming] {
        (pb.pasteboardItems ?? []).compactMap { item in
            if let url = item.string(forType: .fileURL).flatMap(URL.init(string:)), url.isFileURL {
                return .file(url)
            }
            if let data = item.data(forType: .png) { return .image(data, .png) }
            if let data = item.data(forType: .tiff) { return .image(data, .tiff) }
            if let url = item.string(forType: .URL).flatMap(URL.init(string:)) { return .url(url) }
            if let text = item.string(forType: .string), !text.isEmpty { return .text(text) }
            return nil
        }
    }

    static func canAccept(_ pb: NSPasteboard) -> Bool {
        !read(pb).isEmpty
    }
}
