import AppKit
import SwiftUI

/// Shows, hides, and positions the shelf panel. Never activates the app (ARCHITECTURE §5 rule 6).
@Observable
final class ShelfPanelController {
    enum ShowReason { case manual, autoDrag }

    private(set) var isShown = false
    /// Panel height cap: 70% of the cursor screen's visible height (ARCHITECTURE §6).
    fileprivate var maxHeight: CGFloat = 600

    @ObservationIgnored let store: ShelfStore
    @ObservationIgnored private let panel = ShelfPanel()
    @ObservationIgnored private(set) var reason: ShowReason?
    @ObservationIgnored private var droppedOnShelf = false
    @ObservationIgnored private var dragActive = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Gap below the menu bar / notch, and the entry slide distance.
    static let topInset: CGFloat = 12
    private static let slide: CGFloat = 10

    init(store: ShelfStore) {
        self.store = store
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

    /// Visibility rule 2 (ARCHITECTURE §5): only an auto-shown, still-empty shelf that got no drop hides.
    static func shouldAutoHide(reason: ShowReason?, droppedOnShelf: Bool, isEmpty: Bool, dragActive: Bool) -> Bool {
        reason == .autoDrag && !droppedOnShelf && isEmpty && !dragActive
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func dragStarted(at point: NSPoint) {
        hideTask?.cancel()
        dragActive = true
        droppedOnShelf = false
        show(reason: .autoDrag, at: point)
    }

    /// 250 ms grace lets an in-flight drop land first (+0.2 s fade stays under AC-3's 500 ms).
    func dragEnded() {
        dragActive = false
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
        let visible = screen.visibleFrame
        maxHeight = visible.height * 0.7
        let frame = Self.topCenterFrame(size: panel.contentView?.fittingSize ?? .zero, in: visible,
                                        safeTop: screen.frame.maxY - screen.safeAreaInsets.top)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Slides down from just under the menu bar while fading in; Reduce Motion → fade only.
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Self.slide), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
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

    var body: some View {
        ShelfView(store: controller.store, maxHeight: controller.maxHeight, onClose: controller.hide,
                  onQuickLook: controller.quickLook)
            .scaleEffect(controller.isShown || reduceMotion ? 1 : 0.96, anchor: .top)
            // Last item gone (drag out, remove, clear) → hide (ARCHITECTURE §5 rule 4).
            .onChange(of: controller.store.items.isEmpty) { _, empty in if empty { controller.hide() } }
    }
}
