import AppKit
import SwiftUI

/// Header search field (V2-10): a native `NSSearchField` that filters the grid live (`ShelfStore.query`).
/// Esc clears and hides it; Return or ↓ hand the keys back to the grid (arrows, Space, ⌘C). Focusing it makes the
/// panel key without activating DragShelf (non-activating panel), like the rename field.
struct SearchField: NSViewRepresentable {
    let store: ShelfStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> ShelfSearchField {
        let field = ShelfSearchField()
        field.placeholderString = "Search"
        field.controlSize = .small
        field.font = .preferredFont(forTextStyle: .callout)
        field.sendsSearchStringImmediately = true
        field.stringValue = store.query
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search DragShelf")
        field.setAccessibilityHelp("Filters items by name, link, or text. Press Escape to clear.")
        return field
    }

    func updateNSView(_ field: ShelfSearchField, context: Context) {
        context.coordinator.store = store
        if field.stringValue != store.query { field.stringValue = store.query }
        // ⌘F again while shown (focus elsewhere): back into the field.
        if context.coordinator.focus != store.searchFocus {
            context.coordinator.focus = store.searchFocus
            field.focus()
        }
    }

    static func dismantleNSView(_ field: ShelfSearchField, coordinator: Coordinator) {
        field.stopWatching()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var store: ShelfStore
        var focus: Int

        init(store: ShelfStore) {
            self.store = store
            focus = store.searchFocus
        }

        /// Every keystroke and the field's ✕ button.
        @objc func changed(_ field: NSSearchField) {
            if store.query != field.stringValue { store.query = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                control.window?.makeFirstResponder(nil)
                store.resetSearch()
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)):
                control.window?.makeFirstResponder(nil)
                if store.selectedItems.isEmpty { store.moveSelection(by: 1) }
            default:
                return false
            }
            return true
        }
    }
}

final class ShelfSearchField: NSSearchField {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, monitor == nil else { return }
        monitor = endEditingOnClickElsewhere()
        focus()
    }

    /// After this layout pass: the field needs its frame before it can take focus.
    func focus() {
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeKey() // Non-activating panel: key for typing, DragShelf stays inactive.
            window.makeFirstResponder(self)
        }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
