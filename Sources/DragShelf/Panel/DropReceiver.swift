import AppKit
import CryptoKit
import UniformTypeIdentifiers
import SwiftUI
import os

/// Panel content view and drop destination. Lives on the panel's content view so drops work
/// while the app is inactive. Subclasses the hosting view so SwiftUI keeps sizing the panel.
private let log = Logger(subsystem: "com.abhishekyadav.DragShelf", category: "drop")
private let promiseQueue = OperationQueue()
/// Tail of the drops whose items land asynchronously (image hashing). Later drops chain behind it so items
/// keep drop order. Tests await it.
@MainActor var pendingIngest: Task<Void, Never>?
@MainActor private var pendingIngestCount = 0

final class DropReceiver<Content: View>: NSHostingView<Content> {
    var store: ShelfStore?
    /// A drop landed (keeps an auto-shown shelf open, T-08 AC-3).
    var onDrop: (() -> Void)?
    /// A file promise from that drop failed (e.g. offline Mail attachment).
    var onPromiseFailed: (@MainActor () -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(PasteboardReader.types)
        // The controller sizes the panel from `fittingSize`; content must not pin the window size, or edge
        // resizing is blocked (T-16 AC-4). Low priorities: below the window's resize/stay-put priorities.
        sizingOptions = [.intrinsicContentSize]
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.defaultLow, for: axis)
            setContentCompressionResistancePriority(.defaultLow, for: axis)
        }
        // No focus ring when the panel turns key; clip to the shelf's rounded shape so nothing square
        // (window shadow included) shows past the corners (T-16 AC-1, AC-2).
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = shelfCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // ponytail: explicit empty deinit works around a swift-frontend 6.3 -O crash (EarlyPerfInliner on the
    // synthesized deinit of this generic hosting-view subclass); remove once the toolchain is fixed.
    nonisolated deinit {}

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
        DragOutSource.copy(store.selectedItems.filter { !store.missing(id: $0.id) })
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
        store.showRecent = false  // any accepted drop returns to the grid (T-20 AC-8), even duplicate-only
        let failed = onPromiseFailed
        guard Self.ingest(PasteboardReader.read(sender.draggingPasteboard), into: store,
                          onPromiseFailed: { failed?() }) else { return false }
        onDrop?()
        return true
    }

    private func setTargeted(_ on: Bool) {
        guard let store, store.isDropTargeted != on else { return }
        // Reduce Motion: fade the highlight instead of springing it (T-11 AC-6).
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0.1)) {
            store.isDropTargeted = on
        }
    }

    /// Adds each incoming value in order; returns true if any item landed or may still land.
    /// Image data is converted, written to the cache, and hashed off the main actor (T-11 AC-7); a drop with
    /// an image, or any drop while one is in flight, lands asynchronously. `onPromiseFailed` fires when
    /// nothing from an asynchronous drop landed.
    @discardableResult
    static func ingest(_ incoming: [PasteboardReader.Incoming], into store: ShelfStore,
                       onPromiseFailed: @escaping @MainActor () -> Void = {}) -> Bool {
        let hasImage = incoming.contains { if case .image = $0 { true } else { false } }
        if !hasImage, pendingIngestCount == 0 {
            return incoming.reduce(false) { add($1, into: store, onPromiseFailed: onPromiseFailed) || $0 }
        }
        let previous = pendingIngest, generation = store.generation
        pendingIngestCount += 1
        pendingIngest = Task {
            await previous?.value
            var landed = false
            // A Clear after the drop drops what has not landed yet, like a late file promise.
            for value in incoming where generation == store.generation {
                guard case .image(let data, let type) = value else {
                    landed = add(value, into: store, onPromiseFailed: onPromiseFailed) || landed
                    continue
                }
                let cache = store.cache
                guard let (file, dir, hash) = await Task.detached(operation: { prepareImage(data, type: type, cache: cache) }).value
                else { continue }
                if generation == store.generation,
                   store.add(ShelfItem(kind: .file(file), isCached: true, contentHash: hash)) { landed = true }
                else { cache.remove(dir: dir) }
            }
            pendingIngestCount -= 1
            if !landed { onPromiseFailed() }
        }
        return !incoming.isEmpty
    }

    /// Adds one non-image value now (a promise starts receiving and counts as landed).
    private static func add(_ value: PasteboardReader.Incoming, into store: ShelfStore,
                            onPromiseFailed: @escaping @MainActor () -> Void) -> Bool {
        switch value {
        case .file(let url): return store.add(ShelfItem(kind: .file(url)))
        case .url(let url): return store.add(ShelfItem(kind: .url(url)))
        case .text(let text): return store.add(ShelfItem(kind: .text(text)))
        case .promise(let receiver):
            receive(receiver, into: store, onFail: onPromiseFailed)
            return true
        case .image: return false
        }
    }

    /// Receives a file promise into `root/<UUID>/` on a background queue, then adds the item on main.
    private static func receive(_ receiver: NSFilePromiseReceiver, into store: ShelfStore, onFail: @escaping @MainActor () -> Void) {
        let cache = store.cache, generation = store.generation
        guard let dir = try? cache.newItemDir() else { log.error("promise: cannot create cache dir"); onFail(); return }
        receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue,
                                      reader: promiseHandler(dir: dir, store: store, generation: generation, onFail: onFail))
    }

    /// The promise reader. AppKit calls it on `promiseQueue`, so it must be nonisolated: a MainActor-inferred
    /// closure traps on the runtime isolation check before its body runs. Hops to main to add the item.
    nonisolated static func promiseHandler(dir: URL, store: ShelfStore, generation: Int,
                                           onFail: @escaping @MainActor () -> Void) -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in
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
}

/// Off the main actor: PNG file in a new cache dir plus the SHA-256 of the original data.
nonisolated private func prepareImage(_ data: Data, type: UTType, cache: ItemCache) -> (URL, URL, SHA256.Digest)? {
    guard let (file, dir) = writeImage(data, type: type, cache: cache) else { return nil }
    return (file, dir, SHA256.hash(data: data))
}

/// Writes PNG as-is (TIFF converted to PNG) to `root/<UUID>/Image <timestamp>.png`.
nonisolated private func writeImage(_ data: Data, type: UTType, cache: ItemCache) -> (URL, URL)? {
    let png: Data? = type == .png ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    guard let png, let dir = try? cache.newItemDir() else { return nil }
    let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                                             locale: .init(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current))
    let file = dir.appendingPathComponent("Image \(stamp).png")
    do { try png.write(to: file) } catch { cache.remove(dir: dir); return nil }
    return (file, dir)
}
