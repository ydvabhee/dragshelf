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


/// What the play floor draws right now.
struct PetSnapshot: Equatable {
    var frame: PetFrame
    /// Cat centre on the floor track.
    var x: Double
    var facingRight: Bool
    /// Ball centre on the floor track (nil = no ball shown).
    var ball: Double?
    var ballSpin = 0.0
    var bubble: String?
}

/// Runs the shelf pet (V3-01): feeds `PetBrain` time and shelf events, publishes what the play floor draws.
/// The floor is a band at the bottom of the shelf panel (`PetFloor`), present only while the pet is on.
@Observable
final class PetController {
    /// Floor band height, the floor surface (top of the front lip) from the band's top, the tray's side inset,
    /// and where the cat's track starts (clear of the tray's rounded ends).
    static let floorHeight: CGFloat = 60
    static let groundY: CGFloat = 48
    static let trayInset: CGFloat = 10
    static let trackInset: CGFloat = 40
    static let favoriteKey = "petFavoriteSpot"

    /// Pet on (or previewing / asking): the shelf shows the floor band.
    private(set) var floorOn = false
    /// Drawn state; set by the controller (and by snapshot tests).
    var snapshot: PetSnapshot?
    private(set) var asking = false
    private(set) var ballOut = false
    /// Per-tile wiggle counters; a change wiggles that tile once.
    private(set) var wiggles: [UUID: Int] = [:]
    private(set) var name = Preferences.defaultPetName

    /// Floor band frame in the panel's content coordinates (top-left origin), reported by `PetFloor`.
    @ObservationIgnored var floorFrame: CGRect = .zero { didSet { if floorFrame.width != oldValue.width { layout() } } }
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
    @ObservationIgnored private var previewUntil: TimeInterval = 0
    @ObservationIgnored private var itemIDs: [UUID] = []
    @ObservationIgnored private var personality = PetPersonality.playful

