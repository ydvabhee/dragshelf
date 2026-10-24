import AppKit
import SwiftUI

// Shelf pet (V3-01): a transparent child window on the shelf's top edge, driven by `PetBrain`.

extension Preferences {
    static let petEnabled = "petEnabled"
    static let petPersonality = "petPersonality"
    static let petName = "petName"
    /// Preview on the 2nd and 3rd drag session, then ask once (default off).
    static let petPreview = "petPreview"
    static let petSessions = "petSessions"
    static let petAsked = "petAsked"
    /// Internal kill switch: `defaults write com.abhishekyadav.DragShelf petFeature -bool NO` removes the pet entirely.
    static let petFeature = "petFeature"
    static let defaultPetName = "Mochi"

    static func petFeatureOn(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: petFeature) as? Bool ?? true }

    static func petMode(_ d: UserDefaults = .standard) -> PetOptIn.Mode {
        PetOptIn.mode(feature: petFeatureOn(d), enabled: d.bool(forKey: petEnabled), preview: d.bool(forKey: petPreview),
                      sessions: d.integer(forKey: petSessions), asked: d.bool(forKey: petAsked))
    }

    static func petPersonalityChoice(_ d: UserDefaults = .standard) -> PetPersonality {
        d.string(forKey: petPersonality).flatMap(PetPersonality.init(rawValue:)) ?? .playful
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

/// Links the shelf view (yarn button, tile wiggle) to the pet. There is one shelf, so one hub.
@Observable
final class PetHub {
    static let shared = PetHub()
    /// Pet attached to the shown shelf: the header shows the yarn button.
    var available = false
    var ballOut = false
    /// Per-tile wiggle counters; a change wiggles that tile once.
    var wiggles: [UUID: Int] = [:]
    var name = Preferences.defaultPetName
    @ObservationIgnored var toggleBall: () -> Void = {}
}

/// What the pet window draws right now.
struct PetSnapshot: Equatable {
    var pose: PetPose
    var step: Int
    var progress: Double
    var x: Double
    var facingRight: Bool
    var ball: Double?
    var bubble: String?
}

@Observable
final class PetController {
    /// Window height above the shelf edge, how far it overlaps the shelf, and the track inset from each side
    /// (clear of the rounded corners).
    static let height = PetArt.size.height
    static let overlap = PetArt.size.height - PetArt.ground
    static let inset: CGFloat = 50
    /// Room the shelf keeps free above itself while the pet is on, so the cat is not under the menu bar.
    static let headroom: CGFloat = 50

    private(set) var snapshot: PetSnapshot?
    private(set) var width: CGFloat = ShelfView.defaultWidth
    private(set) var asking = false
    var name: String { hub.name }

    @ObservationIgnored let hub = PetHub.shared
    @ObservationIgnored var askRect: CGRect = .zero
    @ObservationIgnored private var brain: PetBrain
    @ObservationIgnored private let shelf: NSWindow
    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private let window = PetWindow()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var mode = PetOptIn.Mode.off
    @ObservationIgnored private var shelfShown = false
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var askShown = false
    @ObservationIgnored private var previewUntil: TimeInterval = 0
    @ObservationIgnored private var itemCount = 0
    @ObservationIgnored private var ballDragging = false
    @ObservationIgnored private var personality = PetPersonality.playful

    init(shelf: NSWindow, store: ShelfStore) {
        self.shelf = shelf
        self.store = store
        brain = PetBrain(traits: PetPersonality.playful.traits, seed: UInt64.random(in: 0...UInt64.max))
        let host = PetHostingView(rootView: PetStage(pet: self))
        host.sizingOptions = [] // The controller sizes the window to the shelf.
        window.contentView = host
        hub.toggleBall = { [weak self] in self?.toggleBall() }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prefsChanged() }
        })
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: shelf, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            })
        }
        prefsChanged()
        observeStore()
    }

    private static func now() -> TimeInterval { Date.timeIntervalSinceReferenceDate }

    /// Shelf placement: with the pet on, keep `headroom` free under the menu bar.
    static func reserve(_ visible: NSRect) -> NSRect {
        guard Preferences.petMode() != .off else { return visible }
        var v = visible
        v.size.height -= headroom
        return v
    }

    // MARK: Shelf hooks

    func dragSessionStarted() { Preferences.recordPetSession() }

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

    func sendHome() { Preferences.sendPetHome() }

    func answer(keep: Bool) {
        asking = false
        askShown = false
        Preferences.answerPetQuestion(keep: keep)
    }

    func dragBall(to viewX: CGFloat) {
        ballDragging = true
        brain.moveBall(to: Double(viewX - Self.inset), now: Self.now())
        reschedule()
    }

    func ballDragEnded() {
        ballDragging = false
        updateMouse()
    }

    private func toggleBall() {
        let now = Self.now()
        if hub.ballOut {
            hub.ballOut = false
            brain.removeBall(now: now)
        } else {
            hub.ballOut = true
            brain.moveBall(to: brain.x < brain.track / 2 ? brain.track * 0.85 : brain.track * 0.15, now: now)
        }
        reschedule()
    }

    // MARK: State

    /// Attach or detach for the current shelf visibility and mode.
    private func refresh() {
        let want = shelfShown && mode != .off
        if want && !attached { attach() } else if !want && attached { detach() }
    }

    private func prefsChanged() {
        hub.name = Preferences.petDisplayName()
        let newMode = Preferences.petMode()
        let choice = Preferences.petPersonalityChoice()
        if choice != personality {
            personality = choice
            brain.traits = choice.resolved(using: &brain.rng).traits
        }
        guard newMode != mode else { return }
        mode = newMode
        // Kept after the question: back to normal motion, same pet.
        if mode != .ask && asking {
            asking = false
            brain.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        refresh()
    }

    private func attach() {
        attached = true
        hub.available = true
        brain.traits = personality.resolved(using: &brain.rng).traits
        brain.hour = Calendar.current.component(.hour, from: Date())
        brain.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        itemCount = store.items.count
        layout()
        shelf.addChildWindow(window, ordered: .above)
        window.ignoresMouseEvents = true
        window.orderFront(nil)
        brain.shelfShown(hasItems: itemCount > 0, now: Self.now())
        brain.setDragging(store.isDragging || store.isDropTargeted, now: Self.now())
        // Mouse moves anywhere: clicks reach the window only over the pet, its ball, or the question.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.updateMouse()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in
            self?.updateMouse()
            return e
        }) {
            monitors.append(local)
        }
        reschedule()
    }

    private func detach() {
        attached = false
        if askShown { answer(keep: false) } // Ignored counts as "No thanks".
        loop?.cancel()
        loop = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        brain.shelfHidden(now: Self.now())
        hub.available = false
        hub.ballOut = false
        hub.wiggles = [:]
        previewUntil = 0
        snapshot = nil
        shelf.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func layout() {
        guard attached else { return }
        let f = shelf.frame
        window.setFrame(NSRect(x: f.minX, y: f.maxY - Self.overlap, width: f.width, height: Self.height), display: false)
        if width != f.width { width = f.width }
        brain.track = max(0, Double(f.width - 2 * Self.inset))
    }

    /// Drags (in, out, over the shelf) and item changes; re-arms itself (Observation fires once per registration).
    private func observeStore() {
        withObservationTracking {
            _ = (store.isDragging, store.isDropTargeted, store.items.count)
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
        let count = store.items.count
        brain.setDragging(store.isDragging || store.isDropTargeted, now: now)
        if count != itemCount {
            brain.itemsChanged(count: count, added: count > itemCount, now: now)
            itemCount = count
        }
        reschedule()
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
        let now = Self.now()
        let wasVisible = brain.isVisible, bats = brain.tileBats
        brain.tick(now: now)
        if brain.tileBats != bats { wiggleTile() }
        if brain.isVisible && !wasVisible { appeared(now) }
        publish(now)
    }

    /// First appearance this show: the preview note or the question, with the cat at the left end so it fits.
    private func appeared(_ now: TimeInterval) {
        switch mode {
        case .preview where previewUntil == 0:
            previewUntil = now + 5
        case .ask where !askShown:
            askShown = true
            asking = true
            brain.reduceMotion = true // Sits still beside the question.
        default:
            return
        }
        brain.place(at: 0)
    }

    private func publish(_ now: TimeInterval) {
        guard let pose = brain.pose else {
            if snapshot != nil { snapshot = nil }
            updateMouse()
            return
        }
        var bubble: String?
        if pose == .purr { bubble = "purrr…" }
        if now < previewUntil { bubble = "Meet \(name) 🐱 — your shelf pet (preview)" }
        let new = PetSnapshot(pose: pose, step: brain.step(at: now), progress: brain.progress(at: now), x: brain.x,
                              facingRight: pose == .sleep || brain.facingRight, ball: hub.ballOut ? brain.ball : nil,
                              bubble: asking ? nil : bubble)
        if new != snapshot { snapshot = new }
        updateMouse()
    }

    /// Bat a tile: the tile under the cat (first row) wiggles. Purely visual; items never change.
    private func wiggleTile() {
        let cols = ShelfView.columnCount(width: width)
        let col = min(cols - 1, max(0, Int((Self.inset + brain.x) / width * CGFloat(cols))))
        guard col < store.items.count else { return }
        hub.wiggles[store.items[col].id, default: 0] += 1
    }

    /// Window-local rects (SwiftUI, top-left origin) that take clicks.
    private var hitRects: [CGRect] {
        guard let s = snapshot else { return [] }
        let cx = Self.inset + s.x
        var rects = [CGRect(x: cx - 24, y: 8, width: 48, height: PetArt.ground - 2)]
        if let b = s.ball { rects.append(CGRect(x: Self.inset + b - 11, y: PetArt.ground - 18, width: 22, height: 20)) }
        if asking { rects.append(askRect) }
        return rects
    }

    /// Clicks pass through everywhere except over the pet, the ball, and the question (never over the shelf's
    /// grid, header buttons, scroll bar, or drop target).
    private func updateMouse() {
        guard attached, !ballDragging else { return }
        let p = NSEvent.mouseLocation, f = window.frame
        let inside = hitRects.contains {
            NSRect(x: f.minX + $0.minX, y: f.maxY - $0.maxY, width: $0.width, height: $0.height).contains(p)
        }
        if window.ignoresMouseEvents == inside { window.ignoresMouseEvents = !inside }
    }
}

private final class PetWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// First click on the pet works while DragShelf is inactive.
private final class PetHostingView: NSHostingView<PetStage> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
