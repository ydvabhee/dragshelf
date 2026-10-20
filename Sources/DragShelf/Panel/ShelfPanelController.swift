import AppKit
import SwiftUI

/// Shows, hides, and positions the shelf panel. Never activates the app (ARCHITECTURE §5 rule 6).
@Observable
final class ShelfPanelController {
    private(set) var isShown = false
    /// Panel height cap: 70% of the cursor screen's visible height (ARCHITECTURE §6).
    fileprivate var maxHeight: CGFloat = 600

    @ObservationIgnored let store: ShelfStore
    @ObservationIgnored private let panel = ShelfPanel()

    init(store: ShelfStore) {
        self.store = store
        let receiver = DropReceiver(rootView: PanelRoot(controller: self))
        receiver.store = store
        panel.contentView = receiver
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        maxHeight = visible.height * 0.7
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setFrame(NSRect(x: visible.maxX - size.width - 12, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { isShown = true }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        })
    }

    func hide() {
        guard isShown else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { isShown = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// Fades via window alpha (controller); adds the 0.96→1 spring scale unless Reduce Motion is on.
private struct PanelRoot: View {
    let controller: ShelfPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ShelfView(store: controller.store, maxHeight: controller.maxHeight, onClose: controller.hide)
            .scaleEffect(controller.isShown || reduceMotion ? 1 : 0.96)
    }
}
