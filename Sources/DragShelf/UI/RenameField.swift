import AppKit
import SwiftUI

/// Finder-style inline rename over a tile caption (V2-04, US-12). AppKit field: it selects the base name, and its
/// delegate owns Return (commit; an invalid name shakes and stays), Esc (cancel; the panel does not hide), and
/// end editing (click elsewhere, panel hides or loses key: commit; an invalid name reverts). It makes the panel
/// key without activating DragShelf (non-activating panel).
struct RenameField: NSViewRepresentable {
    let store: ShelfStore
    let item: ShelfItem

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> RenameTextField {
        let name = item.displayName
        let field = RenameTextField(string: name)
        field.font = .preferredFont(forTextStyle: .caption1)
        field.alignment = .center
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        field.delegate = context.coordinator
        if case .file(let url) = item.kind { field.selection = Renamer.baseRange(of: name, isFolder: Renamer.isFolder(url)) }
        field.setAccessibilityLabel("Name")
        field.setAccessibilityHelp("Press Return to rename, Escape to cancel")
        return field
    }

    func updateNSView(_ field: RenameTextField, context: Context) {
        let store = store, id = item.id
        context.coordinator.commit = { text in
            guard let item = store.items.first(where: { $0.id == id }) else { return nil }
            return store.actions.rename(item, to: text, in: store)
        }
        context.coordinator.cancel = { if store.renamingID == id { store.renamingID = nil } }
    }

    /// Tile width, one text line high.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: RenameTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height + 2)
    }

    /// Tile gone (removed, Clear) while editing: nothing to rename, close without committing.
    static func dismantleNSView(_ field: RenameTextField, coordinator: Coordinator) {
        if !coordinator.done {
            coordinator.done = true
            coordinator.cancel()
        }
        field.stopWatching()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        /// Error text, or nil when accepted (the store then closes the field).
        var commit: (String) -> String? = { _ in nil }
        var cancel: () -> Void = {}
        var done = false

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? RenameTextField, !done else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if let error = commit(field.stringValue) {
                    AccessibilityNotification.Announcement(error).post()
                    field.shake()
                    return true
                }
                finish(field)
            case #selector(NSResponder.cancelOperation(_:)):
                finish(field)
                cancel()
            default:
                return false
            }
            return true
        }

        /// Click elsewhere, Tab, the panel hid or lost key: commit; an invalid name keeps the old one.
        func controlTextDidEndEditing(_ note: Notification) {
            guard !done, let field = note.object as? NSTextField else { return }
            done = true
            if commit(field.stringValue) != nil { cancel() }
        }

        private func finish(_ field: NSTextField) {
            done = true
            field.window?.makeFirstResponder(nil)
        }
    }
}

final class RenameTextField: NSTextField {
    /// Base-name range selected when editing starts.
    var selection: NSRange?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, monitor == nil else { return }
        // A click anywhere else in the panel ends editing (the tiles' drag handles never take first responder).
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, let window = self.window, event.window === window,
               !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                window.makeFirstResponder(nil)
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: window)
        // After this layout pass: the field needs its frame before it can take focus.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeKey() // Non-activating panel: key for typing, DragShelf stays inactive.
            window.makeFirstResponder(self)
            if let selection = self.selection { self.currentEditor()?.selectedRange = selection }
        }
    }

    @objc private func windowResignedKey() {
        if currentEditor() != nil { window?.makeFirstResponder(nil) }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.removeObserver(self)
    }

    /// Invalid name (US-12 AC-3): a short horizontal shake; Reduce Motion skips it (the inline message stays).
    func shake() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -6, 6, -4, 4, 0]
        shake.duration = 0.3
        layer?.add(shake, forKey: "shake")
    }
}
