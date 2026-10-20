import AppKit
import Carbon.HIToolbox
import Quartz

/// Floating, non-activating shelf window. Owns keyboard (Esc, Space, Delete, arrows) and Quick Look,
/// which need the key window; show/hide behavior lives in `ShelfPanelController`.
final class ShelfPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var store: ShelfStore?
    /// Esc with Quick Look closed.
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keys are handled before SwiftUI sees them; Cmd/Ctrl/Option combos pass through (Cmd-C).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let store,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: isPreviewVisible ? closePreview() : onCancel?()
        case kVK_Space: isPreviewVisible ? closePreview() : openPreview()
        case kVK_Delete, kVK_ForwardDelete: store.remove(ids: store.selection)
        case kVK_LeftArrow: store.moveSelection(by: -1)
        case kVK_RightArrow: store.moveSelection(by: 1)
        case kVK_UpArrow: store.moveSelection(by: -ShelfView.columnCount)
        case kVK_DownArrow: store.moveSelection(by: ShelfView.columnCount)
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
