import Foundation

// Shelf pet behavior (V3-01): a pure, deterministic state machine. Time and randomness are injected so tests can
// drive it; `PetController` feeds it real time and shelf events and draws what it says.
//
// Continuity: needs (energy, curiosity, play) drift over time and with events; when the current routine ends the
// cat picks the next one from its needs, scaled by personality. Routines are short step lists (walk to a spot,
// sit, look around…); the cat always walks between spots, never jumps.
// The pointer is a stimulus, not a command: on meaningful changes (enter, stop, near, linger, stroke, every few
// seconds) the cat picks a response from personality × state × an attention budget that wears off with repeated
// stimulation. A double-click on the cat or empty shelf space always calls it over.
// Coordinates: `x` is the cat's centre along the shelf's bottom rim, 0…`track`; the ball may roll a little further.
// Past either end (beyond ±72) the cat is out of view: it enters and leaves that way (appear, drag, own ball).

nonisolated enum PetPose: String, CaseIterable, Sendable {
    // Front-facing.
    case sit, look, perk, sad, sniff, purr, yawn, bat, sleep
    // Side view, drawn facing right (mirrored for left).
    case walk, run, carry, crouch, pounce, stretch, backRoll
    // Cursor play: jump up at it, bat up at it, cheek and body rubs; sleeping loaf with one eye open.
    case pounceUp, batUp, headRub, bodyRub, peekEye
    // Teaching a tip: point up, pat the rim, wave, head tilt with a "?", tap a paw.
    case pointUp, pat, wave, shrug, pawTap
    // Unused since the floor band went away (kept so the art and its review sheets stay complete).
    case peek, hide
}

/// What the art draws: pose, animation frame, 0…1 through the pose, head turn (-1…1, + = toward the cat's front).
nonisolated struct PetFrame: Equatable, Sendable {
    var pose: PetPose
    var step = 0
    var progress = 0.0
    var turn = 0.0
}

/// Personality weights, each 0…1.
nonisolated struct PetTraits: Equatable, Sendable {
    var energy, curiosity, sleepiness, mischief, shyness: Double
}

nonisolated enum PetPersonality: String, CaseIterable, Sendable {
    case playful, lazy, curious, shy, mischievous, surprise

    static let concrete: [PetPersonality] = [.playful, .lazy, .curious, .shy, .mischievous]

    var title: String { self == .surprise ? "Surprise me" : rawValue.capitalized }

    /// "Surprise me" picks one of the five each time the shelf shows.
    func resolved(using rng: inout some RandomNumberGenerator) -> PetPersonality {
        self == .surprise ? Self.concrete.randomElement(using: &rng)! : self
    }

    var traits: PetTraits {
        switch self {
        case .playful: PetTraits(energy: 0.9, curiosity: 0.6, sleepiness: 0.15, mischief: 0.5, shyness: 0.1)
        case .lazy: PetTraits(energy: 0.15, curiosity: 0.3, sleepiness: 0.95, mischief: 0.15, shyness: 0.2)
        case .curious: PetTraits(energy: 0.55, curiosity: 0.95, sleepiness: 0.3, mischief: 0.3, shyness: 0.15)
        case .shy: PetTraits(energy: 0.35, curiosity: 0.5, sleepiness: 0.4, mischief: 0.1, shyness: 0.95)
        case .mischievous, .surprise: PetTraits(energy: 0.7, curiosity: 0.6, sleepiness: 0.2, mischief: 0.95, shyness: 0.1)
        }
    }
}

/// Small seedable RNG (SplitMix64): same seed, same pet.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

