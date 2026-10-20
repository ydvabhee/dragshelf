import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag out and Cmd-C for shelf items (ADR-007): file/url → `NSURL`, text → `NSString`, copy only.
final class DragOutSource: NSObject, NSDraggingSource {
    /// Keeps the source alive for the running session (one drag at a time).
    private(set) static var current: DragOutSource?

    let store: ShelfStore
    let ids: Set<UUID>

    init(store: ShelfStore, ids: Set<UUID>) {
        self.store = store
        self.ids = ids
    }

    static func writer(for item: ShelfItem) -> any NSPasteboardWriting {
        switch item.kind {
        case .file(let url), .url(let url): url as NSURL
        case .text(let text): text as NSString
        }
    }

    /// Cmd-C: same writers as drag out.
    static func copy(_ items: [ShelfItem], to pb: NSPasteboard = .general) {
        guard !items.isEmpty else { return }
        pb.clearContents()
        pb.writeObjects(items.map(writer(for:)))
    }

    /// Starts one session with an `NSDraggingItem` per item; icons stack under the cursor.
    static func begin(items: [ShelfItem], event: NSEvent, view: NSView, store: ShelfStore) {
        guard !items.isEmpty else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        let dragItems = items.enumerated().map { i, item in
            let d = NSDraggingItem(pasteboardWriter: writer(for: item))
            let offset = CGFloat(min(i, 4)) * 4
            d.setDraggingFrame(NSRect(x: p.x - 32 + offset, y: p.y - 32 - offset, width: 64, height: 64),
                               contents: icon(for: item))
            return d
        }
        let source = DragOutSource(store: store, ids: Set(items.map(\.id)))
        current = source
        let session = view.beginDraggingSession(with: dragItems, event: event, source: source)
        session.draggingFormation = items.count > 1 ? .stack : .none
    }

    private static func icon(for item: ShelfItem) -> NSImage {
        switch item.kind {
        case .file(let url): NSWorkspace.shared.icon(forFile: url.path)
        case .url: NSWorkspace.shared.icon(for: .internetShortcut)
        case .text: NSWorkspace.shared.icon(for: .plainText)
        }
    }

    /// Copy only, and never back onto our own shelf (a drop there would be a no-op duplicate).
    static func mask(for context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.mask(for: context)
    }

    /// Cmd/Option must not turn the drag into a move/link the mask forbids.
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ended(operation: operation)
        Self.current = nil
    }

    /// `[]` = cancelled (Esc / dropped on nothing) → keep. Otherwise remove the dragged items.
    /// Cache dirs stay until clear/quit: targets (Finder copy, browser upload, Slack) read the file after the drop.
    func ended(operation: NSDragOperation) {
        guard operation != [] else { return }
        store.remove(ids: ids, deletingCache: false)
    }
}

/// Transparent AppKit layer over a tile (`id`) or the drag-all button (`id == nil`).
/// AppKit mouse handling, not a SwiftUI gesture, so the first click in the inactive panel starts a drag.
struct DragOutHandle: NSViewRepresentable {
    let store: ShelfStore
    var id: UUID?

    func makeNSView(context: Context) -> DragOutHandleView { DragOutHandleView() }

    func updateNSView(_ view: DragOutHandleView, context: Context) {
        view.store = store
        view.id = id
        view.toolTip = id == nil ? "Drag all items" : nil
    }
}

final class DragOutHandleView: NSView {
    var store: ShelfStore?
    var id: UUID?
    private var mouseDown: NSEvent?
    /// Plain click on an already-selected tile keeps the selection for a multi-drag; collapses on mouse up.
    private var collapseOnUp = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Panel turns key (not active) so Cmd-C reaches it.
    override var needsPanelToBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDown = event
        guard let store, let id else { return }
        let command = event.modifierFlags.contains(.command), shift = event.modifierFlags.contains(.shift)
        collapseOnUp = !command && !shift && store.selection.contains(id)
        if !collapseOnUp { store.select(id, command: command, shift: shift) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let store, let start = mouseDown else { return }
        let a = start.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) >= 3 else { return }
        mouseDown = nil
        collapseOnUp = false
        DragOutSource.begin(items: id.map(store.dragItems(for:)) ?? store.items, event: start, view: self, store: store)
    }

    override func mouseUp(with event: NSEvent) {
        if collapseOnUp, let id { store?.select(id, command: false, shift: false) }
        mouseDown = nil
        collapseOnUp = false
    }
}
