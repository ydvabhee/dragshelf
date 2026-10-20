import AppKit
import UniformTypeIdentifiers

/// Parses a pasteboard into shelf-ready values (ARCHITECTURE §4).
/// Per pasteboard item precedence: file URL > image data > web URL > string.
/// Real file URLs on the pasteboard win; promises are used only when there are none.
enum PasteboardReader {
    enum Incoming: Equatable {
        case file(URL)
        case promise(NSFilePromiseReceiver)
        case image(Data, UTType)
        case url(URL)
        case text(String)
    }

    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static func read(_ pb: NSPasteboard) -> [Incoming] {
        let parsed = parseItems(pb)
        if parsed.contains(where: { if case .file = $0 { true } else { false } }) { return parsed }
        let promises = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
        return promises.isEmpty ? parsed : promises.map(Incoming.promise)
    }

    private static func parseItems(_ pb: NSPasteboard) -> [Incoming] {
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
