import AppKit
import SwiftUI

/// Shows, hides, and positions the shelf panel. Never activates the app (ARCHITECTURE §5 rule 6).
@Observable
final class ShelfPanelController {
    /// `.hotkey` is the only reason that makes the panel key (T-14 AC-X): menu and auto-show leave keyboard
    /// focus with the frontmost app.
    enum ShowReason { case manual, hotkey, autoDrag }

    private(set) var isShown = false
    /// Panel width and height cap: the user's resized size on this screen, else defaults (T-13 AC-2, T-16 AC-6).
    fileprivate var width: CGFloat = ShelfView.defaultWidth
    fileprivate var maxHeight: CGFloat = 600

    @ObservationIgnored let store: ShelfStore
    @ObservationIgnored let promos: PromoLoader
    @ObservationIgnored private let panel = ShelfPanel()
    @ObservationIgnored private var receiver: DropReceiver<PanelRoot>!  // set in init, after self is usable
    @ObservationIgnored private(set) var reason: ShowReason?
    @ObservationIgnored private var droppedOnShelf = false
    @ObservationIgnored private var dragActive = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    /// Shelf pet (V3-01); set in init.
    @ObservationIgnored private(set) var pet: PetController!

    /// Gap below the menu bar / notch, and the entry slide distance.
    static let topInset: CGFloat = 12
    private static let slide: CGFloat = 10
    /// UserDefaults key: [screen id: [dx, dy]], panel top-center offset from the visibleFrame's top center (T-13 AC-5).
    static let offsetsKey = "panelOffsets"
    /// UserDefaults key: [screen id: [width, height]], the user's resized panel size (T-16 AC-7).
    static let sizesKey = "panelSizes"

