import SwiftUI

/// Shelf content: header, item grid, empty state.
struct ShelfView: View {
    let store: ShelfStore
    /// Whole-panel height cap; the grid scrolls beyond it.
    var maxHeight: CGFloat = 600
    var onClose: () -> Void = {}
    var onQuickLook: (UUID) -> Void = { _ in }
    /// Header drag moved the panel / header double-clicked (T-13 AC-4, AC-6).
    var onMoved: () -> Void = {}
    var onResetPosition: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tile under the pointer (tracked by its `DragOutHandleView`, which is the hit view).
    @State private var hovered: UUID?

    static let columnCount = 3
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columnCount)
    /// ponytail: fixed header and tile heights; `tileHeightMatchesLayout` test catches drift.
    private static let headerHeight: CGFloat = 52
    static let tileHeight: CGFloat = 103
    /// Panel height for 4.5 tile rows: the half row hints there is more (T-13 AC-2).
    static let maxContentHeight = headerHeight + 4 * (tileHeight + 12) + tileHeight / 2

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
        .shelfBackground(isTargeted: store.isDropTargeted)
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
                .accessibilityHint("Drag into another app to drop every item")
                .disabled(store.items.isEmpty)
                .overlay { DragOutHandle(store: store) }

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
                .accessibilityHint("Removes every item and hides the shelf")
                .disabled(store.items.isEmpty)

                Button(action: onClose) {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close")
                .accessibilityHint("Hides the shelf; items stay")
            }
            .labelStyle(.iconOnly)
            .shelfButtonStyle()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Empty header area moves the panel; buttons above it keep their clicks.
        .background { WindowDragArea(onMoved: onMoved, onDoubleClick: onResetPosition) }
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

    /// Finder/Dock-style remove badge on the thumbnail's top-leading corner.
    private func removeBadge(_ id: UUID) -> some View {
        Button { store.remove(ids: [id]) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Remove")
        .accessibilityLabel("Remove")
        .offset(x: -32)
        .transition(.opacity)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.items) { item in
                        ShelfItemView(item: item, isSelected: store.selection.contains(item.id),
                                      isMissing: store.missing(id: item.id),
                                      onRemove: { store.remove(ids: [item.id]) },
                                      onQuickLook: { onQuickLook(item.id) })
                            .overlay {
                                DragOutHandle(store: store, id: item.id, onHover: { inside in
                                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                                }, onQuickLook: onQuickLook)
                            }
                            // Above the handle so it gets the click.
                            .overlay(alignment: .top) { if hovered == item.id { removeBadge(item.id) } }
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            // Click on empty space deselects.
            .background { Color.clear.contentShape(.rect).onTapGesture { store.selection = [] } }
            // Hug content until the cap, then scroll.
            .frame(maxHeight: maxHeight - Self.headerHeight)
            .fixedSize(horizontal: false, vertical: true)
            .flashScrollIndicators(trigger: store.items.count)
            // Reveal what was just added (appended at the end) (T-13 AC-3).
            .onChange(of: store.items.count) { old, new in
                guard new > old, let last = store.items.last?.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }
}

/// Moves the window by dragging; AppKit so the first click in the inactive, non-activating panel works.
private struct WindowDragArea: NSViewRepresentable {
    let onMoved: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }

    func updateNSView(_ view: WindowDragView, context: Context) {
        view.onMoved = onMoved
        view.onDoubleClick = onDoubleClick
    }
}

final class WindowDragView: NSView {
    var onMoved: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    private var start: (mouse: NSPoint, origin: NSPoint)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = nil
        if event.clickCount == 2 { return onDoubleClick() }
        start = window.map { (NSEvent.mouseLocation, $0.frame.origin) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start else { return }
        let p = NSEvent.mouseLocation
        var frame = window.frame
        frame.origin = NSPoint(x: start.origin.x + p.x - start.mouse.x, y: start.origin.y + p.y - start.mouse.y)
        // Stay inside the visible frame of the screen under the pointer: never under the menu bar or off-screen (T-11 AC-9).
        if let visible = (NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? window.screen)?.visibleFrame {
            frame = ShelfPanelController.clamp(frame, to: visible)
        }
        window.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        if let start, window?.frame.origin != start.origin { onMoved() }
        start = nil
    }
}
