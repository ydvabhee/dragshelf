import AppKit
import SwiftUI

/// Shows, hides, and positions the shelf panel. Never activates the app (ARCHITECTURE §5 rule 6).
@Observable
final class ShelfPanelController {
    /// `.hotkey` is the only reason that makes the panel key (T-14 AC-X): menu and auto-show leave keyboard
    /// focus with the frontmost app.
    enum ShowReason { case manual, hotkey, autoDrag }

    private(set) var isShown = false
    /// Panel height cap: min(4.5 tile rows, 50% of the screen's visible height) (T-13 AC-2).
    fileprivate var maxHeight: CGFloat = 600

    @ObservationIgnored let store: ShelfStore
    @ObservationIgnored let promos: PromoLoader
    @ObservationIgnored private let panel = ShelfPanel()
    @ObservationIgnored private(set) var reason: ShowReason?
    @ObservationIgnored private var droppedOnShelf = false
    @ObservationIgnored private var dragActive = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Gap below the menu bar / notch, and the entry slide distance.
    static let topInset: CGFloat = 12
    private static let slide: CGFloat = 10
    /// UserDefaults key: [screen id: [dx, dy]], panel top-center offset from the visibleFrame's top center (T-13 AC-5).
    static let offsetsKey = "panelOffsets"

    init(store: ShelfStore, promos: PromoLoader) {
        self.store = store
        self.promos = promos
        let receiver = DropReceiver(rootView: PanelRoot(controller: self))
        receiver.store = store
        receiver.onDrop = { [weak self] in self?.droppedOnShelf = true }
        receiver.onPromiseFailed = { [weak self] in self?.promiseFailed() }
        panel.contentView = receiver
        panel.store = store
        panel.onCancel = { [weak self] in self?.hide() }
    }

    /// Top center of `visible`, top edge fixed so content growth extends downward (AC-9).
    /// `safeTop` = screen top minus the notch inset; matters when the menu bar is hidden (full screen).
    static func topCenterFrame(size: NSSize, in visible: NSRect, safeTop: CGFloat = .infinity) -> NSRect {
        NSRect(x: (visible.midX - size.width / 2).rounded(), y: min(visible.maxY, safeTop) - topInset - size.height,
               width: size.width, height: size.height)
    }

    /// Saved spot: `offset` = (top-center x − visible.midX, visible.maxY − top), clamped into `visible`.
    static func frame(size: NSSize, offset: CGPoint, in visible: NSRect) -> NSRect {
        clamp(NSRect(x: (visible.midX + offset.x - size.width / 2).rounded(), y: visible.maxY - offset.y - size.height,
                     width: size.width, height: size.height), to: visible)
    }

    static func offset(of frame: NSRect, in visible: NSRect) -> CGPoint {
        CGPoint(x: frame.midX - visible.midX, y: visible.maxY - frame.maxY)
    }

