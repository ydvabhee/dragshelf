import AppKit
import os
import SwiftUI

private let log = Logger(subsystem: PromoConfig.selfBundleID, category: "pet")

// Shelf pet (V3-01): a cat on the shelf's bottom rim (an overlay on the panel content), driven by `PetBrain`.

extension Preferences {
    static let petEnabled = "petEnabled"
    static let petPersonality = "petPersonality"
    static let petName = "petName"
    /// Preview on the 2nd and 3rd drag session, then ask once (default off).
    static let petPreview = "petPreview"
    static let petSessions = "petSessions"
    static let petAsked = "petAsked"
    /// The "Hey, I'm Mochi!" intro bubble was dismissed by a click; Reset Tips and Show preview clear it.
    static let petIntroSeen = "petIntroSeen"
    /// Internal kill switch: `defaults write com.abhishekyadav.DragShelf petFeature -bool NO` removes the pet entirely.
    static let petFeature = "petFeature"
    static let defaultPetName = "Mochi"

    static func petFeatureOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: petFeature) as? Bool ?? true }

    static func petMode(_ d: UserDefaults = .standard) -> PetOptIn.Mode {
        PetOptIn.mode(feature: petFeatureOn(d), enabled: d.bool(forKey: petEnabled), preview: d.bool(forKey: petPreview),
                      sessions: d.integer(forKey: petSessions), asked: d.bool(forKey: petAsked))
    }

    static func petPersonalityChoice(_ d: UserDefaults = .standard) -> PetPersonality {
        d.string(forKey: petPersonality).flatMap(PetPersonality.init(rawValue:)) ?? .curious
    }

    static func petDisplayName(_ d: UserDefaults = .standard) -> String {
        let name = (d.string(forKey: petName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? defaultPetName : String(name.prefix(20))
    }

    /// Counts drag sessions only while the preview flow still needs them.
    static func recordPetSession(_ d: UserDefaults = .standard) {
        let sessions = d.integer(forKey: petSessions)
        guard petFeatureOn(d), d.bool(forKey: petPreview), !d.bool(forKey: petEnabled), !d.bool(forKey: petAsked),
              sessions < 4 else { return }
        d.set(sessions + 1, forKey: petSessions)
    }

    /// The one question: Keep → pet on; No thanks or ignored → stays off. Never asked again either way.
    static func answerPetQuestion(keep: Bool, _ d: UserDefaults = .standard) {
        // Enabled first: the pet never flips to "off" in between and leaves.
        if keep { d.set(true, forKey: petEnabled) }
        d.set(true, forKey: petAsked)
    }

    /// Right-click → Send home: the pet setting turns off (and no preview comes back).
    static func sendPetHome(_ d: UserDefaults = .standard) {
        d.set(false, forKey: petEnabled)
        d.set(true, forKey: petAsked)
    }
}


/// What the cat overlay draws right now.
struct PetSnapshot: Equatable {
    var frame: PetFrame
    /// Cat centre on the rim track.
    var x: Double
    var facingRight: Bool
    /// Ball centre on the rim track (nil = no ball shown).
    var ball: Double?
    var ballSpin = 0.0
    var bubble: String?
    /// Height off the rim mid-jump.
    var lift = 0.0
}

/// Runs the shelf pet (V3-01): feeds `PetBrain` time and shelf events, publishes what the cat overlay draws.
/// The cat stands on the shelf's bottom rim over the panel's own background (`PetStage`): no band, no layout.
@Observable
final class PetController {
    /// Overlay height (the sprite canvas), the cat's feet above the panel's bottom edge, and where the cat's
    /// track starts (the sprite is centred on it, so a cat at -72 is fully out of view).
    static let stageHeight: CGFloat = 64
    nonisolated static let rimInset: CGFloat = 4
    nonisolated static let trackInset: CGFloat = 40
    static let favoriteKey = "petFavoriteSpot"

    /// Pet on (or previewing / asking): the shelf shows the cat.
    private(set) var petOn = false
    /// Drawn state; set by the controller (and by snapshot tests).
    var snapshot: PetSnapshot?
    private(set) var asking = false
    /// Per-tile wiggles; a new `count` wiggles that tile once. Set by the controller (and by snapshot tests).
    var wiggles: [UUID: TileWiggle] = [:]
    private(set) var name = Preferences.defaultPetName
    /// The tip in the cat's speech bubble right now. Set by the controller (and by snapshot tests).
    var tip: HintEngine.Hint?
    /// The cat tells every tip (pet on or previewing); the footer never shows one. Pet off or the question: footer.
    private(set) var tipsOnStage = false

    /// Overlay frame in the panel's content coordinates (top-left origin), reported by `PetStage`.
    @ObservationIgnored var stageFrame: CGRect = .zero { didSet { if stageFrame.width != oldValue.width { layout() } } }
    /// Tile frames and the grid's visible area, same space as `stageFrame` (reported by `ShelfView`). Tiles the grid
    /// has not laid out, or that are scrolled away, are not on screen; the cat never plays with those.
    @ObservationIgnored var tileFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var gridFrame: CGRect?
    /// The Recent (clock) button's centre x, same space as `stageFrame`.
    @ObservationIgnored var clockX: CGFloat?
    /// The tip the cat was sent to tell (it stays current in `HintEngine` after the bubble fades).
    @ObservationIgnored private(set) var delivered: HintEngine.Hint?
    @ObservationIgnored private var brain: PetBrain
    @ObservationIgnored private let shelf: NSWindow
    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var mode = PetOptIn.Mode.off
    @ObservationIgnored private var shelfShown = false
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var askShown = false
    /// The intro bubble is up; it stays until a click on the shelf (or `introCap` seconds).
    @ObservationIgnored private(set) var introShowing = false
    @ObservationIgnored private var introCapTask: Task<Void, Never>?
    @ObservationIgnored private var clickMonitor: Any?
    static let introCap: Duration = .seconds(30)
    @ObservationIgnored private var itemIDs: [UUID] = []
    @ObservationIgnored private var personality = PetPersonality.curious
    @ObservationIgnored private let tracker = PointerTracker()

    init(shelf: NSWindow, store: ShelfStore, defaults: UserDefaults = .standard) {
        self.shelf = shelf
        self.store = store
        self.defaults = defaults
        brain = PetBrain(traits: PetPersonality.curious.traits, seed: UInt64.random(in: 0...UInt64.max))
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prefsChanged() }
        }
        tracker.onPointer = { [weak self] p in self?.pointer(p) }
        prefsChanged()
        observeStore()
    }

    private static func now() -> TimeInterval { Date.timeIntervalSinceReferenceDate }

    // MARK: Shelf hooks

    func dragSessionStarted() { Preferences.recordPetSession(defaults) }

    func shelfDidShow() {
        shelfShown = true
        refresh()
    }

    func shelfDidHide() {
        shelfShown = false
        refresh()
    }

    // MARK: User actions

    func petTapped() {
        brain.pet(now: Self.now())
        reschedule()
    }

    /// The intro comes first (pet on or previewing) until a click has dismissed it once; tips wait for it.
    var introPending: Bool { [.on, .preview].contains(mode) && !defaults.bool(forKey: Preferences.petIntroSeen) }

    static func introText(name: String) -> String { "Hey, I'm \(name)!" }

    /// Any click on the shelf (it still does its normal action): the intro is seen; a tip bubble goes away unlearned.
    /// A left click-up on the tip bubble itself learns it first (`tipLearned` clears `tip`), so that path is a no-op.
    func shelfClicked(tipToo: Bool = true) {
        if introShowing {
            introShowing = false
            introCapTask?.cancel()
            defaults.set(true, forKey: Preferences.petIntroSeen)
            refreshTips()
        }
        if tipToo, tip != nil {
            brain.hideTip()
            tip = nil
            reschedule()
        }
    }

    func sendHome() { Preferences.sendPetHome(defaults) }

    /// Clicked the tip bubble: learned, never shown again; the cat does a happy bounce.
    func tipLearned() {
        store.hints.dismiss()
        tip = nil
        brain.tipLearned(now: Self.now())
        reschedule()
    }

    func answer(keep: Bool) {
        asking = false
        askShown = false
        Preferences.answerPetQuestion(keep: keep, defaults)
    }

    /// Settings → Pet → Play with ball: the cat fetches its ball now (if it is on the shelf).
    func playBall() {
        guard attached else { return }
        brain.playBall(now: Self.now())
        reschedule()
    }

    /// Pointer over the panel at `p` (content coordinates, top-left origin; nil = it left). Reported by
    /// `PointerTracker` only while the cat is on a shown shelf; nothing watches the mouse otherwise.
    func pointer(_ p: CGPoint?) {
        guard attached else { return }
        brain.cursorMoved(p.map(rim), now: Self.now())
        log.debug("cursor \(String(describing: p), privacy: .public) last response \(String(describing: self.brain.lastResponse), privacy: .public)")
        reschedule()
    }

    /// Double-click on the cat or on empty shelf space (`ShelfPanel.onPetCall`): the cat comes to jump at it.
    func call(at p: CGPoint) {
        guard attached else { return }
        log.debug("call at \(p.x, privacy: .public), \(p.y, privacy: .public)")
        brain.call(at: rim(p), now: Self.now())
        reschedule()
    }

    private func rim(_ p: CGPoint) -> SIMD2<Double> {
        Self.rim(p, stage: stageFrame.height > 0 ? stageFrame
            : CGRect(x: 0, y: (shelf.contentView?.bounds.height ?? 0) - Self.stageHeight, width: shelf.frame.width, height: Self.stageHeight))
    }

    /// Content point → rim coordinates: x along the cat's track, y above the rim (up = +). `stage` = `stageFrame`.
    nonisolated static func rim(_ p: CGPoint, stage: CGRect) -> SIMD2<Double> {
        SIMD2(Double(p.x - stage.minX - trackInset), Double(stage.maxY - rimInset - p.y))
    }

    // MARK: State

    private func refresh() {
        let want = shelfShown && mode != .off
        if want && !attached { attach() } else if !want && attached { detach() }
        refreshTips()
    }

    /// Hands a new tip to the cat when it is on stage (Settings → Tips off: none).
    private func refreshTips() {
        let routed = [.on, .preview].contains(mode)
        if routed != tipsOnStage { tipsOnStage = routed }
        let onStage = attached && routed
        let hint = Preferences.tipsOn(defaults) && !introPending ? store.hints.current : nil
        guard hint != delivered else { return }
        // A tip waits (undelivered) through a drag; the cat comes back and tells it afterwards.
        if onStage && (store.isDragging || store.isDropTargeted) && hint != nil { return }
        delivered = onStage ? hint : nil
        guard onStage, let hint else { return }
        let gesture = Self.gesture(for: hint)
        brain.deliverTip(gesture, target: tipTarget(hint, gesture), now: Self.now())
        reschedule()
    }

    /// How the cat acts out each tip.
    static func gesture(for hint: HintEngine.Hint) -> PetBrain.TipGesture {
        switch hint {
        case .firstDrop: .patRim
        case .paste, .dragOut: .pawTap
        case .holdCommand: .nudgeTile
        case .recent, .moveResize: .pointUp
        case .pin: .pointAtTile
        case .hotkey: .wave
        case .clear: .shrug
        case .search: .lookAround
        }
    }

    /// Where the gesture goes on the rim: under the clock button (Recent), the on-screen bottom-row tile nearest
    /// the cat (nudge, pin), else nowhere in particular.
    private func tipTarget(_ hint: HintEngine.Hint, _ gesture: PetBrain.TipGesture) -> Double? {
        switch gesture {
        case .pointUp:
            guard hint == .recent, let clockX else { return nil }
            return Double(clockX - stageFrame.minX - Self.trackInset)
        case .nudgeTile, .pointAtTile:
            return visibleRow().min { abs($0.x - brain.x) < abs($1.x - brain.x) }?.x
        default: return nil
        }
    }

    private func prefsChanged() {
        let newName = Preferences.petDisplayName(defaults)
        if newName != name { name = newName }
        let newMode = Preferences.petMode(defaults)
        let choice = Preferences.petPersonalityChoice(defaults)
        if choice != personality {
            personality = choice
            brain.traits = choice.resolved(using: &brain.rng).traits
        }
        guard newMode != mode else { return refreshTips() }
        mode = newMode
        if petOn != (mode != .off) { petOn = mode != .off }
        // Kept after the question: back to normal motion, same pet.
        if mode != .ask && asking {
            asking = false
            brain.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        refresh()
    }

    private func attach() {
        attached = true
        brain.traits = personality.resolved(using: &brain.rng).traits
        brain.hour = Calendar.current.component(.hour, from: Date())
        brain.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        itemIDs = store.visibleItems.map(\.id)
        layout()
        // Favorite nap nook: a floor corner, picked once and remembered.
        if defaults.object(forKey: Self.favoriteKey) == nil { defaults.set(Bool.random() ? 0.0 : 1.0, forKey: Self.favoriteKey) }
        brain.favorite = defaults.double(forKey: Self.favoriteKey) * brain.track
        brain.shelfShown(hasItems: !store.items.isEmpty, now: Self.now())
        if mode == .preview || mode == .ask { brain.place(at: 0) } // Room for the bubble beside it.
        brain.setDragging(store.isDragging || store.isDropTargeted, now: Self.now())
        brain.tiles = visibleRow().map(\.x)
        if let view = shelf.contentView { tracker.install(on: view) }
        installClickMonitor()
        reschedule()
    }

    private func detach() {
        attached = false
        tracker.remove()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        introShowing = false
        introCapTask?.cancel()
        if askShown { answer(keep: false) } // Ignored counts as "No thanks".
        loop?.cancel()
        loop = nil
        brain.shelfHidden(now: Self.now())
        wiggles = [:]
        tileFrames = [:]
        delivered = nil
        tip = nil
        snapshot = nil
    }

    /// Local monitor, this panel only; the event always passes on untouched. Downs dismiss at once (a right-click's
    /// menu would swallow the up); a left tip click waits for its up, deferred so the bubble's own action runs first.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]) { [weak self] event in
            nonisolated(unsafe) let e = event // Monitors run on the main thread.
            MainActor.assumeIsolated {
                guard let self, e.window === self.shelf else { return }
                if e.type == .leftMouseUp {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.shelfClicked() } }
                } else {
                    self.shelfClicked(tipToo: e.type == .rightMouseDown)
                }
            }
            return event
        }
    }

    /// Track length follows the panel width.
    private func layout() {
        let width = stageFrame.width > 0 ? stageFrame.width : shelf.frame.width
        guard width > 0 else { return }
        brain.track = max(0, Double(width - 2 * Self.trackInset))
    }

    /// The lowest row of tiles that are on screen (at least 60% of the tile inside `viewport`), left to right, as
    /// (id, centre x). Tiles scrolled away or never laid out are left out.
    nonisolated static func bottomRow(_ frames: [UUID: CGRect], viewport: CGRect) -> [(id: UUID, x: CGFloat)] {
        let shown = frames.filter { $0.value.height > 0 && $0.value.intersection(viewport).height >= 0.6 * $0.value.height }
        guard let lowest = shown.values.map(\.minY).max() else { return [] }
        return shown.filter { abs($0.value.minY - lowest) < 4 }.map { (id: $0.key, x: $0.value.midX) }.sorted { $0.x < $1.x }
    }

    /// The on-screen bottom row on the rim track.
    private func visibleRow() -> [(id: UUID, x: Double)] {
        guard let grid = gridFrame, !store.showRecent, store.resizing == nil else { return [] }
        let ids = Set(store.visibleItems.map(\.id))
        return Self.bottomRow(tileFrames.filter { ids.contains($0.key) }, viewport: grid)
            .map { (id: $0.id, x: Double($0.x - stageFrame.minX - Self.trackInset)) }
    }

    /// Drags (in, out, over the shelf) and item changes; re-arms itself (Observation fires once per registration).
    private func observeStore() {
        withObservationTracking {
            _ = (store.isDragging, store.isDropTargeted, store.items.count, store.query, store.hints.current)
        } onChange: { [weak self] in
            Self.onMain { self?.storeChanged() }()
        }
    }

    /// Observation may call back on the thread that made the change; hop to main (ADR-016).
    nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) -> @Sendable () -> Void {
        { Task { @MainActor in work() } }
    }

    private func storeChanged() {
        observeStore()
        guard attached else { return }
        let now = Self.now()
        brain.setDragging(store.isDragging || store.isDropTargeted, now: now)
        let ids = store.visibleItems.map(\.id)
        if ids != itemIDs {
            let added = ids.first { !itemIDs.contains($0) }
            let removed = itemIDs.first { !ids.contains($0) }
            let grew = ids.count > itemIDs.count
            itemIDs = ids
            let removedX = grew ? nil : removed.flatMap { id in visibleRow().first { $0.id == id }?.x }
            brain.itemsChanged(count: store.items.count, addedAt: nil, removedAt: removedX, now: now)
            if grew, let added { playWithNewTile(added) }
        }
        refreshTips()
        reschedule()
    }

    /// A tile arrived: once the grid has laid it out and scrolled to it, the cat goes to play with it, or with the
    /// on-screen bottom-row tile nearest it when it landed elsewhere.
    private func playWithNewTile(_ id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.35))
            guard let self, self.attached else { return }
            let row = self.visibleRow()
            let near = self.tileFrames[id].map { Double($0.midX - self.stageFrame.minX - Self.trackInset) } ?? self.brain.x
            let target = row.first { $0.id == id } ?? row.min { abs($0.x - near) < abs($1.x - near) }
            self.brain.tiles = row.map(\.x)
            self.brain.itemsChanged(count: self.store.items.count, addedAt: target?.x, removedAt: nil, now: Self.now())
            self.reschedule()
        }
    }

    /// Ticks now, then sleeps until the brain next needs time. No timer at all while nothing can change.
    private func reschedule() {
        loop?.cancel()
        step()
        guard let wait = brain.nextWake(now: Self.now()) else { return loop = nil }
        loop = Task { [weak self] in
            var wait = wait
            while true {
                guard (try? await Task.sleep(for: .seconds(wait))) != nil, let self else { return }
                self.step()
                guard let next = self.brain.nextWake(now: Self.now()) else { return }
                wait = next
            }
        }
    }

    private func step() {
        guard attached else { return }
        let now = Self.now()
        let wasVisible = brain.isVisible, bats = brain.tileBats, knocks = brain.tileKnocks
        let row = visibleRow()
        brain.tiles = row.map(\.x)
        brain.tick(now: now)
        if brain.tileBats != bats || brain.tileKnocks != knocks { wiggleTile(row, knock: brain.tileKnocks != knocks) }
        if brain.isVisible && !wasVisible { appeared(now) }
        publish(now)
    }

    /// First appearance this show: the intro bubble or the question.
    private func appeared(_ now: TimeInterval) {
        switch mode {
        case .ask where !askShown:
            askShown = true
            asking = true
            brain.reduceMotion = true // Sits still beside the question.
        default:
            showIntro()
        }
    }

    func showIntro() {
        guard introPending, !introShowing else { return }
        introShowing = true
        introCapTask?.cancel()
        introCapTask = Task { [weak self] in
            try? await Task.sleep(for: Self.introCap)
            guard !Task.isCancelled else { return }
            self?.shelfClicked(tipToo: false) // Safety cap: counts as seen.
        }
    }

    private func publish(_ now: TimeInterval) {
        let bubbleTip = brain.isVisible && brain.tipShowing(at: now) ? delivered : nil
        if bubbleTip != tip { tip = bubbleTip }
        guard let frame = brain.frame(at: now) else {
            if snapshot != nil { snapshot = nil }
            return
        }
        var bubble: String?
        if [.purr, .headRub, .bodyRub].contains(frame.pose) { bubble = "purrr…" }
        if brain.routine == .call && frame.pose == .perk { bubble = "!" }
        if introShowing { bubble = Self.introText(name: name) }
        var ball: Double?
        if let b = brain.ball {
            if brain.ballGone {
                // Rolling off the end, out of view.
                let t = min(1, (now - brain.ballGoneAt) / 0.35)
                if t < 1 { ball = b + (b > 0 ? 1 : -1) * 40 * t }
            } else if brain.ballVisible {
                ball = b
            }
        }
        // Sleep is drawn facing right so the "z z" reads.
        let new = PetSnapshot(frame: frame, x: brain.x, facingRight: [.sleep, .peekEye].contains(frame.pose) || brain.facingRight,
                              ball: ball, ballSpin: brain.ballSpin, bubble: asking ? nil : bubble, lift: brain.lift(at: now))
        if new != snapshot { snapshot = new }
        let fav = brain.track > 0 ? brain.favorite / brain.track : 0
        if abs(fav - defaults.double(forKey: Self.favoriteKey)) > 0.01 { defaults.set(fav, forKey: Self.favoriteKey) }
    }

    /// Bat or knock a tile: the on-screen bottom-row tile nearest the cat wiggles (a knock shoves it toward the
    /// nearer edge and back). Purely visual; items never change.
    private func wiggleTile(_ row: [(id: UUID, x: Double)], knock: Bool) {
        guard let tile = row.min(by: { abs($0.x - brain.x) < abs($1.x - brain.x) }) else { return }
        let count = (wiggles[tile.id]?.count ?? 0) + 1
        wiggles[tile.id] = TileWiggle(count: count, knock: knock, toRight: tile.x > brain.track / 2)
    }

    /// The cat takes clicks only while it is in view.
    var interactive: Bool { brain.isInteractive }
}

