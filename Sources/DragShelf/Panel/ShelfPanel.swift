import AppKit
import Carbon.HIToolbox
import Quartz

/// Floating, non-activating shelf window. Owns keyboard (Esc, Space, Return, Delete, arrows, Cmd-Z) and Quick Look,
/// which need the key window; show/hide behavior lives in `ShelfPanelController`.
final class ShelfPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var store: ShelfStore?
    /// Esc with Quick Look closed.
    var onCancel: (() -> Void)?
    /// User edge-drag resize: each step (`ended == false`) and the end (T-16 AC-4).
    var onUserResize: ((_ ended: Bool) -> Void)?
    /// Double-click on the cat or empty shelf space (content point, top-left origin): calls the pet (V3-01).
    var onPetCall: ((CGPoint) -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            // `.resizable` on a borderless panel: edge and corner resize with system cursors, no frame drawn (T-16 AC-4).
            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        NotificationCenter.default.addObserver(self, selector: #selector(liveResizeEnded),
                                               name: NSWindow.didEndLiveResizeNotification, object: self)
    }

    /// Top edge is the header move area, so a live resize never moves it (T-16 AC-4). The shadow is recomputed
    /// on every frame change: a stale one shows as a stray outline at the old size (T-16 AC-2).
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(inLiveResize ? Self.pinTop(frameRect, current: frame) : frameRect, display: flag)
        invalidateShadow()
        if inLiveResize { onUserResize?(false) }
    }

    /// A resize that moved the top edge keeps the current vertical span; width changes still apply.
    static func pinTop(_ proposed: NSRect, current: NSRect) -> NSRect {
        abs(proposed.maxY - current.maxY) < 0.5 ? proposed
            : NSRect(x: proposed.minX, y: current.minY, width: proposed.width, height: current.height)
    }

    @objc private func liveResizeEnded() { onUserResize?(true) }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keys are handled before SwiftUI sees them; Cmd/Ctrl/Option combos pass through (Cmd-C).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        if event.type == .leftMouseDown, event.clickCount == 2, let onPetCall, let content = contentView,
           let frame = content.superview {
            let p = content.convert(event.locationInWindow, from: nil)
            let top = CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y)
            if Self.callsPet(hit: content.hitTest(frame.convert(event.locationInWindow, from: nil)), yFromTop: top.y) {
                onPetCall(top)
            }
        }
        super.sendEvent(event)
    }

    /// A double-click calls the pet unless it lands on the header (its double-click resets the position), a tile
    /// or Recent row, or a control or text field.
    static func callsPet(hit: NSView?, yFromTop: CGFloat) -> Bool {
        guard yFromTop >= ShelfView.headerHeight else { return false }
        var view = hit
        while let v = view {
            if v is DragOutHandleView || v is WindowDragView || v is NSControl || v is NSText { return false }
            view = v.superview
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let store else { return false }
        // Custom resize form (V2-05): Esc closes it (not the panel); every other key goes to the form.
        if store.resizing != nil {
            guard Int(event.keyCode) == kVK_Escape else { return false }
            store.resizing = nil
            return true
        }
        // Rename or search field editing (V2-04, V2-10): every key goes to the text, Esc and Return included
        // (the search field's own delegate handles those).
        if firstResponder is NSText { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            // Cmd-Z: bring back the last drag out (T-17 AC-2); empty Recent passes through (system beep).
            case "z": return store.undoDragOut()
            // Cmd-F: show and focus the search field (V2-10 AC-1); nothing to search on an empty shelf.
            case "f":
                guard !store.items.isEmpty else { return false }
                store.showRecent = false
                store.isSearching = true
                store.searchFocus += 1
                return true
            case "a": // Cmd-A: select every visible item (V2-10 AC-3).
                store.selectAll()
                return true
            default: return false
            }
        }
        guard modifiers.isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: // Quick Look first, then an open search (clears it), then the panel.
            if isPreviewVisible { closePreview() } else if store.isSearching { store.resetSearch() } else { onCancel?() }
        case kVK_Space: isPreviewVisible ? closePreview() : openPreview()
        case kVK_Return: // Finder: Return renames the one selected file (V2-04 AC-1).
            guard store.actions.canRun(.rename, on: store.selectedItems) else { return false }
            store.actions.run(.rename, on: store.selectedItems, in: store)
        case kVK_Delete, kVK_ForwardDelete: store.remove(ids: store.selectedIDs)
        case kVK_LeftArrow: store.moveSelection(by: -1)
        case kVK_RightArrow: store.moveSelection(by: 1)
        case kVK_UpArrow: store.moveSelection(by: -ShelfView.columnCount(width: frame.width))
        case kVK_DownArrow: store.moveSelection(by: ShelfView.columnCount(width: frame.width))
        default: return false
        }
        return true
    }

    // MARK: Quick Look (US-7). Ordered front, never made key: keys stay here and DragShelf stays inactive.

    private var isPreviewVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func openPreview() {
        guard store?.previewURLs.isEmpty == false else { return }
        let preview: QLPreviewPanel = QLPreviewPanel.shared()
        preview.updateController()
        // Fallback if the controller search (key window's responder chain) missed us while the app is inactive.
        if preview.dataSource == nil { beginPreviewPanelControl(preview) }
        preview.reloadData()
        preview.orderFront(nil)
    }

    /// Called whenever the previewable selection changes (keys, clicks, remove, missing).
    func syncPreview() {
        guard isPreviewVisible else { return }
        store?.previewURLs.isEmpty != false ? closePreview() : QLPreviewPanel.shared().reloadData()
    }

    func closePreview() {
        if isPreviewVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    // QLPreviewPanelController informal protocol: declared nonisolated, always called on main.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
            // The app is never active; do not let a later deactivation hide the preview.
            panel.hidesOnDeactivate = false
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        store?.previewURLs.count ?? 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        store?.previewURL(at: index) as NSURL?
    }

    /// Keys pressed while the preview itself is key (user clicked it) still drive the shelf.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        event.type == .keyDown && handleKey(event)
    }
}