    /// New height with the top edge fixed; near the screen bottom it shifts up to stay inside `visible`.
    static func fit(_ frame: NSRect, height: CGFloat, in visible: NSRect) -> NSRect {
        clamp(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), to: visible)
    }

    static func clamp(_ f: NSRect, to v: NSRect) -> NSRect {
        NSRect(x: max(v.minX, min(f.minX, v.maxX - f.width)), y: max(v.minY, min(f.minY, v.maxY - f.height)),
               width: f.width, height: f.height)
    }

    /// Stable across reboots and display reordering (display UUID), name as a fallback.
    private static func id(of screen: NSScreen) -> String {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return screen.localizedName }
        return string as String
    }

    private var savedOffsets: [String: [Double]] {
        get { UserDefaults.standard.dictionary(forKey: Self.offsetsKey) as? [String: [Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.offsetsKey) }
    }

    /// Frame on `screen` for content `size`: saved spot if any, else top center (T-08 AC-9).
    private func frame(size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        if let o = savedOffsets[Self.id(of: screen)], o.count == 2 {
            return Self.frame(size: size, offset: CGPoint(x: o[0], y: o[1]), in: visible)
        }
        return Self.topCenterFrame(size: size, in: visible, safeTop: screen.frame.maxY - screen.safeAreaInsets.top)
    }

    /// Header drag ended: remember the spot for the panel's current screen.
    func userMoved() {
        guard let screen = panel.screen else { return }
        let o = Self.offset(of: panel.frame, in: screen.visibleFrame)
        savedOffsets[Self.id(of: screen)] = [o.x, o.y]
        updateMaxHeight(for: screen)
    }

    /// Height cap for `screen` (T-11 AC-8: also after a move to another screen). Set only on change: every set
    /// re-renders the view.
    private func updateMaxHeight(for screen: NSScreen) {
        let h = min(ShelfView.maxContentHeight, (screen.visibleFrame.height * 0.5).rounded())
        if h != maxHeight { maxHeight = h }
    }

    /// Menu item / header double-click: forget all saved spots, back to top center.
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.offsetsKey)
        guard isShown, let screen = panel.screen else { return }
        panel.setFrame(frame(size: panel.frame.size, on: screen), display: true,
                       animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Resizes the shown panel to its content, top edge fixed (T-13 AC-1). Called async after a geometry change:
    /// `fittingSize` is 0 inside the callback.
    func fitToContent() {
        guard isShown, let screen = panel.screen else { return }
        updateMaxHeight(for: screen)
        guard let height = panel.contentView?.fittingSize.height, height > 0,
              abs(height - panel.frame.height) >= 0.5 else { return }
        panel.setFrame(Self.fit(panel.frame, height: height, in: screen.visibleFrame), display: true)
    }

    /// Visibility rule 2 (ARCHITECTURE §5): only an auto-shown, still-empty shelf that got no drop hides.
    static func shouldAutoHide(reason: ShowReason?, droppedOnShelf: Bool, isEmpty: Bool, dragActive: Bool) -> Bool {
        reason == .autoDrag && !droppedOnShelf && isEmpty && !dragActive
    }

    func toggle(reason: ShowReason = .manual) {
        isShown ? hide() : show(reason: reason)
    }

    func dragStarted(at point: NSPoint) {
        hideTask?.cancel()
        dragActive = true
        store.isDragging = true
        droppedOnShelf = false
        show(reason: .autoDrag, at: point)
    }

    /// 250 ms grace lets an in-flight drop land first (+0.2 s fade stays under AC-3's 500 ms).
    func dragEnded() {
        dragActive = false
        store.isDragging = false
        hideTask?.cancel()
        hideTask = Task {
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            hideIfUnused(droppedOnShelf: droppedOnShelf)
        }
    }

    /// A promise drop counted as a drop but never landed: treat it as no drop.
    private func promiseFailed() {
        hideIfUnused(droppedOnShelf: false)
    }

    private func hideIfUnused(droppedOnShelf: Bool) {
        if Self.shouldAutoHide(reason: reason, droppedOnShelf: droppedOnShelf,
                               isEmpty: store.items.isEmpty, dragActive: dragActive) { hide() }
    }

    func show(reason: ShowReason = .manual, at point: NSPoint = NSEvent.mouseLocation) {
        guard !isShown,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        else { return }
        self.reason = reason
        store.refreshMissing()
        // Not during an auto-drag show: a first feed landing mid-drag would add the footer row and grow the panel.
        if reason != .autoDrag { Task { await promos.refreshIfStale() } }
        updateMaxHeight(for: screen)
        let frame = self.frame(size: panel.contentView?.fittingSize ?? .zero, on: screen)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Slides down from just under the menu bar while fading in; Reduce Motion → fade only.
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Self.slide), display: false)
        panel.alphaValue = 0
        // Hotkey: key panel so arrows, Space, Cmd-C, Esc work without the mouse (T-11 AC-4).
        // Menu and auto-show stay non-key (T-14 AC-X). None activates the app.
        if reason == .hotkey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { isShown = true }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.2 : 0.35
            // Critically damped spring-like ease-out (no overshoot on a window frame).
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        })
    }

    /// Quick Look on one tile (context menu, VoiceOver): acts on the selection if the tile is in it.
    func quickLook(_ id: UUID) {
        store.selection = store.targetIDs(for: id)
        panel.openPreview()
    }

    /// VoiceOver: low-priority "Item added" when the shelf grows (T-11 AC-1).
    func announceAdded(_ count: Int) {
        let text = count == 1 ? "Item added" : "\(count) items added"
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }

    func previewSourceChanged() {
        panel.syncPreview()
    }

    func hide() {
        guard isShown else { return }
        reason = nil
        panel.closePreview()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { isShown = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
            if !reduceMotion { panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: Self.slide), display: true) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// Fades/slides via the window (controller); adds the 0.96→1 top-anchored spring scale unless Reduce Motion is on.
private struct PanelRoot: View {
    let controller: ShelfPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preferences.showPromos) private var showPromos = true

    var body: some View {
        // Re-evaluated on every show (reads `isShown`), so the daily rotation advances.
        ShelfView(store: controller.store, maxHeight: controller.maxHeight, onClose: controller.hide,
                  onQuickLook: controller.quickLook, onMoved: controller.userMoved,
                  onResetPosition: controller.resetPosition,
                  promo: showPromos ? controller.promos.footerPromo : nil,
                  onDismissPromo: controller.promos.dismiss)
            .scaleEffect(controller.isShown || reduceMotion ? 1 : 0.96, anchor: .top)
            // Last item gone (drag out, remove, clear) → hide (ARCHITECTURE §5 rule 4).
            .onChange(of: controller.store.items.isEmpty) { _, empty in if empty { controller.hide() } }
            .onChange(of: controller.store.items.count) { old, new in if new > old { controller.announceAdded(new - old) } }
            // Quick Look follows any selection/items change, not only keys.
            .onChange(of: controller.store.previewURLs) { controller.previewSourceChanged() }
            // Async: `fittingSize` read synchronously here is 0 and would collapse the panel.
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { _ in
                Task { @MainActor in controller.fitToContent() }
            }
    }
}