nonisolated struct PetBrain: Sendable {
    enum Activity: Equatable, Sendable {
        case away, sit, look, perk, sad, sniff, leanIn, yawn, stretch, circle, curl, sleep,
             walk, run, carry, crouch, pounce, bat, backRoll, batTile, knockTile, dropBall, pushOut, pushPrep,
             watch, peekEye, pounceUp, batUp, headRub, bodyRub,
             /// Tip gestures, and a happy hop when a tip is learned.
             pointUp, pat, wave, shrug, pawTap, hop,
             /// Expands when it starts: runs over to the cursor (or the call spot) if it is far.
             approach
    }

    /// What the cat does about the pointer.
    enum CursorResponse: Equatable, Sendable {
        case ignore, watch, follow, pounce, sneak, bat, backOff, headRub, bodyRub, petting

        var isActive: Bool { [.follow, .pounce, .sneak, .bat].contains(self) }
        var isAffection: Bool { [.headRub, .bodyRub, .petting].contains(self) }
    }

    /// A meaningful pointer change; the cat only reconsiders on these.
    enum Stimulus: Equatable, Sendable {
        /// Entered the shelf, stopped moving, or still around after a while.
        case enter, still, periodic
        /// Moving within `nearDistance`.
        case near
        /// Still at the cat's head for `dwellAfter`.
        case dwell
        /// Moving slowly along its back.
        case alongBack
        /// Back and forth over the cat.
        case stroke
    }

    enum Target: Equatable, Sendable {
        case none
        case x(Double)
        /// Next to the ball (follows it while it rolls).
        case ball
        /// Past an end of the rim, out of sight (`right` side or left).
        case offstage(right: Bool)
    }

    /// One routine step. `duration` 0 = until the target is reached (moves) or until something happens.
    struct Step: Equatable, Sendable {
        var activity: Activity
        var duration: TimeInterval = 0
        var target: Target = .none
        /// Turn toward this x first (reactions).
        var lookAt: Double?
        /// The tip gesture: the speech bubble shows from when this step begins.
        var tip = false

        init(_ activity: Activity, _ duration: TimeInterval = 0, to target: Target = .none, look: Double? = nil) {
            self.activity = activity
            self.duration = duration
            self.target = target
            lookAt = look
        }
    }

    enum Routine: Equatable, Sendable { case nap, wake, explore, inspect, idle, stretch, wander, bringBall, cursor, call, exit, react, tip }

    /// How the cat acts out a tip (V3-01): pat the rim, tap a paw, nudge a tile, point up (at a button), point at a
    /// tile from beside it, wave, tilt its head, look around.
    enum TipGesture: Equatable, Sendable { case patRim, pawTap, nudgeTile, pointUp, pointAtTile, wave, shrug, lookAround }

    /// 0…1 each.
    struct Needs: Equatable, Sendable {
        var energy = 0.8, curiosity = 0.5, play = 0.4
    }

    static let sleepAfter: TimeInterval = 30
    static let appearDelay: ClosedRange<TimeInterval> = 2...5
    /// Back in this long after a drag ends.
    static let returnDelay: ClosedRange<TimeInterval> = 0.9...1.1
    /// Routine naps last this long (idle dozing lasts until something happens).
    static let napLength: ClosedRange<TimeInterval> = 60...180
    /// Cursor: pause between active responses, re-think interval, "stopped" and "lingering" times, distances.
    static let cursorCooldown: TimeInterval = 3, pounceCooldown: TimeInterval = 6, reconsiderEvery: TimeInterval = 4
    static let stillAfter: TimeInterval = 0.35, dwellAfter: TimeInterval = 0.8
    static let nearDistance = 40.0, pounceReach = 120.0
    /// A double-click keeps the cat interested this long.
    static let callInterest: TimeInterval = 20
    /// Where the cat is out of view (the sprite is 64 wide).
    static let offstageX = 72.0
    static let walkSpeed = 38.0, runSpeed = 120.0, carrySpeed = 45.0
    /// Rolling friction (pt/s²), bounce damping at the ends, and the speed that rolls the ball off an end.
    static let friction = 150.0, bounce = 0.5, rollOffSpeed = 240.0, maxFlick = 900.0, ballRadius = 7.0
    /// How far the ball may roll past the cat's track at each end; past that it hits the end.
    static let ballOverhang = 22.0
    /// Where the cat stops beside the ball.
    static let reach = 22.0
    /// Head-turn in-between after a direction change.
    static let turnTime: TimeInterval = 0.18
    /// A tip bubble shows this long; it shows anyway if the gesture has not started after `tipWait`.
    static let tipLength: TimeInterval = 6, tipWait: TimeInterval = 5

    var traits: PetTraits
    var reduceMotion = false
    /// Local hour, for the time-of-day mood.
    var hour = 12
    var track = 280.0 { didSet { x = min(max(x, -80), track + 80); favorite = min(max(favorite, 0), track) } }
    /// Favorite nap nook (a rim corner), remembered by the controller.
    var favorite = 0.0
    /// Centres (rim axis) of the bottom row of tiles actually on screen; the cat only plays with these.
    var tiles: [Double] = []
    var rng: SplitMix64

    private(set) var needs = Needs()
    private(set) var routine: Routine?
    private(set) var current = Step(.away)
    private(set) var plan: [Step] = []
    /// Reactions that happened while hidden; they play after popping up.
    private(set) var pending: [Step] = []
    private(set) var x = 0.0
    private(set) var facingRight = true
    private(set) var lastFlip: TimeInterval = -1
    private(set) var started: TimeInterval = 0
    private(set) var appearAt: TimeInterval?
    /// Side the cat enters from (and left by, during a drag).
    private(set) var entryRight = false
    /// Pointer: x on the rim track, y = height above the rim (nil = not over the shelf).
    private(set) var cursor: SIMD2<Double>?
    /// 0…1; each stimulus uses some up (more ignores), it comes back with time.
    private(set) var attention = 1.0
    private(set) var lastResponse: CursorResponse?
    private(set) var lastStimulus: Stimulus?
    /// Counts decisions (tests watch it to see each one).
    private(set) var decisions = 0
    private(set) var cooldownUntil: TimeInterval = 0
    private(set) var interestUntil: TimeInterval = -1
    /// Where a pounce goes (the cursor, or a double-click spot).
    private(set) var aim: SIMD2<Double>?
    private(set) var twitchAt: TimeInterval = -10
    private(set) var jumpHeight = 0.0
    private(set) var lastActive: TimeInterval = 0
    private(set) var happiness = 0.0
    private(set) var ball: Double?
    private(set) var ballSpeed = 0.0
    private(set) var ballSpin = 0.0
    /// Rolled off an end (`ballGoneAt`); the ball is gone for good a moment later.
    private(set) var ballGone = false
    private(set) var ballGoneAt: TimeInterval = 0
    /// The cat holds the ball (carry, back roll).
    private(set) var catHasBall = false
    /// Tile play: each bat / knock wiggles the bottom-row tile nearest the cat (purely visual).
    private(set) var tileBats = 0
    private(set) var tileKnocks = 0
    private(set) var shelfVisible = false
    private(set) var hasItems = false
    private(set) var dragging = false
    /// When the current tip's bubble appeared (nil = no tip under way or not yet shown).
    private(set) var tipAt: TimeInterval?
    private var tipDeadline: TimeInterval?
    private var from = 0.0, pounceTo = 0.0
    private var circled = false
    private var lastTick: TimeInterval?
    private var lastCursor: TimeInterval = -1
    private var napEnd: TimeInterval = .infinity
    private var lazyNap = false
    private var pendingRoutine = Routine.react
    private var cursorMovedAt: TimeInterval = 0, lastEval: TimeInterval = 0
    private var stillPending = false, wasNear = false
    private var cursorSpeed = 0.0, strokeDir = 0.0
    private var strokeTurns: [TimeInterval] = []
    private var backSince: TimeInterval?

    init(traits: PetTraits, seed: UInt64) {
        self.traits = traits
        rng = SplitMix64(seed: seed)
    }

    var activity: Activity { current.activity }
    var isVisible: Bool { activity != .away && !isOffstage }
    var isAsleep: Bool { activity == .sleep || activity == .curl }
    /// Out past an end of the rim, out of view.
    var isOffstage: Bool { x < -Self.offstageX || x > track + Self.offstageX }
    var isInteractive: Bool { isVisible }
    var ballVisible: Bool { ball != nil && !catHasBall && !ballGone }
    var ballRange: ClosedRange<Double> { -Self.ballOverhang...(track + Self.ballOverhang) }

    // MARK: Frame

    func progress(at now: TimeInterval) -> Double {
        current.duration > 0 ? min(1, max(0, (now - started) / current.duration)) : 0
    }

    /// Animation frame counter; always 0 with Reduce Motion (static pet).
    func step(at now: TimeInterval) -> Int {
        guard !reduceMotion else { return 0 }
        let rate: Double = switch activity {
        case .walk, .circle: 8
        case .run: 14
        case .carry: 9
        case .crouch: 10
        case .leanIn, .headRub, .bodyRub: 3
        case .sleep, .curl, .peekEye: 0.7
        default: 0
        }
        return Int(max(0, now - started) * rate)
    }

    func frame(at now: TimeInterval) -> PetFrame? {
        guard activity != .away else { return nil }
        let p = progress(at: now)
        let side = now - lastFlip < Self.turnTime && !reduceMotion ? 0.0 : 1.0
        let pose: PetPose
        var turn = 0.0
        switch activity {
        case .away: return nil
        case .sit, .dropBall, .pushPrep: pose = .sit
        case .look:
            pose = .look
            turn = reduceMotion ? 0 : sin(p * 2 * .pi) * 0.8
        case .perk:
            pose = .perk
            turn = current.lookAt == nil ? 0 : 0.7
        case .sad:
            pose = .sad
            turn = current.lookAt == nil ? 0 : 0.4
        case .sniff: pose = .sniff
        case .leanIn: pose = .purr
        case .yawn: pose = .yawn
        case .stretch: pose = .stretch
        case .curl, .sleep: pose = .sleep
        case .bat, .pushOut: pose = .bat
        case .batTile, .knockTile:
            // Reaches up at the tile above it.
            pose = .batUp
        case .walk, .circle:
            pose = .walk
            turn = side
        case .run:
            pose = .run
            turn = side
        case .carry:
            pose = .carry
            turn = side
        case .crouch:
            pose = .crouch
            turn = 1
        case .pounce:
            pose = .pounce
            turn = 1
        case .backRoll: pose = .backRoll
        case .watch:
            // Head follows the pointer: turned toward it, straight on when it is right above.
            pose = .perk
            if let c = cursor ?? aim { turn = min(0.9, abs(c.x - x) / 50) }
        case .peekEye: pose = .peekEye
        case .pounceUp: pose = .pounceUp
        case .batUp: pose = .batUp
        case .headRub: pose = .headRub
        case .bodyRub:
            pose = .bodyRub
            turn = 1
        case .approach, .hop: pose = .sit
        case .pointUp:
            pose = .pointUp
            turn = 0.3
        case .pat: pose = .pat
        case .wave: pose = .wave
        case .shrug: pose = .shrug
        case .pawTap: pose = .pawTap
        }
        // Asleep: an ear flicks at the pointer (ignored, but noticed).
        if pose == .sleep && now - twitchAt < 0.5 && !reduceMotion { turn = 1 }
        return PetFrame(pose: pose, step: step(at: now), progress: p, turn: turn)
    }

    /// How high the cat is off the rim (pt) mid-jump.
    func lift(at now: TimeInterval) -> Double {
        switch activity {
        case .pounceUp: sin(progress(at: now) * .pi) * jumpHeight
        case .hop: sin(progress(at: now) * .pi) * 8
        default: 0
        }
    }

    /// The tip bubble is up.
    func tipShowing(at now: TimeInterval) -> Bool {
        tipAt.map { now >= $0 && now < $0 + Self.tipLength } ?? false
    }

    // MARK: Events

    mutating func shelfShown(hasItems: Bool, now: TimeInterval) {
        shelfVisible = true
        self.hasItems = hasItems
        lastActive = now
        lastTick = now
        set(Step(.away), now)
        x = min(max(favorite, 0), track)
        entryRight = favorite > track / 2
        plan = []
        pending = []
        cursor = nil
        attention = 1
        appearAt = hasItems && !dragging ? now + Double.random(in: Self.appearDelay, using: &rng) : nil
    }

    mutating func shelfHidden(now: TimeInterval) {
        shelfVisible = false
        set(Step(.away), now)
        appearAt = nil
        plan = []
        pending = []
        routine = nil
        ball = nil
        ballSpeed = 0
        ballGone = false
        catHasBall = false
        cursor = nil
        endTip()
    }

    /// Items changed. `addedAt`: rim x of the on-screen bottom-row tile to play with (the new one, or the nearest
    /// one on screen): ears perk, it walks under it, sniffs, often bats it, then sits admiring it.
    /// `removedAt`: where one left (head follows with a small sad beat).
    mutating func itemsChanged(count: Int, addedAt: Double?, removedAt: Double?, now: TimeInterval) {
        hasItems = count > 0
        guard hasItems else {
            set(Step(.away), now)
            appearAt = nil
            return
        }
        lastActive = now
        if activity == .away && appearAt == nil && shelfVisible && !dragging {
            appearAt = now + Double.random(in: Self.appearDelay, using: &rng)
        }
        var reaction: [Step] = []
        if let a = addedAt {
            reaction = [Step(.perk, 0.6, look: a), Step(.walk, to: .x(a)), Step(.sniff, 1.2, look: a)] + tilePlay(a)
        } else if let r = removedAt {
            reaction = [Step(.perk, 0.8, look: r), Step(.sad, 1.2, look: r)]
        }
        guard !reaction.isEmpty else { return }
        if routine == .tip && activity != .away && !dragging {
            plan += reaction // After the tip.
        } else if !isVisible || dragging {
            // Plays once the cat is back in view.
            pending = reaction
            pendingRoutine = .react
        } else if isAsleep {
            if addedAt != nil { run(.react, [Step(.stretch, 1.8)] + reaction, now) }
        } else {
            run(.react, reaction, now)
        }
    }

    /// Any drag (in, out, over the shelf): the cat runs out of the shelf to the nearer side (out of view) and walks
    /// back in about a second after the drag ends.
    mutating func setDragging(_ on: Bool, now: TimeInterval) {
        guard on != dragging else { return }
        dragging = on
        if on {
            if routine != .react || pendingRoutine == .tip { pending = [] }
            endTip()
            appearAt = nil
            guard activity != .away else { return }
            if catHasBall || ball != nil { ball = nil; catHasBall = false; ballSpeed = 0; ballGone = false }
            let right = x >= track / 2
            if isOffstage { return set(Step(.away), now) }
            entryRight = right
            run(.exit, (isAsleep ? [Step(.stretch, 0.6)] : []) + exitPlan(right: right), now)
        } else if shelfVisible && hasItems {
            lastActive = now
            appearAt = now + Double.random(in: Self.returnDelay, using: &rng)
        }
    }

    private func exitPlan(right: Bool) -> [Step] {
        [Step(.run, to: .x(right ? track : 0)), Step(.run, to: .offstage(right: right))]
    }

    /// Click (or VoiceOver "Pet"): leans in and purrs; asleep → wakes with a stretch first.
    mutating func pet(now: TimeInterval) {
        guard isInteractive, !dragging else { return }
        happiness = min(1, happiness + 0.25)
        lastActive = now
        run(.react, (isAsleep ? [Step(.stretch, 1.8)] : []) + [Step(.leanIn, 2.4)], now)
    }

    // MARK: Tips

    /// Delivers a tip (V3-01): wakes first (stretch) unless it is a very sleepy cat, which tells it with one eye
    /// open instead; walks to `target` (the button or tile it is about, if any) and acts out `g` while the bubble
    /// shows. Not during a drag. Reduce Motion: no walk or gesture, just the bubble.
    mutating func deliverTip(_ g: TipGesture, target: Double?, now: TimeInterval) {
        guard shelfVisible, hasItems, !dragging else { return }
        lastActive = now
        tipAt = nil
        tipDeadline = now + Self.tipWait
        if catHasBall {
            if isOffstage { ball = nil; catHasBall = false } else { dropBallHere() }
        }
        func tip(_ a: Activity, _ d: TimeInterval, look: Double? = nil) -> Step {
            var s = Step(a, d, look: look)
            s.tip = true
            return s
        }
        if isAsleep && traits.sleepiness >= 0.9 && activity != .away {
            return run(.tip, [tip(.peekEye, Self.tipLength), Step(.sleep)], now)
        }
        let here = track > 100 ? min(max(x, 50), track - 50) : x
        let t = target.map { min(max($0, 0), track) }
        var spot = here
        let gesture: [Step]
        switch g {
        case .patRim: gesture = [tip(.pat, 1.6), Step(.sit, 4.4)]
        case .pawTap: gesture = [tip(.pawTap, 1.4), Step(.sit, 4.6)]
        case .wave: gesture = [tip(.wave, 1.8), Step(.sit, 4.2)]
        case .shrug: gesture = [tip(.shrug, 1.6), Step(.sit, 4.4)]
        case .lookAround: gesture = [tip(.look, 2.4), Step(.sit, 3.6)]
        case .nudgeTile:
            spot = t ?? here
            gesture = [tip(.batTile, 0.5, look: t), Step(.sit, 5.5, look: t)]
        case .pointUp:
            spot = t ?? here
            gesture = [tip(.pointUp, 2.6, look: t), Step(.sit, 3.4)]
        case .pointAtTile:
            // Beside the tile, on the side it comes from.
            if let t { spot = min(max(t + (t >= x ? -26 : 26), 0), track) }
            gesture = [tip(.pointUp, 2.6, look: t), Step(.sit, 3.4, look: t)]
        }
        let walk = abs(spot - x) > 2 || activity == .away ? [Step(.walk, to: .x(spot))] : []
        let steps = walk + gesture
        if activity == .away {
            // Not in yet: comes in right away to tell it (before any reaction that was waiting).
            pending = steps + (pendingRoutine == .react ? pending : [])
            pendingRoutine = .tip
            appearAt = now
            return
        }
        run(.tip, (isAsleep ? [Step(.stretch, 1.2)] : []) + steps, now)
    }

    /// Clicked the bubble: the tip is learned; a happy bounce and a purr.
    mutating func tipLearned(now: TimeInterval) {
        endTip()
        guard isVisible, !dragging else { return }
        happiness = min(1, happiness + 0.15)
        lastActive = now
        run(.react, (isAsleep ? [Step(.stretch, 0.6)] : []) + [Step(.hop, 0.35), Step(.hop, 0.35), Step(.leanIn, 1.6)], now)
    }

    private mutating func endTip() {
        tipAt = nil
        tipDeadline = nil
    }

    // MARK: Cursor

    /// The pointer moved over the shelf: `c.x` on the rim track, `c.y` above the rim (nil = it left). Only meaningful
    /// changes make the cat reconsider (`Stimulus`); the rest is bookkeeping. Ignored with Reduce Motion, during a
    /// drag, while out of view, and while busy (a reaction, its own ball, a call, a cursor action under way).
    mutating func cursorMoved(_ c: SIMD2<Double>?, now: TimeInterval) {
        let old = cursor
        cursor = c
        guard let c else {
            strokeTurns = []
            backSince = nil
            wasNear = false
            // Leaves: watches where it went out a moment, then back to its routines.
            if let o = old, routine == .cursor, isVisible, !dragging {
                lastActive = now
                run(nil, (isAsleep ? [] : [Step(.perk, 1.2, look: o.x)]), now)
            }
            return
        }
        if let o = old {
            let d = c - o
            cursorSpeed = (d * d).sum().squareRoot() / max(1.0 / 60, now - cursorMovedAt)
            if abs(d.x) > 2 {
                let dir: Double = d.x > 0 ? 1 : -1
                if strokeDir != 0 && dir != strokeDir && overBody(c) { strokeTurns.append(now) }
                strokeDir = dir
            }
        }
        cursorMovedAt = now
        stillPending = true
        strokeTurns.removeAll { now - $0 > 1.5 }
        let near = isNear(c), cameNear = near && !wasNear
        wasNear = near
        let slowOnBack = alongBack(c)
        if !slowOnBack { backSince = nil }
        guard canNotice else { return }
        if old == nil { return respond(to: .enter, now) }
        if strokeTurns.count >= 2 {
            strokeTurns = []
            return respond(to: .stroke, now)
        }
        if cameNear { return respond(to: .near, now) }
        if slowOnBack {
            guard let since = backSince else { return backSince = now }
            if now - since >= 0.5 {
                backSince = nil
                respond(to: .alongBack, now)
            }
        }
    }

    /// Double-click on the cat or empty shelf space (`p` like `cursorMoved`): always gets attention. Looks, perks up,
    /// goes there, crouches and jumps at the spot, then stays interested in the pointer for a while.
    mutating func call(at p: SIMD2<Double>, now: TimeInterval) {
        guard shelfVisible, hasItems, !dragging else { return }
        attention = 1
        interestUntil = now + Self.callInterest
        cooldownUntil = 0
        aim = p
        lastActive = now
        if catHasBall {
            if isOffstage { ball = nil; catHasBall = false } else { dropBallHere() }
        }
        let steps = [Step(.perk, 0.7, look: p.x), Step(.approach), Step(.crouch, 0.8, look: p.x),
                     Step(p.y > 24 ? .pounceUp : .pounce, 0.55), Step(.sit, 1), Step(.watch, 3, look: p.x)]
        if activity == .away {
            // Not in yet: comes in right away and answers.
            pending = steps
            pendingRoutine = .call
            appearAt = now
            return
        }
        run(.call, (isAsleep ? [Step(.stretch, 0.6)] : []) + steps, now)
    }

    /// Settings → Pet → Play with ball: the own-ball routine right now.
    mutating func playBall(now: TimeInterval) {
        guard shelfVisible, hasItems, !dragging, !reduceMotion, routine != .bringBall else { return }
        lastActive = now
        if activity == .away {
            pending = ballPlan(enter: true)
            pendingRoutine = .bringBall
            appearAt = now
            return
        }
        run(.bringBall, (isAsleep ? [Step(.stretch, 0.6)] : []) + ballPlan(enter: isOffstage), now)
    }

    /// The cat can take notice: in view, idle enough, and not mid-action on an earlier response.
    private var canNotice: Bool {
        guard isVisible, !dragging, !reduceMotion, ![.exit, .react, .bringBall, .call, .tip].contains(routine) else { return false }
        return routine != .cursor || [.watch, .sit, .perk, .peekEye, .sleep].contains(activity)
    }

    private func isNear(_ c: SIMD2<Double>) -> Bool { hypot(c.x - x, c.y - 20) < Self.nearDistance }
    private func overBody(_ c: SIMD2<Double>) -> Bool { abs(c.x - x) < 30 && (0...46).contains(c.y) }
    private func nearHead(_ c: SIMD2<Double>) -> Bool { abs(c.x - x) < 22 && (20...58).contains(c.y) }
    private func alongBack(_ c: SIMD2<Double>) -> Bool {
        abs(c.x - x) < 28 && (8...42).contains(c.y) && (6...90).contains(cursorSpeed)
    }

    /// Stopped, lingering at the head, or every few seconds while the pointer stays around.
    private mutating func cursorTick(_ now: TimeInterval) {
        guard let c = cursor, canNotice else { return }
        let still = now - cursorMovedAt, head = nearHead(c)
        if stillPending {
            if head {
                if still >= Self.dwellAfter {
                    stillPending = false
                    return respond(to: .dwell, now)
                }
                return
            }
            if still >= Self.stillAfter {
                stillPending = false
                return respond(to: .still, now)
            }
        }
        // Lingering at its head: rubs again now and then.
        if head && still >= Self.dwellAfter && now - lastEval >= 1.8 { return respond(to: .dwell, now) }
        if now - lastEval >= Self.reconsiderEvery { respond(to: .periodic, now) }
    }

    /// Odds of each response to `s` right now: personality (via mood), state (asleep, tired), attention, cooldown,
    /// and a recent call. Lazy mostly ignores, Curious mostly watches, Playful pounces and bats, Shy keeps its
    /// distance, Mischievous pretends not to care and then pounces.
    func responseWeights(_ s: Stimulus, now: TimeInterval) -> [(CursorResponse, Double)] {
        guard let c = cursor else { return [(.ignore, 1)] }
        let t = mood(), a = attention, tired = 1 - needs.energy
        let boost = now < interestUntil ? 2.0 : 1.0
        let act = now >= cooldownUntil ? a * boost * (isAsleep ? 0.35 : 1) : 0
        let canJump = c.y <= Self.pounceReach
        let ignore = (0.4 + 3 * t.sleepiness + 1.2 * tired + (isAsleep ? 2 + 3 * t.sleepiness : 0)) * (1 + 2 * (1 - a)) / boost
        let watch = (0.8 + 2.5 * t.curiosity + 1.5 * t.shyness) * (0.4 + 0.6 * a)
        let affection = (0.5 + 2.5 * (1 - t.shyness) + 2 * happiness) * (isAsleep ? 0.6 : 1)
        switch s {
        case .enter, .still, .periodic:
            return [(.ignore, ignore), (.watch, watch),
                    (.follow, (0.3 + 1.4 * t.curiosity * (1 - t.shyness) + 0.6 * t.energy) * act),
                    (.pounce, canJump ? (0.1 + 3.2 * t.energy * t.energy * (0.5 + 0.5 * t.mischief)) * act : 0),
                    (.sneak, canJump ? 3 * t.mischief * t.mischief * act : 0)]
        case .near:
            return [(.ignore, ignore), (.watch, watch),
                    (.bat, (0.2 + 3 * t.energy * (0.3 + t.mischief)) * act),
                    (.backOff, isAsleep ? 0 : 6 * max(0, t.shyness - 0.4))]
        case .dwell:
            return [(.ignore, ignore * 0.5), (.watch, 0.5), (.headRub, affection)]
        case .alongBack:
            return [(.ignore, ignore * 0.5), (.watch, 0.5), (.bodyRub, affection)]
        case .stroke:
            return [(.ignore, ignore * 0.3), (.petting, affection * 1.5), (.bat, t.mischief * act)]
        }
    }

    private mutating func respond(to s: Stimulus, _ now: TimeInterval) {
        lastEval = now
        let options = responseWeights(s, now: now)
        var r = Double.random(in: 0..<max(1e-9, options.reduce(0) { $0 + $1.1 }), using: &rng)
        var pick = CursorResponse.ignore
        for (response, w) in options {
            if r < w { pick = response; break }
            r -= w
        }
        attention = max(0, attention - (pick.isAffection ? 0.03 : 0.12))
        lastResponse = pick
        lastStimulus = s
        decisions += 1
        guard let c = cursor else { return }
        if pick == .ignore {
            if isAsleep { twitchAt = now }
            return
        }
        lastActive = now
        if pick.isActive { cooldownUntil = now + ([.pounce, .sneak].contains(pick) ? Self.pounceCooldown : Self.cursorCooldown) }
        if pick.isAffection { happiness = min(1, happiness + 0.08) }
        let t = mood()
        let wake = isAsleep ? [Step(.stretch, 0.6)] : []
        let toward: Double = c.x >= x ? 1 : -1
        let steps: [Step]
        switch pick {
        case .ignore: return
        case .watch:
            // A sleepy cat just opens one eye.
            steps = isAsleep && t.sleepiness >= 0.6 ? [Step(.peekEye, 3), Step(.sleep)] : wake + [Step(.watch, 3, look: c.x)]
        case .follow:
            // Walks or trots over and stops short (a shy cat keeps its distance); a curious one sniffs.
            let gap = t.shyness > 0.6 ? 70.0 : 20.0
            let spot = min(max(c.x - toward * gap, 0), track)
            let gait: Activity = t.energy * needs.energy > 0.45 ? .run : .walk
            steps = wake + [Step(.perk, 0.4, look: c.x), Step(gait, to: .x(spot))]
                + (t.curiosity > 0.7 ? [Step(.sniff, 1.2, look: c.x)] : []) + [Step(.watch, 2.5, look: c.x)]
        case .pounce:
            steps = wake + [Step(.approach), Step(.crouch, 0.9, look: c.x), Step(c.y > 24 ? .pounceUp : .pounce, 0.55),
                            Step(.sit, 0.8), Step(.watch, 2, look: c.x)]
        case .sneak:
            // Looks away as if it does not care… then turns and pounces.
            steps = wake + [Step(.sit, Double.random(in: 1.5...3, using: &rng), look: x - toward * 50), Step(.approach),
                            Step(.crouch, 0.7, look: c.x), Step(.pounceUp, 0.55), Step(.sit, 0.8)]
        case .bat:
            steps = wake + [Step(.batUp, 0.5, look: c.x), Step(.batUp, 0.5), Step(.watch, 1.5, look: c.x)]
        case .backOff:
            steps = [Step(.walk, to: .x(min(max(x - toward * 60, 0), track))), Step(.watch, 2.5, look: c.x)]
        case .headRub: steps = wake + [Step(.headRub, 1.8, look: c.x)]
        case .bodyRub:
            if !isAsleep { face(x + strokeDir * 10, now) }
            steps = wake + [Step(.bodyRub, 2)]
        case .petting: steps = wake + [Step(.leanIn, 2.4)]
        }
        run(.cursor, steps, now)
    }

    // MARK: Time

    mutating func tick(now: TimeInterval) {
        let raw = lastTick.map { max(0, now - $0) } ?? 0
        lastTick = now
        let dt = min(0.25, raw)
        updateNeeds(raw)
        attention = min(1, attention + raw * (cursor == nil ? 0.04 : 0.01))
        rollBall(dt, now)
        if ballGone && now - ballGoneAt >= 0.4 { // Pushed off the edge: gone for good.
            ball = nil
            ballGone = false
        }
        guard shelfVisible, hasItems else {
            if activity != .away { set(Step(.away), now) }
            return
        }
        if tipAt == nil, let d = tipDeadline, now >= d, isVisible {
            tipAt = now
            tipDeadline = nil
        }
        // Waiting to appear (first time, or back after a drag): walks in from a side.
        if activity == .away {
            guard !dragging, let t = appearAt, now >= t else { return }
            appearAt = nil
            lastActive = now
            let reaction = pending
            pending = []
            let spot = entryRight ? track - 30 : 30
            if !reduceMotion { x = entryRight ? track + Self.offstageX + 8 : -Self.offstageX - 8 }
            // Its own ball comes in with it (carried); anything else walks in first.
            if pendingRoutine == .bringBall && !reaction.isEmpty { return run(.bringBall, reaction, now) }
            run(reaction.isEmpty ? nil : pendingRoutine, [Step(.walk, to: .x(reduceMotion ? x : spot))] + reaction, now)
            return
        }
        cursorTick(now)
        switch activity {
        case .walk, .run, .carry:
            if moveStep(dt, now) { return advance(now) }
        case .circle:
            if !circled && progress(at: now) >= 0.5 {
                circled = true
                flip(now)
            }
        case .pounce, .pounceUp:
            x = from + (pounceTo - from) * progress(at: now)
        case .watch:
            if let c = cursor { face(c.x, now) }
        case .sleep:
            if now >= napEnd { return run(.wake, wakePlan(), now) }
        default:
            break
        }
        if current.duration > 0 && now >= started + current.duration { return advance(now) }
        if !dragging && !isAsleep && routine != .nap && now - lastActive >= Self.sleepAfter {
            run(.nap, napPlan(at: favorite), now)
            lazyNap = true
        }
    }

    /// Seconds until the next `tick` matters; nil = nothing changes until an event (no CPU at all).
    func nextWake(now: TimeInterval) -> TimeInterval? {
        guard shelfVisible else { return nil }
        let frameRate = 1.0 / 30
        if ball != nil && ballSpeed != 0 { return frameRate }
        if ballGone && now - ballGoneAt < 0.45 { return frameRate }
        let end = current.duration > 0 ? started + current.duration - now : .infinity
        let doze = isAsleep || routine == .nap || dragging ? .infinity : lastActive + Self.sleepAfter - now
        let wait: TimeInterval?
        switch activity {
        case .away: wait = dragging ? nil : appearAt.map { $0 - now }
        case .walk, .run, .carry, .circle, .pounce, .pounceUp, .crouch, .backRoll: wait = reduceMotion ? min(end, doze) : frameRate
        case .sleep:
            wait = reduceMotion ? nil : now - twitchAt < 0.5 ? 1.0 / 20 : min(1.4, max(0.02, napEnd - now))
        case .sit, .dropBall, .pushPrep, .approach, .watch: wait = min(end, doze)
        case .look: wait = reduceMotion ? end : 1.0 / 20
        case .leanIn: wait = reduceMotion ? end : min(1.0 / 6, end)
        default: wait = reduceMotion ? end : min(1.0 / 20, end)
        }
        // Pointer over the shelf: a slow tick notices when it stops or lingers (≤ 10 Hz; moves tick on their own).
        var attentive = cursor != nil && canNotice ? min(wait ?? .infinity, 0.1) : wait
        // The tip bubble's deadline and fade.
        if let edge = [tipDeadline, tipAt.map { $0 + Self.tipLength }].compactMap({ $0 }).filter({ $0 > now }).min() {
            attentive = min(attentive ?? .infinity, edge - now)
        }
        guard let attentive, attentive.isFinite else { return nil }
        return max(0.02, attentive)
    }

    // MARK: Choice

    /// Needs adjusted by time of day and petting.
    func mood() -> PetTraits {
        var t = traits
        if hour >= 22 || hour < 6 {
            t.sleepiness = min(1, t.sleepiness * 1.5 + 0.2)
            t.energy *= 0.6
        }
        t.shyness *= 1 - 0.6 * happiness
        return t
    }

    /// Odds of each free-time routine from the current needs, scaled by personality. Naps dominate: the cat is
    /// mostly asleep when it is on screen.
    func routineWeights() -> [(Routine, Double)] {
        let t = mood(), n = needs
        return [(.nap, 5 + 6 * t.sleepiness),
                (.explore, 0.2 + 1.5 * n.curiosity * (0.4 + t.curiosity)),
                // Playing with the tiles on screen: Curious most of all, then Mischievous and Playful.
                (.inspect, tiles.isEmpty ? 0 : 0.3 + 1.0 * n.curiosity * (0.4 + t.curiosity) + 0.8 * t.mischief
                    + 2.4 * t.curiosity * t.curiosity),
                (.idle, 0.4 + 1.2 * (1 - n.energy) + 0.8 * t.sleepiness),
                (.stretch, 0.1 + 0.3 * t.sleepiness),
                (.wander, 0.1 + 1.2 * t.energy * n.energy),
                // Its own ball: a regular game for an awake cat, most of all a playful or curious one.
                (.bringBall, 0.3 + 2.5 * t.energy * n.play + 1.0 * t.curiosity * n.play)]
    }

    mutating func chooseRoutine() -> Routine {
        let options = routineWeights()
        var r = Double.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &rng)
        for (routine, w) in options {
            if r < w { return routine }
            r -= w
        }
        return .idle
    }

    /// Steps of a free-time routine.
    mutating func plan(for r: Routine) -> [Step] {
        let t = mood()
        switch r {
        case .nap: return napPlan(at: favorite)
        case .wake: return wakePlan()
        case .explore:
            return [Step(.walk, to: .x(farSpot())), Step(.sit, Double.random(in: 1.5...3, using: &rng)), Step(.look, 2.4)]
        case .inspect:
            // Walks under an on-screen bottom-row tile, sniffs, then plays with it.
            let tile = tiles.randomElement(using: &rng) ?? x
            return [Step(.walk, to: .x(tile)), Step(.sniff, 1.2, look: tile)] + tilePlay(tile)
        case .idle: return [Step(.sit, Double.random(in: 3...7, using: &rng) * (1 + t.sleepiness))]
        case .stretch: return [Step(.stretch, 1.8), Step(.sit, 2)]
        case .wander:
            let spot = min(max(x + Double.random(in: -90...90, using: &rng), 0), track)
            return [Step(.walk, to: .x(spot)), Step(.sit, 2)]
        case .bringBall: return ballPlan()
        case .cursor, .call, .exit, .react, .tip: return [Step(.sit, 2)]
        }
    }

    /// The cat's own ball: out of view past a side, back carrying it, put it down, a round or two of play (run
    /// over, crouch with a butt wiggle, pounce, bat; or roll on its back holding it), then walk around it and
    /// push it off the nearer edge. The ball is gone for good.
    /// `enter`: already out of view; it just comes back in with the ball.
    private mutating func ballPlan(enter: Bool = false) -> [Step] {
        let right = enter ? (isOffstage ? x > track / 2 : entryRight) : Bool.random(using: &rng)
        let rounds = Int.random(in: 1...2, using: &rng)
        let spot = right ? track - 50 : 50
        return (enter ? [] : exitPlan(right: right) + [Step(.sit, 0.8)]) + [Step(.carry, to: .x(spot)), Step(.dropBall, 0.4)]
            + (0..<rounds).flatMap { _ in playRound() } + [Step(.pushPrep), Step(.sit, 1.5)]
    }

    /// Under a tile: often reaches up and bats it (it wiggles), sometimes twice, then sits admiring it. A
    /// mischievous cat may knock it instead (a bigger shove toward the edge) and look around as if nothing happened.
    /// Purely visual: the item never changes.
    private mutating func tilePlay(_ tile: Double) -> [Step] {
        let t = mood()
        let batOdds = min(0.9, max(0.05, 0.2 + 0.5 * t.curiosity + 0.4 * t.energy + 0.4 * t.mischief - 0.5 * t.shyness))
        guard Double.random(in: 0..<1, using: &rng) < batOdds else { return [Step(.sit, 2.5, look: tile)] }
        if t.mischief > 0.7 && Double.random(in: 0..<1, using: &rng) < 0.45 {
            return [Step(.knockTile, 0.6, look: tile), Step(.look, 2.4)]
        }
        let twice = Double.random(in: 0..<1, using: &rng) < 0.25 + 0.5 * max(t.energy, t.mischief)
        return [Step(.batTile, 0.5, look: tile)] + (twice ? [Step(.batTile, 0.5)] : []) + [Step(.sit, 2.5, look: tile)]
    }

    private mutating func playRound() -> [Step] {
        let roll = Double.random(in: 0..<1, using: &rng) < 0.25 + 0.4 * traits.mischief
        return [Step(.perk, 0.5, look: ball), Step(.run, to: .ball), Step(.crouch, 1.0, look: ball), Step(.pounce, 0.45)]
            + (roll ? [Step(.backRoll, 1.6)] : []) + [Step(.bat, 0.5), Step(.sit, 1.6)]
    }

    private func napPlan(at spot: Double) -> [Step] {
        [Step(.yawn, 1.6), Step(.walk, to: .x(spot)), Step(.circle, 1.2), Step(.curl, 0.8), Step(.sleep)]
    }

    private func wakePlan() -> [Step] { [Step(.stretch, 1.8), Step(.sit, 2)] }

    private mutating func nextPlan(_ now: TimeInterval) -> (Routine?, [Step]) {
        if dragging { return (.exit, [Step(.away)]) }
        if reduceMotion { return (nil, [Step(.sit, 4)]) }
        if needs.energy < 0.25 { return (.nap, napPlan(at: favorite)) }
        let r = chooseRoutine()
        return (r, plan(for: r))
    }

    // MARK: Internals

    private mutating func run(_ r: Routine?, _ steps: [Step], _ now: TimeInterval) {
        routine = r
        plan = steps
        lazyNap = false
        advance(now)
    }

    private mutating func advance(_ now: TimeInterval) {
        if plan.isEmpty {
            let (r, steps) = nextPlan(now)
            routine = r
            plan = steps
            lazyNap = false
        }
        begin(plan.removeFirst(), now)
    }

    private mutating func set(_ s: Step, _ now: TimeInterval) {
        current = s
        started = now
    }

    private mutating func begin(_ step: Step, _ now: TimeInterval) {
        var s = step
        if s.activity == .approach {
            // Over to the pointer (or the call spot) first if it is out of paw's reach.
            if let goal = routine == .call ? aim : cursor ?? aim, abs(goal.x - x) > 40 {
                let spot = min(max(goal.x + (goal.x >= x ? -24 : 24), 0), track)
                plan.insert(Step(.run, to: .x(spot)), at: 0)
            }
            guard !plan.isEmpty else { return begin(Step(.sit, 0.5), now) }
            return begin(plan.removeFirst(), now)
        }
        if s.activity == .pushPrep {
            // Walk around to the side of the ball away from the nearer edge, then push it that way.
            let b = ball ?? x
            let right = b > track / 2
            let side = min(max(b + (right ? -Self.reach : Self.reach), 0), track)
            plan = [Step(.run, to: .x(side)), Step(.sit, 0.3), Step(.pushOut, 0.6)] + plan
            return begin(plan.removeFirst(), now)
        }
        if reduceMotion {
            // Static pet: no locomotion or animated beats; it sits (or sleeps) where it is.
            switch s.activity {
            case .sit, .sleep, .leanIn, .perk, .sad, .dropBall, .away: break
            case .watch: s.activity = .perk
            case .curl: s = Step(.sleep)
            default: s = Step(.sit, max(s.duration, 1.5))
            }
        }
        set(s, now)
        if step.tip {
            tipAt = now
            tipDeadline = nil
        }
        if let l = s.lookAt { face(l, now) }
        // Cursor play aims at where the pointer is now; a call keeps its spot.
        if routine == .cursor, let c = cursor, [.crouch, .pounce, .pounceUp, .batUp, .headRub, .watch].contains(s.activity) {
            aim = c
            face(c.x, now)
        }
        switch s.activity {
        case .circle: circled = false
        case .pounce:
            from = x
            let b = [.cursor, .call].contains(routine) ? aim?.x ?? x : ball ?? x + (facingRight ? 30 : -30)
            face(b, now)
            pounceTo = min(max(b - (facingRight ? 10 : -10), 0), track)
        case .pounceUp:
            // Up at the pointer: a short hop sideways, as high as the canvas allows.
            let goal = aim ?? SIMD2(x + (facingRight ? 20 : -20), 40)
            from = x
            face(goal.x, now)
            pounceTo = min(max(x + min(max(goal.x - x, -30), 30) * 0.8, 0), track)
            jumpHeight = min(max(goal.y * 0.75, 16), 46)
        case .backRoll:
            catHasBall = ball != nil
            needs.energy = max(0, needs.energy - 0.03)
        case .bat: kick()
        case .pushOut: pushBall()
        case .batTile: tileBats += 1
        case .knockTile: tileKnocks += 1
        case .dropBall:
            if catHasBall { dropBallHere() }
        case .carry:
            // The cat's own ball arrives with it.
            if routine == .bringBall && ball == nil { ball = x }
            catHasBall = ball != nil
        case .sleep: napEnd = lazyNap ? .infinity : now + Double.random(in: Self.napLength, using: &rng)
        default: break
        }
    }

    /// Bat: the ball goes back toward the pointer (or away if unknown), rolling to a stop near it.
    private mutating func kick() {
        guard let b = ball, abs(b - x) < 40 || catHasBall else { return }
        catHasBall = false
        let start = min(max(x + (facingRight ? 12 : -12), ballRange.lowerBound), ballRange.upperBound)
        let goal = min(max(cursor?.x ?? (x + (facingRight ? 100 : -100)), 0), track)
        let d = goal - start
        ball = start
        ballSpeed = (d >= 0 ? 1 : -1) * min(Self.rollOffSpeed * 0.9, (2 * Self.friction * abs(d)).squareRoot())
        if abs(d) > 1 { ballSpin += 0.3 }
        needs.play = max(0, needs.play - 0.22 * (1.3 - 0.6 * traits.energy))
    }

    /// Push: a firm shove toward the nearer end; it rolls off the edge.
    private mutating func pushBall() {
        guard let b = ball else { return }
        face(b, lastTick ?? 0)
        let dir = b >= x ? 1.0 : -1.0
        catHasBall = false
        ball = min(max(x + dir * 12, ballRange.lowerBound), ballRange.upperBound)
        ballSpeed = dir * 400
        ballSpin += dir * 0.4
    }

    private mutating func dropBallHere() {
        catHasBall = false
        ballGone = false
        ballSpeed = 0
        ball = min(max(x + (facingRight ? 14 : -14), ballRange.lowerBound), ballRange.upperBound)
    }

    /// Moves toward the step's target; true once there.
    private mutating func moveStep(_ dt: Double, _ now: TimeInterval) -> Bool {
        let speed = activity == .run ? Self.runSpeed : activity == .carry ? Self.carrySpeed : Self.walkSpeed
        switch current.target {
        case .none: return true
        case .x(let goal): return move(toward: min(max(goal, 0), track), speed: speed, dt: dt, now: now)
        case .offstage(let right): return move(toward: right ? track + Self.offstageX + 8 : -Self.offstageX - 8, speed: speed, dt: dt, now: now)
        case .ball:
            guard let b = ball, !ballGone else { return true }
            let goal = min(max(b + (b >= x ? -Self.reach : Self.reach), 0), track)
            let there = move(toward: goal, speed: speed, dt: dt, now: now)
            if there { face(b, now) }
            return there && abs(ballSpeed) < 30
        }
    }

    private mutating func move(toward goal: Double, speed: Double, dt: Double, now: TimeInterval) -> Bool {
        let d = goal - x
        if abs(d) > 0.5 { face(goal, now) }
        let len = speed * dt
        if abs(d) <= len {
            x = goal
            return true
        }
        x += d > 0 ? len : -len
        return false
    }

    private mutating func face(_ target: Double, _ now: TimeInterval) {
        guard abs(target - x) > 1 else { return }
        if (target > x) != facingRight { flip(now) }
    }

    private mutating func flip(_ now: TimeInterval) {
        facingRight.toggle()
        lastFlip = now
    }

    private mutating func rollBall(_ dt: Double, _ now: TimeInterval) {
        guard var b = ball, !ballGone, !catHasBall, ballSpeed != 0, dt > 0 else { return }
        let v0 = ballSpeed
        var v = v0 - (v0 > 0 ? 1 : -1) * Self.friction * dt
        if v * v0 <= 0 { v = 0 }
        let nb = b + (v0 + v) / 2 * dt
        ballSpin += (nb - b) / Self.ballRadius
        b = nb
        if !ballRange.contains(b) {
            if abs(v) > Self.rollOffSpeed {
                // Rolls off the end, out of sight.
                ballGone = true
                ballGoneAt = now
                v = 0
            } else {
                b = min(max(b, ballRange.lowerBound), ballRange.upperBound)
                v = -v * Self.bounce
            }
        }
        ball = b
        ballSpeed = v
    }

    private mutating func updateNeeds(_ dt: Double) {
        guard shelfVisible, dt > 0 else { return }
        let t = mood()
        if isAsleep {
            needs.energy += 0.06 * dt
        } else {
            let busy: Set<Activity> = [.walk, .run, .carry, .pounce, .pounceUp, .crouch, .backRoll, .bat, .batUp]
            needs.energy -= dt * 0.006 * (0.5 + 1.5 * t.sleepiness) * (busy.contains(activity) ? 2.5 : 1)
        }
        if [.look, .sniff].contains(activity) { needs.curiosity -= dt * 0.15 } else { needs.curiosity += dt * 0.012 * (0.3 + t.curiosity) }
        needs.play += dt * 0.008 * (0.2 + t.energy + 0.5 * t.mischief)
        needs.energy = min(max(needs.energy, 0), 1)
        needs.curiosity = min(max(needs.curiosity, 0), 1)
        needs.play = min(max(needs.play, 0), 1)
    }

    /// A spot at least 60 pt away when the rim allows.
    private mutating func farSpot() -> Double {
        let spot = Double.random(in: 0...max(1, track), using: &rng)
        if abs(spot - x) >= 60 || track < 120 { return min(spot, track) }
        return spot >= x ? min(track, x + 60 + spot.truncatingRemainder(dividingBy: 40)) : max(0, x - 60 - spot.truncatingRemainder(dividingBy: 40))
    }

    // MARK: Test hooks

    /// Starts a routine right away (tests, previews).
    mutating func start(_ r: Routine, now: TimeInterval) { run(r, plan(for: r), now) }
    /// Sets needs directly (tests).
    mutating func setNeeds(_ n: Needs) { needs = n }
    /// One decision about the pointer right now (tests; the pointer must be set).
    mutating func stimulate(_ s: Stimulus, now: TimeInterval) { respond(to: s, now) }
    /// Puts the cat at `x` while it is not visible (first appearance spot).
    mutating func place(at newX: Double) { x = min(max(newX, 0), track) }
}

/// Preview + ask-once opt-in (V3-01): pet on, or a preview on the 2nd and 3rd drag session, then one question.
nonisolated enum PetOptIn {
    enum Mode: Equatable, Sendable { case off, on, preview, ask }

    static func mode(feature: Bool, enabled: Bool, preview: Bool, sessions: Int, asked: Bool) -> Mode {
        guard feature else { return .off }
        if enabled { return .on }
        guard preview, !asked else { return .off }
        switch sessions {
        case 2...3: return .preview
        case 4...: return .ask
        default: return .off
        }
    }
}
