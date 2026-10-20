import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Panel content view and drop destination. Lives on the panel's content view so drops work
/// while the app is inactive. Subclasses the hosting view so SwiftUI keeps sizing the panel.
final class DropReceiver<Content: View>: NSHostingView<Content> {
    var store: ShelfStore?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(PasteboardReader.types)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The app is never active, so the first click on the panel must reach SwiftUI controls.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard PasteboardReader.canAccept(sender.draggingPasteboard) else { return [] }
        setTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { setTargeted(false) }
    override func draggingEnded(_ sender: any NSDraggingInfo) { setTargeted(false) }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setTargeted(false)
        guard let store else { return false }
        return Self.ingest(PasteboardReader.read(sender.draggingPasteboard), into: store)
    }

    private func setTargeted(_ on: Bool) {
        guard let store, store.isDropTargeted != on else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.isDropTargeted = on }
    }

    /// Adds each incoming value; returns true if any item landed. Images are written to the cache.
    @discardableResult
    static func ingest(_ incoming: [PasteboardReader.Incoming], into store: ShelfStore) -> Bool {
        var added = false
        for value in incoming {
            switch value {
            case .file(let url): added = store.add(ShelfItem(kind: .file(url))) || added
            case .url(let url): added = store.add(ShelfItem(kind: .url(url))) || added
            case .text(let text): added = store.add(ShelfItem(kind: .text(text))) || added
            case .image(let data, let type):
                guard let (file, dir) = writeImage(data, type: type, cache: store.cache) else { continue }
                if store.add(ShelfItem(kind: .file(file), isCached: true)) { added = true } else { store.cache.remove(dir: dir) }
            }
        }
        return added
    }

    /// Writes PNG as-is (TIFF converted to PNG) to `root/<UUID>/Image <timestamp>.png`.
    private static func writeImage(_ data: Data, type: UTType, cache: ItemCache) -> (URL, URL)? {
        let png: Data? = type == .png ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        guard let png, let dir = try? cache.newItemDir() else { return nil }
        let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                                                 locale: .init(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current))
        let file = dir.appendingPathComponent("Image \(stamp).png")
        do { try png.write(to: file) } catch { cache.remove(dir: dir); return nil }
        return (file, dir)
    }
}