    init(store: ShelfStore, promos: PromoLoader) {
        self.store = store
        self.promos = promos
        pet = PetController(shelf: panel, store: store) // Before the content view: it reads `pet`.
        receiver = DropReceiver(rootView: PanelRoot(controller: self))
        receiver.store = store
        receiver.onDrop = { [weak self] in
            self?.droppedOnShelf = true
            self?.store.hints.record(.dropped)
        }
        receiver.onPromiseFailed = { [weak self] in self?.promiseFailed() }
        panel.contentView = receiver
        panel.store = store
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onPetCall = { [weak self] p in self?.pet.call(at: p) }
        panel.onUserResize = { [weak self] ended in ended ? self?.userResized() : self?.liveResized() }
        panel.minSize = ShelfView.minSize
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

    /// New size with the top center fixed; near the screen bottom it shifts up to stay inside `visible`.
    static func fit(_ frame: NSRect, size: NSSize, in visible: NSRect) -> NSRect {
        clamp(NSRect(x: (frame.midX - size.width / 2).rounded(), y: frame.maxY - size.height,
                     width: size.width, height: size.height), to: visible)
    }

    /// Width and height cap on `visible`: the user's size there (its height is the max, content still fits below it,
    /// T-16 AC-6), else the default width and min(4.5 rows, 50% of the visible height) (T-13 AC-2).
    /// Clamped to `ShelfView.minSize` … `visible` (T-16 AC-5).
    static func limits(saved: NSSize?, in visible: NSRect) -> (width: CGFloat, maxHeight: CGFloat) {
        let w = saved?.width ?? ShelfView.defaultWidth
        let h = (saved?.height ?? min(ShelfView.maxContentHeight, (visible.height * 0.5).rounded()))
        return (max(ShelfView.minSize.width, min(w, visible.width)),
                max(ShelfView.minSize.height, min(h, visible.height)))
    }

    /// Per-screen pair saved under `key` (offsets, sizes).
    static func saved(_ key: String, screen: String, in defaults: UserDefaults = .standard) -> [Double]? {
        guard let pair = (defaults.dictionary(forKey: key) as? [String: [Double]])?[screen], pair.count == 2 else { return nil }
        return pair
    }

    static func save(_ pair: [Double], as key: String, screen: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        all[screen] = pair
        defaults.set(all, forKey: key)
    }

    /// Reset: forget every saved spot and size (T-16 AC-7).
    static func forgetPlacement(in defaults: UserDefaults = .standard) {
        for key in [offsetsKey, sizesKey] { defaults.removeObject(forKey: key) }
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

    /// Frame on `screen` for content `size`: saved spot if any, else top center (T-08 AC-9).
    private func frame(size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        if let o = Self.saved(Self.offsetsKey, screen: Self.id(of: screen)) {
            return Self.frame(size: size, offset: CGPoint(x: o[0], y: o[1]), in: visible)
        }
        return Self.topCenterFrame(size: size, in: visible, safeTop: screen.frame.maxY - screen.safeAreaInsets.top)
    }

    /// Header drag ended: remember the spot for the panel's current screen.
    func userMoved() {
        guard let screen = panel.screen else { return }
        let o = Self.offset(of: panel.frame, in: screen.visibleFrame)
        Self.save([o.x, o.y], as: Self.offsetsKey, screen: Self.id(of: screen))
        updateLimits(for: screen)
    }

    /// Edge drag in progress: tiles reflow to the new width, the grid cap follows the height. Auto-fit is paused.
    private func liveResized() {
        let size = panel.frame.size
        if size.width != width { width = size.width }
        if size.height != maxHeight { maxHeight = size.height }
    }

    /// Edge drag ended: the size becomes this screen's width and max height; content fits below it (T-16 AC-6/7).
    private func userResized() {
        guard let screen = panel.screen else { return }
        Self.save([panel.frame.width, panel.frame.height], as: Self.sizesKey, screen: Self.id(of: screen))
        userMoved() // A left-edge drag moved the top center too.
        Task { @MainActor in
            fitToContent()
            panel.invalidateShadow()
        }
    }

    /// Width and height cap for `screen` (T-11 AC-8: also after a move to another screen). Set only on change:
    /// every set re-renders the view.
    private func updateLimits(for screen: NSScreen) {
        let saved = Self.saved(Self.sizesKey, screen: Self.id(of: screen)).map { NSSize(width: $0[0], height: $0[1]) }
        let limits = Self.limits(saved: saved, in: screen.visibleFrame)
        if limits.width != width { width = limits.width }
        if limits.maxHeight != maxHeight { maxHeight = limits.maxHeight }
        panel.maxSize = screen.visibleFrame.size
        panel.minSize = NSSize(width: ShelfView.minSize.width, height: ShelfView.minSize.height)
    }

    /// Menu item / Settings / header double-click: forget all saved spots and sizes, back to top center.
    func resetPosition() {
        Self.forgetPlacement()
        guard isShown, let screen = panel.screen else { return }
        updateLimits(for: screen)
        panel.setFrame(frame(size: NSSize(width: width, height: panel.frame.height), on: screen), display: true,
                       animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Resizes the shown panel to its content, top center fixed (T-13 AC-1). Called async after a geometry change:
    /// `fittingSize` is 0 inside the callback. Paused while the user drags an edge (T-16 AC-6).
    func fitToContent() {
        guard isShown, !panel.inLiveResize, let screen = panel.screen else { return }
        updateLimits(for: screen)
        guard let size = panel.contentView?.fittingSize, size.height > 0,
              abs(size.height - panel.frame.height) >= 0.5 || abs(size.width - panel.frame.width) >= 0.5 else { return }
        panel.setFrame(Self.fit(panel.frame, size: size, in: screen.visibleFrame), display: true)
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
        pet.dragSessionStarted()
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
        Task { await store.sweep() }
        store.showRecent = false
        store.resizing = nil
        let hasFile = store.items.contains { if case .file = $0.kind { true } else { false } }
        store.hints.record(.shown(reason, hasFile: hasFile, hasRecent: !store.recent.isEmpty, itemCount: store.items.count))
        store.hints.visible = true
        // Not during an auto-drag show: a first feed landing mid-drag would add the footer row and grow the panel.
        if reason != .autoDrag { Task { await promos.refreshIfStale() } }
        updateLimits(for: screen)
        // Width from the limits: `fittingSize` may still reflect the previous width; height is re-fit async.
        let frame = self.frame(size: NSSize(width: width, height: panel.contentView?.fittingSize.height ?? 0), on: screen)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Slides down from just under the menu bar while fading in; Reduce Motion → fade only.
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Self.slide), display: false)
        panel.alphaValue = 0
        // Hotkey: key panel so arrows, Space, Cmd-C, Esc work without the mouse (T-11 AC-4).
        // Menu and auto-show stay non-key (T-14 AC-X). None activates the app.
        if reason == .hotkey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        pet.shelfDidShow()
        // Shadow again once the 0.96→1 scale settles: one taken mid-spring is smaller than the glass (T-16 AC-2).
        withAnimation(.spring(duration: 0.35, bounce: 0.15), completionCriteria: .removed) { isShown = true }
            completion: { [weak self] in self?.panel.invalidateShadow() }
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

    /// Menu "Paste to DragShelf": shows the panel (not key, app not activated) and adds the clipboard (V2-06 AC-2).
    func paste() {
        show()
        receiver.pasteItems()
    }

    /// Menu "Undo Drag Out": restores the last drag out and shows the panel with it (T-17 AC-2).
    func undoDragOut() {
        if store.undoDragOut() { show() }
    }

    /// Quick Look on one tile (context menu, VoiceOver): acts on the selection if the tile is in it.
    func quickLook(_ id: UUID) {
        store.selection = store.targetIDs(for: id)
        panel.openPreview()
    }

    /// VoiceOver: low-priority "Item added" when the shelf grows (T-11 AC-1).
    func announceAdded(_ count: Int) {
        announce(count == 1 ? "Item added" : "\(count) items added")
    }

    /// Low-priority VoiceOver announcement (item added, a tip appeared).
    func announce(_ text: String) {
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }

    func previewSourceChanged() {
        panel.syncPreview()
    }

    func hide() {
        guard isShown else { return }
        reason = nil
        panel.makeFirstResponder(nil) // Commits an open rename field (V2-04 AC-2).
        store.hints.visible = false
        store.actions.message = nil
        store.resetSearch() // V2-10 AC-4
        panel.closePreview()
        pet.shelfDidHide()
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
    @AppStorage(Preferences.showTips) private var showTips = true

    var body: some View {
        // Re-evaluated on every show (reads `isShown`), so the daily rotation advances.
        ShelfView(store: controller.store, width: controller.width, maxHeight: controller.maxHeight,
                  onClose: controller.hide,
                  onQuickLook: controller.quickLook, onMoved: controller.userMoved,
                  onResetPosition: controller.resetPosition,
                  promo: showPromos ? controller.promos.footerPromo : nil,
                  onDismissPromo: controller.promos.dismiss,
                  hint: showTips ? controller.store.hints.current : nil,
                  onDismissHint: controller.store.hints.dismiss,
                  pet: controller.pet.petOn ? controller.pet : nil)
            .scaleEffect(controller.isShown || reduceMotion ? 1 : 0.96, anchor: .top)
            // Last item gone (drag out, remove, clear) → hide (ARCHITECTURE §5 rule 4).
            .onChange(of: controller.store.items.isEmpty) { _, empty in if empty { controller.hide() } }
            .onChange(of: controller.store.items.count) { old, new in if new > old { controller.announceAdded(new - old) } }
            .onChange(of: controller.store.hints.current) { _, hint in if let hint { controller.announce(hint.spokenText) } }
            // Quick Look follows any selection/items change, not only keys.
            .onChange(of: controller.store.previewURLs) { controller.previewSourceChanged() }
            // Async: `fittingSize` read synchronously here is 0 and would collapse the panel.
            .onGeometryChange(for: CGSize.self, of: \.size) { _ in
                Task { @MainActor in controller.fitToContent() }
            }
            // Top-pinned in the window: while an edge drag makes the window taller than the content, or before an
            // async fit lands, the header stays put (T-16 AC-4).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
