import AppKit
import UniformTypeIdentifiers
import SwiftUI
import os

/// Panel content view and drop destination. Lives on the panel's content view so drops work
/// while the app is inactive. Subclasses the hosting view so SwiftUI keeps sizing the panel.
private let log = Logger(subsystem: "com.abhishekyadav.DragShelf", category: "drop")
private let promiseQueue = OperationQueue()

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

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        PasteboardReader.canAccept(sender.draggingPasteboard) ? .copy : []
    }
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
            case .promise(let receiver):
                // Item lands asynchronously, so a promise alone does not count as added now.
                receive(receiver, into: store)
                added = true
            case .image(let data, let type):
                guard let (file, dir) = writeImage(data, type: type, cache: store.cache) else { continue }
                if store.add(ShelfItem(kind: .file(file), isCached: true)) { added = true } else { store.cache.remove(dir: dir) }
            }
        }
        return added
    }

    /// Receives a file promise into `root/<UUID>/` on a background queue, then adds the item on main.
    private static func receive(_ receiver: NSFilePromiseReceiver, into store: ShelfStore) {
        let cache = store.cache
        guard let dir = try? cache.newItemDir() else { log.error("promise: cannot create cache dir"); return }
        receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
            Task { @MainActor in finishPromise(url: error == nil ? url : nil, error: error, dir: dir, store: store) }
        }
    }

    /// Adds the received file as a cached item; on failure or duplicate removes the (now empty) dir.
    static func finishPromise(url: URL?, error: (any Error)? = nil, dir: URL, store: ShelfStore) {
        if let url, store.add(ShelfItem(kind: .file(url), isCached: true)) { return }
        if let error { log.error("promise failed: \(error.localizedDescription, privacy: .public)") }
        store.cache.remove(dir: dir)
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
