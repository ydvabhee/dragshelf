import SwiftUI

/// Shelf content: header, item grid, empty state.
struct ShelfView: View {
    let store: ShelfStore
    /// Whole-panel height cap; the grid scrolls beyond it.
    var maxHeight: CGFloat = 600
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)
    /// ponytail: fixed header allowance; measure it if the header grows.
    private let headerHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(width: 288)
        .frame(minHeight: 160, alignment: .top)
        .shelfBackground(isTargeted: false)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15),
                   value: store.items)
    }

    private var header: some View {
        ShelfGlassContainer {
            HStack(spacing: 8) {
                Button {} label: {
                    Label("Drag All", systemImage: "square.stack.3d.up")
                }
                .help("Drag all items")
                .disabled(store.items.isEmpty)

                Text(store.items.isEmpty ? "Shelf" : "^[\(store.items.count) Item](inflect: true)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    store.clear()
                    onClose()
                } label: {
                    Label("Clear Shelf", systemImage: "trash")
                }
                .help("Clear shelf")
                .disabled(store.items.isEmpty)

                Button(action: onClose) {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close")
            }
            .labelStyle(.iconOnly)
            .shelfButtonStyle()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Drop here")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Files, links, and text")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.items) { item in
                    ShelfItemView(item: item)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        // Hug content until the cap, then scroll.
        .frame(maxHeight: maxHeight - headerHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}
