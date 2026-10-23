import SwiftUI

/// Shelf content: header, item grid, empty state.
struct ShelfView: View {
    let store: ShelfStore
    /// Panel width (user-resizable, T-16); columns follow it.
    var width: CGFloat = ShelfView.defaultWidth
    /// Whole-panel height cap; the grid scrolls beyond it.
    var maxHeight: CGFloat = 600
    var onClose: () -> Void = {}
    var onQuickLook: (UUID) -> Void = { _ in }
    /// Header drag moved the panel / header double-clicked (T-13 AC-4, AC-6).
    var onMoved: () -> Void = {}
    var onResetPosition: () -> Void = {}
    /// Footer promo (nil when promos are off or none is eligible) and its ✕ (T-14).
    var promo: Promo?
    var onDismissPromo: (String) -> Void = { _ in }
    /// Contextual tip (T-18); takes the footer slot over the promo. Nil when tips are off or none is due.
    var hint: HintEngine.Hint?
    var onDismissHint: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tile under the pointer (tracked by its `DragOutHandleView`, which is the hit view).
    @State private var hovered: UUID?
    /// Promo row height, measured: the grid cap leaves room for it so the panel never exceeds `maxHeight`.
    @State private var footerHeight: CGFloat = 0
    /// Action caption height, measured like the footer.
    @State private var captionHeight: CGFloat = 0

    /// Grid / Recent height cap: what `maxHeight` leaves after header, caption, and footer.
    private var contentCap: CGFloat {
        max(0, maxHeight - Self.headerHeight - (store.actions.message == nil ? 0 : captionHeight)
            - (hint == nil && promo == nil ? 0 : footerHeight))
    }

    /// One footer line: a hint wins over a promo (T-18 AC-1).
    enum Footer: Equatable { case hint(HintEngine.Hint), promo(Promo) }
    static func footer(hint: HintEngine.Hint?, promo: Promo?) -> Footer? {
        hint.map(Footer.hint) ?? promo.map(Footer.promo)
    }

    static let defaultWidth: CGFloat = 288
    private static let gridPadding: CGFloat = 12, columnSpacing: CGFloat = 8, minTileWidth: CGFloat = 80
    /// ponytail: fixed header and tile heights; `tileHeightMatchesLayout` test catches drift.
    private static let headerHeight: CGFloat = 52
    static let tileHeight: CGFloat = 103
    /// Panel height for 4.5 tile rows: the half row hints there is more (T-13 AC-2).
    static let maxContentHeight = headerHeight + 4 * (tileHeight + 12) + tileHeight / 2
    /// User-resize floor: header + one tile column and row (T-16 AC-5).
    static let minSize = NSSize(width: 176, height: headerHeight + tileHeight + 14)

