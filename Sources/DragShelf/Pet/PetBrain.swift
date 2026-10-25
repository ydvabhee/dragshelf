import Foundation

// Shelf pet behavior (V3-01): a pure, deterministic state machine. Time and randomness are injected so tests can
// drive it; `PetController` feeds it real time and shelf events and draws what it says.
//
// Continuity: needs (energy, curiosity, play) drift over time and with events; when the current routine ends the
// cat picks the next one from its needs, scaled by personality. Routines are short step lists (walk to a spot,
// sit, look around…); the cat always walks between spots, never jumps.
// Coordinates: `x` is the cat's centre along the shelf's bottom rim, 0…`track`; the ball may roll a little further.
// Past either end (beyond ±72) the cat is out of view: it enters and leaves that way (appear, drag, own ball).

nonisolated enum PetPose: String, CaseIterable, Sendable {
    // Front-facing.
    case sit, look, perk, sad, sniff, purr, yawn, bat, sleep
    // Side view, drawn facing right (mirrored for left).
    case walk, run, carry, crouch, pounce, stretch, backRoll
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
             walk, run, carry, crouch, pounce, bat, backRoll, batTile, dropBall, pushOut, pushPrep
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

        init(_ activity: Activity, _ duration: TimeInterval = 0, to target: Target = .none, look: Double? = nil) {
            self.activity = activity
            self.duration = duration
            self.target = target
            lookAt = look
        }
    }

    enum Routine: Equatable, Sendable { case nap, wake, explore, inspect, idle, stretch, wander, bringBall, follow, exit, react }

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
    /// Mouse follow: at most one cursor update per `followThrottle`; re-aim only past `followSlack`.
    static let followThrottle: TimeInterval = 0.1, followSlack = 20.0
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

    var traits: PetTraits
    var reduceMotion = false
    /// Local hour, for the time-of-day mood.
    var hour = 12
    var track = 280.0 { didSet { x = min(max(x, -80), track + 80); favorite = min(max(favorite, 0), track) } }
    /// Favorite nap nook (a rim corner), remembered by the controller.
    var favorite = 0.0
    /// Pointer x on the rim, if known: a batted ball goes back toward it.
    var cursorX: Double?
    /// Bottom-row tile centres on the rim's axis (for inspecting).
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
    private(set) var followX: Double?
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
    private(set) var tileBats = 0
    private(set) var shelfVisible = false
    private(set) var hasItems = false
    private(set) var dragging = false
    private var from = 0.0, pounceTo = 0.0
    private var circled = false
    private var lastTick: TimeInterval?
    private var lastCursor: TimeInterval = -1
    private var napEnd: TimeInterval = .infinity
    private var lazyNap = false

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
        case .leanIn: 3
        case .sleep, .curl: 0.7
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
        case .bat, .batTile, .pushOut: pose = .bat
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
        }
        return PetFrame(pose: pose, step: step(at: now), progress: p, turn: turn)
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
        followX = nil
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
        followX = nil
    }

    /// Items changed. `addedAt` / `removedAt`: rim x of a tile that arrived or left (ears perk, look, inspect;
    /// or head follows with a small sad beat).
    mutating func itemsChanged(count: Int, addedAt: Double?, removedAt: Double?, now: TimeInterval) {
        hasItems = count > 0
        guard hasItems else {
            set(Step(.away), now)
            appearAt = nil
            return
        }
        lastActive = now
        var reaction: [Step] = []
        if let a = addedAt {
            let spot = a + (a >= x ? -16 : 16)
            reaction = [Step(.perk, 0.6, look: a), Step(.walk, to: .x(spot)), Step(.sniff, 1.4, look: a), Step(.sit, 2)]
        } else if let r = removedAt {
            reaction = [Step(.perk, 0.8, look: r), Step(.sad, 1.2, look: r)]
        }
        guard !reaction.isEmpty else { return }
        if !isVisible || dragging {
            // Plays once the cat is back in view.
            pending = reaction
            if activity == .away && appearAt == nil && shelfVisible && !dragging {
                appearAt = now + Double.random(in: Self.appearDelay, using: &rng)
            }
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
        followX = nil
        if on {
            if routine != .react { pending = [] }
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

    /// The pointer moved over the shelf at rim x `cx` (nil = it left). The cat wakes, runs toward it, then acts
    /// cute (sit, look up, head tilt, purr). Throttled; ignored while Reduce Motion is on, during a drag, or when
    /// the cat is out of view (it is not summoned). A shy cat follows less often.
    mutating func cursorMoved(_ cx: Double?, now: TimeInterval) {
        cursorX = cx
        guard let cx else {
            if routine == .follow {
                followX = nil
                run(nil, [Step(.sit, 1.5)], now)
            }
            return
        }
        guard !reduceMotion, !dragging, isVisible, now - lastCursor >= Self.followThrottle else { return }
        lastCursor = now
        lastActive = now
        let goal = min(max(cx, 0), track)
        if routine == .follow {
            // Re-aim only while still on the way; once sitting by the pointer, stay cute.
            guard let f = followX, abs(goal - f) > Self.followSlack, activity == .run else { return }
            followX = goal
            return begin(Step(.run, to: .x(goal)), now)
        }
        guard abs(goal - x) > Self.followSlack, routine != .react,
              Double.random(in: 0..<1, using: &rng) < 1 - 0.7 * mood().shyness else { return }
        followX = goal
        run(.follow, (isAsleep ? [Step(.stretch, 0.9)] : []) + [Step(.run, to: .x(goal)), Step(.sit, 0.5),
                                                                  Step(.look, 2.0), Step(.perk, 1.0), Step(.leanIn, 3.0)], now)
    }

    // MARK: Time

    mutating func tick(now: TimeInterval) {
        let raw = lastTick.map { max(0, now - $0) } ?? 0
        lastTick = now
        let dt = min(0.25, raw)
        updateNeeds(raw)
        rollBall(dt, now)
        if ballGone && now - ballGoneAt >= 0.4 { // Pushed off the edge: gone for good.
            ball = nil
            ballGone = false
        }
        guard shelfVisible, hasItems else {
            if activity != .away { set(Step(.away), now) }
            return
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
            run(reaction.isEmpty ? nil : .react, [Step(.walk, to: .x(reduceMotion ? x : spot))] + reaction, now)
            return
        }
        switch activity {
        case .walk, .run, .carry:
            if moveStep(dt, now) { return advance(now) }
        case .circle:
            if !circled && progress(at: now) >= 0.5 {
                circled = true
                flip(now)
            }
        case .pounce:
            x = from + (pounceTo - from) * progress(at: now)
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
        case .walk, .run, .carry, .circle, .pounce, .crouch, .backRoll: wait = reduceMotion ? min(end, doze) : frameRate
        case .sleep: wait = reduceMotion ? nil : min(1.4, max(0.02, napEnd - now))
        case .sit, .dropBall, .pushPrep: wait = min(end, doze)
        case .look: wait = reduceMotion ? end : 1.0 / 20
        case .leanIn: wait = reduceMotion ? end : min(1.0 / 6, end)
        default: wait = reduceMotion ? end : min(1.0 / 20, end)
        }
        guard let wait, wait.isFinite else { return nil }
        return max(0.02, wait)
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
                (.inspect, tiles.isEmpty ? 0 : 0.1 + 1.0 * n.curiosity * (0.4 + t.curiosity) + 0.6 * t.mischief
                    + 1.5 * t.curiosity * t.curiosity),
                (.idle, 0.4 + 1.2 * (1 - n.energy) + 0.8 * t.sleepiness),
                (.stretch, 0.1 + 0.3 * t.sleepiness),
                (.wander, 0.1 + 1.2 * t.energy * n.energy),
                (.bringBall, 0.1 + 0.6 * t.energy * n.play)]
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
            // Walks to a bottom-row tile, sniffs, maybe bats it (it wiggles), sits beside it.
            let tile = tiles.randomElement(using: &rng) ?? x
            let bat = Double.random(in: 0..<1, using: &rng) < min(1, t.mischief + 0.5 * t.curiosity) * 0.8
            return [Step(.walk, to: .x(tile + (tile >= x ? -16 : 16))), Step(.sniff, 1.4, look: tile)]
                + (bat ? [Step(.batTile, 0.9)] : []) + [Step(.sit, Double.random(in: 2...4, using: &rng))]
        case .idle: return [Step(.sit, Double.random(in: 3...7, using: &rng) * (1 + t.sleepiness))]
        case .stretch: return [Step(.stretch, 1.8), Step(.sit, 2)]
        case .wander:
            let spot = min(max(x + Double.random(in: -90...90, using: &rng), 0), track)
            return [Step(.walk, to: .x(spot)), Step(.sit, 2)]
        case .bringBall: return ballPlan()
        case .follow, .exit, .react: return [Step(.sit, 2)]
        }
    }

    /// The cat's own ball: out of view past a side, back carrying it, put it down, a round or two of play (run
    /// over, crouch with a butt wiggle, pounce, bat; or roll on its back holding it), then walk around it and
    /// push it off the nearer edge. The ball is gone for good.
    private mutating func ballPlan() -> [Step] {
        let right = Bool.random(using: &rng)
        let rounds = Int.random(in: 1...2, using: &rng)
        let spot = right ? track - 50 : 50
        return exitPlan(right: right) + [Step(.sit, 0.8), Step(.carry, to: .x(spot)), Step(.dropBall, 0.4)]
            + (0..<rounds).flatMap { _ in playRound() } + [Step(.pushPrep), Step(.sit, 1.5)]
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
            case .curl: s = Step(.sleep)
            default: s = Step(.sit, max(s.duration, 1.5))
            }
        }
        set(s, now)
        if let l = s.lookAt { face(l, now) }
        switch s.activity {
        case .circle: circled = false
        case .pounce:
            from = x
            let b = ball ?? x + (facingRight ? 30 : -30)
            face(b, now)
            pounceTo = min(max(b - (facingRight ? 10 : -10), 0), track)
        case .backRoll:
            catHasBall = ball != nil
            needs.energy = max(0, needs.energy - 0.03)
        case .bat: kick()
        case .pushOut: pushBall()
        case .batTile: tileBats += 1
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
        let goal = min(max(cursorX ?? (x + (facingRight ? 100 : -100)), 0), track)
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
            let busy: Set<Activity> = [.walk, .run, .carry, .pounce, .crouch, .backRoll, .bat]
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