    init(shelf: NSWindow, store: ShelfStore, defaults: UserDefaults = .standard) {
        self.shelf = shelf
        self.store = store
        self.defaults = defaults
        brain = PetBrain(traits: PetPersonality.playful.traits, seed: UInt64.random(in: 0...UInt64.max))
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prefsChanged() }
        }
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

    func sendHome() { Preferences.sendPetHome(defaults) }

    func answer(keep: Bool) {
        asking = false
        askShown = false
        Preferences.answerPetQuestion(keep: keep, defaults)
    }

    /// Ball drag on the floor (`floorX` from the band's leading edge).
    func holdBall(at floorX: CGFloat) {
        brain.holdBall(at: Double(floorX - Self.trackInset), now: Self.now())
        reschedule()
    }

    /// Flick: the drag's release velocity (pt/s) keeps it rolling.
    func releaseBall(at floorX: CGFloat, velocity: CGFloat) {
        brain.releaseBall(at: Double(floorX - Self.trackInset), velocity: Double(velocity), now: Self.now())
        reschedule()
    }

    /// Header yarn button.
    func toggleBall() {
        ballOut.toggle()
        ballOut ? brain.placeBall(now: Self.now()) : brain.removeBall(now: Self.now())
        reschedule()
    }

    // MARK: State

    private func refresh() {
        let want = shelfShown && mode != .off
        if want && !attached { attach() } else if !want && attached { detach() }
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
        guard newMode != mode else { return }
        mode = newMode
        if floorOn != (mode != .off) { floorOn = mode != .off }
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
        reschedule()
    }

    private func detach() {
        attached = false
        if askShown { answer(keep: false) } // Ignored counts as "No thanks".
        loop?.cancel()
        loop = nil
        brain.shelfHidden(now: Self.now())
        ballOut = false
        wiggles = [:]
        previewUntil = 0
        snapshot = nil
    }

    /// Track length and tile positions follow the floor width.
    private func layout() {
        let width = floorFrame.width > 0 ? floorFrame.width : shelf.frame.width
        guard width > 0 else { return }
        brain.track = max(0, Double(width - 2 * Self.trackInset))
        brain.tiles = (0..<min(columns, store.visibleItems.count)).map(tileX)
    }

    private var columns: Int { ShelfView.columnCount(width: floorFrame.width > 0 ? floorFrame.width : shelf.frame.width) }

    /// First-row centre of grid column `col` on the floor track (grid padding 12, spacing 8).
    private func tileX(_ col: Int) -> Double {
        let width = floorFrame.width > 0 ? floorFrame.width : shelf.frame.width
        let cols = CGFloat(columns), cell = (width - 24 - 8 * (cols - 1)) / cols
        return Double(12 + cell / 2 + CGFloat(col) * (cell + 8) - Self.trackInset)
    }

    /// Drags (in, out, over the shelf) and item changes; re-arms itself (Observation fires once per registration).
    private func observeStore() {
        withObservationTracking {
            _ = (store.isDragging, store.isDropTargeted, store.items.count, store.query)
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
            let cols = columns
            let added = ids.firstIndex { !itemIDs.contains($0) }
            let removed = itemIDs.firstIndex { !ids.contains($0) }
            let grew = ids.count > itemIDs.count
            itemIDs = ids
            layout()
            brain.itemsChanged(count: store.items.count, addedAt: grew ? added.map { tileX($0 % cols) } : nil,
                               removedAt: !grew ? removed.map { tileX($0 % cols) } : nil, now: now)
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
        guard attached else { return }
        let now = Self.now()
        let wasVisible = brain.isVisible, bats = brain.tileBats
        brain.cursorX = cursorX()
        brain.tick(now: now)
        if brain.tileBats != bats { wiggleTile() }
        if brain.isVisible && !wasVisible { appeared(now) }
        publish(now)
    }

    /// Pointer x on the floor track, so a batted ball comes back toward it.
    private func cursorX() -> Double? {
        guard floorFrame.width > 0 else { return nil }
        return Double(NSEvent.mouseLocation.x - shelf.frame.minX - floorFrame.minX - Self.trackInset)
    }

    /// First appearance this show: the preview note or the question.
    private func appeared(_ now: TimeInterval) {
        switch mode {
        case .preview where previewUntil == 0:
            previewUntil = now + 5
        case .ask where !askShown:
            askShown = true
            asking = true
            brain.reduceMotion = true // Sits still beside the question.
        default:
            break
        }
    }

    private func publish(_ now: TimeInterval) {
        guard let frame = brain.frame(at: now) else {
            if snapshot != nil { snapshot = nil }
            return
        }
        var bubble: String?
        if frame.pose == .purr { bubble = "purrr…" }
        if now < previewUntil { bubble = "Meet \(name) 🐱 — your shelf pet (preview)" }
        var ball: Double?
        if ballOut, let b = brain.ball {
            if brain.ballGone {
                // Rolling off the end, out of sight behind the tray's side.
                let t = min(1, (now - brain.ballGoneAt) / 0.35)
                if t < 1 { ball = b + (b > 0 ? 1 : -1) * 30 * t }
            } else if brain.ballVisible {
                ball = b
            }
        }
        // Sleep is drawn facing right so the "z z" reads.
        let new = PetSnapshot(frame: frame, x: brain.x, facingRight: frame.pose == .sleep || brain.facingRight,
                              ball: ball, ballSpin: brain.ballSpin, bubble: asking ? nil : bubble)
        if new != snapshot { snapshot = new }
        let fav = brain.track > 0 ? brain.favorite / brain.track : 0
        if abs(fav - defaults.double(forKey: Self.favoriteKey)) > 0.01 { defaults.set(fav, forKey: Self.favoriteKey) }
    }

    /// Bat a tile: the tile under the cat (first row) wiggles. Purely visual; items never change.
    private func wiggleTile() {
        let items = store.visibleItems
        guard !items.isEmpty else { return }
        let col = (0..<min(columns, items.count)).min { abs(tileX($0) - brain.x) < abs(tileX($1) - brain.x) } ?? 0
        wiggles[items[col].id, default: 0] += 1
    }

    /// The cat takes clicks only while it is up on the floor (not ducked behind the lip).
    var interactive: Bool { brain.isInteractive }
}
