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