/// Pointer over the whole shelf panel (V3-01) for the cat. An AppKit tracking area, `.activeAlways`: the app is
/// never active and the shelf is usually not the key window. Tracking areas never take clicks, so tiles and drags
/// are untouched. Installed only while the cat is on a shown shelf; moves are throttled to 30 Hz.
final class PointerTracker: NSResponder {
    static let minInterval: TimeInterval = 1.0 / 30
    /// Content point, top-left origin (nil = left the panel).
    var onPointer: (CGPoint?) -> Void = { _ in }
    private(set) weak var view: NSView?
    private(set) var area: NSTrackingArea?
    private var last: TimeInterval = -1

    func install(on view: NSView) {
        guard area == nil || self.view !== view else { return }
        remove()
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        view.addTrackingArea(area)
        self.view = view
        self.area = area
        last = -1
    }

    func remove() {
        if let area { view?.removeTrackingArea(area) }
        area = nil
        view = nil
    }

    override func mouseEntered(with event: NSEvent) { report(event, force: true) }
    override func mouseMoved(with event: NSEvent) { report(event, force: false) }
    override func mouseExited(with event: NSEvent) { onPointer(nil) }

    private func report(_ event: NSEvent, force: Bool) {
        guard let view, force || event.timestamp - last >= Self.minInterval else { return }
        last = event.timestamp
        let p = view.convert(event.locationInWindow, from: nil)
        onPointer(CGPoint(x: p.x, y: view.isFlipped ? p.y : view.bounds.height - p.y))
    }
}