    /// Adaptive columns: as many `minTileWidth` tiles as fit (T-16 AC-5). Arrow keys use it too.
    static func columnCount(width: CGFloat) -> Int {
        max(1, Int((width - 2 * gridPadding + columnSpacing) / (minTileWidth + columnSpacing)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Last action's result or error, one line (V2-01 AC-4, AC-7).
            if let message = store.actions.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { captionHeight = $0 }
            }
            if store.showRecent && !store.recent.isEmpty {
                ScrollView { RecentList(store: store) }
                    .frame(maxHeight: contentCap)
                    .fixedSize(horizontal: false, vertical: true)
            } else if store.items.isEmpty {
                emptyState
            } else {
                grid
            }
            // Own row under the grid: never over tiles. Hidden during any drag; the row keeps its height so the
            // panel does not resize under the pointer (a hover at the bottom edge would otherwise flicker).
            // ZStack: an outgoing and incoming line overlap instead of stacking (no height jump on swap).
            if let footer = Self.footer(hint: hint, promo: promo) {
                let dragging = store.isDragging || store.isDropTargeted
                ZStack {
                    switch footer {
                    case .hint(let hint):
                        HintFooter(hint: hint, onDismiss: onDismissHint)
                            .id(hint)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                    case .promo(let promo):
                        PromoFooter(promo: promo, onDismiss: { onDismissPromo(promo.id) })
                            .transition(.opacity)
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
                .opacity(dragging ? 0 : 1)
                .allowsHitTesting(!dragging)
                .accessibilityHidden(dragging)
                .animation(.easeInOut(duration: 0.15), value: dragging)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0.1), value: hint)
                .transition(.opacity)
            }
        }
        .frame(width: width)
        .frame(minHeight: 160, alignment: .top)
        .shelfBackground(isTargeted: store.isDropTargeted)
        // Clicks make the panel key; never draw the system focus ring (T-16 AC-1). Selection is the tile's own style.
        .focusEffectDisabled()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15),
                   value: store.items)
        // Back to the grid when items arrive (a restore, a drop) or Recent empties.
        .onChange(of: store.items.count) { old, new in if new > old { store.showRecent = false } }
        .onChange(of: store.recent.isEmpty) { _, empty in if empty { store.showRecent = false } }
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

                if let action = store.actions.running {
                    // Running job (V2-01 AC-5): spinner or progress, title, Cancel.
                    ProgressView(value: store.actions.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .accessibilityLabel(action.runningTitle)
                    Text(action.runningTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button { store.actions.cancel() } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .help("Cancel")
                    .accessibilityHint("Stops \(action.title.lowercased()) and adds nothing")
                } else {
                    Text(store.showRecent && !store.recent.isEmpty ? "Recent"
                         : store.items.isEmpty ? "DragShelf" : "^[\(store.items.count) Item](inflect: true)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                ActionsMenu(store: store)

                if !store.recent.isEmpty {
                    Button { store.showRecent.toggle() } label: {
                        Label("Recent drags", systemImage: "clock.arrow.circlepath")
                    }
                    .help(store.showRecent ? "Show DragShelf items" : "Show recent drags")
                    .foregroundStyle(store.showRecent ? Color.accentColor : Color.primary)
                    .accessibilityAddTraits(store.showRecent ? .isSelected : [])
                    .accessibilityHint(store.showRecent ? "Shows DragShelf items again" : "Lists recent drags out to restore or drag again")
                }

                Button("Clear") {
                    store.clear()
                    onClose()
                    // After the hide: the tip waits for the next show instead of flashing out (T-20 AC-5).
                    store.hints.record(.cleared)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help("Remove all items from DragShelf. Your files stay where they are.")
                .accessibilityLabel("Clear DragShelf")
                .accessibilityHint("Removes all items from DragShelf; files are not deleted")
                .disabled(store.items.isEmpty)

                Button(action: onClose) {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close")
                .accessibilityHint("Hides DragShelf; items stay")
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing, alignment: .top),
                                         count: Self.columnCount(width: width)), spacing: 12) {
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
                .padding(.horizontal, Self.gridPadding)
                .padding(.bottom, 14)
                .background { OverlayScroller() }
            }
            // Scroll bar inside the rounded shelf: off the right edge, clear of the bottom corners (T-16 AC-3).
            .contentMargins(.top, 4, for: .scrollIndicators)
            .contentMargins(.bottom, shelfCornerRadius, for: .scrollIndicators)
            .contentMargins(.trailing, 4, for: .scrollIndicators)
            // Click on empty space deselects.
            .background { Color.clear.contentShape(.rect).onTapGesture { store.selection = [] } }
            // Hug content until the cap, then scroll.
            .frame(maxHeight: contentCap)
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

/// Forces the thin, auto-hiding overlay scroller (T-16 AC-3) even when the system prefers legacy scrollers
/// (mouse attached, "Always show"). AppKit resets the style when that preference changes, so re-apply after it.
private struct OverlayScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerView { OverlayScrollerView() }
    func updateNSView(_ view: OverlayScrollerView, context: Context) {}
}

final class OverlayScrollerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(preferenceChanged),
                                               name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        apply()
    }

    /// The scroller-style notification may post off the main thread.
    @objc nonisolated private func preferenceChanged() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.apply() } }
    }
    private func apply() { enclosingScrollView?.scrollerStyle = .overlay }
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
