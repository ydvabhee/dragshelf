import AppKit
import SwiftUI

/// Header "Actions" menu (V2-01): applies to the selection, or to all items when nothing is selected.
/// The tile context menu lists the same `ShelfAction.allCases` (AppKit menu in `DragOutHandleView`).
struct ActionsMenu: View {
    let store: ShelfStore

    var body: some View {
        let targets = store.selectedItems.isEmpty ? store.items : store.selectedItems
        Menu {
            ForEach(ShelfAction.allCases, id: \.self) { action in
                Button(action.title) { store.actions.run(action, on: targets, in: store) }
                    .disabled(!store.actions.canRun(action, on: targets))
            }
            // V2-02: UI actions, not jobs; items stay on the shelf (OQ-25).
            Button("Share…") { Sharer.shared.share(targets) }
                .disabled(Sharer.items(for: targets).isEmpty)
            Button("AirDrop") { Sharer.shared.airDrop(targets) }
                .disabled(!Sharer.canAirDrop(targets))
            // V2-03: disabled when the target has no image items.
            ForEach([("Convert To", ShelfAction.conversions), ("Resize", ShelfAction.resizes)], id: \.0) { title, actions in
                Menu(title) {
                    ForEach(actions, id: \.self) { action in
                        Button(action.menuTitle) { store.actions.run(action, on: targets, in: store) }
                    }
                }
                .disabled(!actions.contains { store.actions.canRun($0, on: targets) })
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help(store.selection.isEmpty ? "Actions for all items" : "Actions for the selected items")
        .accessibilityHint(store.selection.isEmpty ? "Applies to all items" : "Applies to the selected items")
        .disabled(store.items.isEmpty || store.actions.running != nil)
    }
}

/// Share… and AirDrop (V2-02). Items: present files and links as `NSURL`, text as `NSString` (same writers as drag
/// out); missing files are left out. Items stay on the shelf after sharing (OQ-25).
///
/// Activation: the picker and the service sheets (AirDrop, Messages, …) are windows of this app, and an inactive app's
/// windows can open behind the frontmost app. So this action, and only this one, calls `NSApp.activate()` (the same
/// exception as Settings, ARCHITECTURE §5 rule 6) and `NSApp.deactivate()` when the picker closes without a choice or
/// the service finishes, fails, or is cancelled; focus goes back to the previous app and the panel drops key.
/// The panel stays up meanwhile: `hidesOnDeactivate` is false and no auto-hide rule fires for a non-empty shelf.
final class Sharer: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    static let shared = Sharer()
    /// Kept while open: AppKit does not retain the picker.
    private var picker: NSSharingServicePicker?
    private var activated = false

    static func items(for targets: [ShelfItem]) -> [Any] {
        targets.filter(ShelfStore.exists).map(DragOutSource.writer(for:))
    }

    static func canAirDrop(_ targets: [ShelfItem]) -> Bool {
        let items = items(for: targets)
        return !items.isEmpty && NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: items) == true
    }

    /// System share picker under `anchor` (a tile), else at the mouse in the panel (header menu: where "Share…" was clicked).
    func share(_ targets: [ShelfItem], anchor: NSView? = nil) {
        let items = Self.items(for: targets)
        guard !items.isEmpty, let view = anchor ?? NSApp.windows.first(where: { $0 is ShelfPanel })?.contentView,
              let window = view.window else { return }
        let rect = anchor?.bounds
            ?? NSRect(origin: view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil), size: .zero)
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        activate()
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func airDrop(_ targets: [ShelfItem]) {
        let items = Self.items(for: targets)
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else { return }
        service.delegate = self
        activate()
        service.perform(withItems: items)
    }

    private func activate() {
        activated = true
        NSApp.activate()
    }

    private func finished() {
        picker = nil
        guard activated else { return }
        activated = false
        NSApp.deactivate()
    }

    // ADR-016: AppKit may call these off main.
    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker,
                                          delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }

    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard service == nil else { return }
        Task { @MainActor in self.finished() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        Task { @MainActor in self.finished() }
    }
}
