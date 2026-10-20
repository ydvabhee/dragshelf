import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag out and Cmd-C for shelf items (ADR-007): file/url → `NSURL`, text → `NSString`; copy, or move with Cmd for all-file drags.
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

    /// Outside the app: Cmd held and every item is a file → `[.move, .copy]` (copy-only receivers still accept); else `.copy`. Inside the app: `[]`
    /// (a drop on our own shelf would be a no-op duplicate).
    /// Without Cmd the mask is copy only, so Finder's own ⌥/⌘ semantics never turn a plain drag into a move.
    /// Mixed selection: whole drag copies (per-item masks are not supported by AppKit).
    static func mask(for context: NSDraggingContext, modifiers: NSEvent.ModifierFlags = [], allFiles: Bool = false) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        return allFiles && modifiers.contains(.command) ? [.move, .copy] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        let allFiles = store.items.filter { ids.contains($0.id) }.allSatisfy { if case .file = $0.kind { true } else { false } }
        return Self.mask(for: context, modifiers: NSEvent.modifierFlags, allFiles: allFiles)
    }

    /// False so the system badge follows our per-call mask (Cmd toggles move live).
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ended(operation: operation)
        Self.current = nil
    }

    /// Pure rule: `[]` = cancelled (Esc / dropped on nothing) → keep; `.move` → always remove
    /// (the file left its folder); otherwise `keepAfterDragOut` → keep.
    static func shouldRemove(operation: NSDragOperation, keepAfterDragOut: Bool) -> Bool {
        if operation == .move { return true }
        return operation != [] && !keepAfterDragOut
    }

    /// Removes the dragged items unless `shouldRemove` says keep.
    /// Copy: cache dirs stay until clear/quit (targets read the file after the drop).
    /// Move: the file is gone, so an emptied cache dir is deleted.
    func ended(operation: NSDragOperation) {
        guard Self.shouldRemove(operation: operation, keepAfterDragOut: Preferences.keepAfterDrag()) else { return }
        let moved = store.items.filter { ids.contains($0.id) && $0.isCached }
        store.remove(ids: ids, deletingCache: false)
        guard operation == .move else { return }
        let fm = FileManager.default
        let root = store.cache.root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        for case .file(let url) in moved.map(\.kind) {
            let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            guard parts.count > root.count + 1, Array(parts.prefix(root.count)) == root else { continue }
            let dir = store.cache.root.appendingPathComponent(parts[root.count], isDirectory: true)
            if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { store.cache.remove(dir: dir) }
        }
    }
}

/// Transparent AppKit layer over a tile (`id`) or the drag-all button (`id == nil`).
/// AppKit mouse handling, not a SwiftUI gesture, so the first click in the inactive panel starts a drag.
/// Being the hit view, it also owns the tile's hover tracking and context menu (T-07 AC-8).
struct DragOutHandle: NSViewRepresentable {
    let store: ShelfStore
    var id: UUID?
    var onHover: (Bool) -> Void = { _ in }
    var onQuickLook: (UUID) -> Void = { _ in }

    func makeNSView(context: Context) -> DragOutHandleView { DragOutHandleView() }

    func updateNSView(_ view: DragOutHandleView, context: Context) {
        view.store = store
        view.id = id
        view.onHover = onHover
        view.onQuickLook = onQuickLook
        view.toolTip = id == nil ? "Drag all items" : nil
    }
}

final class DragOutHandleView: NSView {
    var store: ShelfStore?
    var id: UUID?
    var onHover: (Bool) -> Void = { _ in }
    var onQuickLook: (UUID) -> Void = { _ in }
    private var mouseDown: NSEvent?
    /// Plain click on an already-selected tile keeps the selection for a multi-drag; collapses on mouse up.
    private var collapseOnUp = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        // `.activeAlways`: the app is never active.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Panel turns key (not active) so Cmd-C reaches it.
    override var needsPanelToBecomeKey: Bool { true }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    /// Finder-style: right-click on an unselected tile selects it; actions apply to the selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let store, let id else { return nil }
        if !store.selection.contains(id) { store.select(id, command: false, shift: false) }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quick Look", action: #selector(previewSelection), keyEquivalent: "").isEnabled = !store.previewURLs.isEmpty
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove", action: #selector(removeSelection), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        menu.autoenablesItems = false
        return menu
    }

    @objc private func previewSelection() { id.map(onQuickLook) }
    @objc private func removeSelection() { store.map { $0.remove(ids: $0.selection) } }

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
        DragOutSource.begin(items: store.dragItems(for: id), event: start, view: self, store: store)
    }

    override func mouseUp(with event: NSEvent) {
        if collapseOnUp, let id { store?.select(id, command: false, shift: false) }
        mouseDown = nil
        collapseOnUp = false
    }
}
