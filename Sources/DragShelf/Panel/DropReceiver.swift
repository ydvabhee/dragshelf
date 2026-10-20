import AppKit
import CryptoKit
import UniformTypeIdentifiers
import SwiftUI
import os

/// Panel content view and drop destination. Lives on the panel's content view so drops work
/// while the app is inactive. Subclasses the hosting view so SwiftUI keeps sizing the panel.
private let log = Logger(subsystem: "com.abhishekyadav.DragShelf", category: "drop")
private let promiseQueue = OperationQueue()

final class DropReceiver<Content: View>: NSHostingView<Content> {
    var store: ShelfStore?
    /// A drop landed (keeps an auto-shown shelf open, T-08 AC-3).
    var onDrop: (() -> Void)?
    /// A file promise from that drop failed (e.g. offline Mail attachment).
    var onPromiseFailed: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(PasteboardReader.types)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The app is never active, so the first click on the panel must reach SwiftUI controls.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Any click turns the panel key (never activates the app) so Esc/Space/Delete/arrows reach it.
    override var needsPanelToBecomeKey: Bool { true }

    /// Cmd-C copies the selection (panel is key after a tile click). `copy(_:)` covers a menu-routed Cmd-C.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "c", store?.selection.isEmpty == false
        else { return super.performKeyEquivalent(with: event) }
        copy(nil)
        return true
    }

    @objc func copy(_ sender: Any?) {
        guard let store else { return }
        DragOutSource.copy(store.selectedItems)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        setTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    /// Our own drag-outs are rejected: dropping back on the shelf is a no-op.
    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        !(sender.draggingSource is DragOutSource) && PasteboardReader.canAccept(sender.draggingPasteboard)
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { setTargeted(false) }
    override func draggingEnded(_ sender: any NSDraggingInfo) { setTargeted(false) }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setTargeted(false)
        guard let store, accepts(sender) else { return false }
        let failed = onPromiseFailed
        guard Self.ingest(PasteboardReader.read(sender.draggingPasteboard), into: store,
                          onPromiseFailed: { failed?() }) else { return false }
        onDrop?()
        return true
    }

    private func setTargeted(_ on: Bool) {
        guard let store, store.isDropTargeted != on else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { store.isDropTargeted = on }
    }

    /// Adds each incoming value; returns true if any item landed. Images are written to the cache.
    @discardableResult
    static func ingest(_ incoming: [PasteboardReader.Incoming], into store: ShelfStore,
                       onPromiseFailed: @escaping () -> Void = {}) -> Bool {
        var added = false
        for value in incoming {
            switch value {
            case .file(let url): added = store.add(ShelfItem(kind: .file(url))) || added
            case .url(let url): added = store.add(ShelfItem(kind: .url(url))) || added
            case .text(let text): added = store.add(ShelfItem(kind: .text(text))) || added
            case .promise(let receiver):
                // Item lands asynchronously, so a promise alone does not count as added now.
                receive(receiver, into: store, onFail: onPromiseFailed)
                added = true
            case .image(let data, let type):
                guard let (file, dir) = writeImage(data, type: type, cache: store.cache) else { continue }
                let item = ShelfItem(kind: .file(file), isCached: true, contentHash: SHA256.hash(data: data))
                if store.add(item) { added = true } else { store.cache.remove(dir: dir) }
            }
        }
        return added
    }

    /// Receives a file promise into `root/<UUID>/` on a background queue, then adds the item on main.
    private static func receive(_ receiver: NSFilePromiseReceiver, into store: ShelfStore, onFail: @escaping () -> Void) {
        let cache = store.cache, generation = store.generation
        guard let dir = try? cache.newItemDir() else { log.error("promise: cannot create cache dir"); onFail(); return }
        receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
            Task { @MainActor in
                if !finishPromise(url: error == nil ? url : nil, error: error, dir: dir, store: store,
                                  generation: generation) { onFail() }
            }
        }
    }

    /// Adds the received file as a cached item; on failure, duplicate, or a Clear since the drop
    /// (`generation` changed) removes the dir and anything written into it. Returns false when no item landed.
    @discardableResult
    static func finishPromise(url: URL?, error: (any Error)? = nil, dir: URL, store: ShelfStore, generation: Int) -> Bool {
        if let url, generation == store.generation, store.add(ShelfItem(kind: .file(url), isCached: true)) { return true }
        if let error { log.error("promise failed: \(error.localizedDescription, privacy: .public)") }
        store.cache.remove(dir: dir)
        return false
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
