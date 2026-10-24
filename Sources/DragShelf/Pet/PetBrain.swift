import Foundation

// Shelf pet behavior (V3-01): a pure, deterministic state machine. Time and randomness are injected so tests can
// drive it; `PetController` feeds it real time and shelf events and draws what it says.
//
// Continuity: needs (energy, curiosity, play) drift over time and with events; when the current routine ends the
// cat picks the next one from its needs, scaled by personality. Routines are short step lists (walk to a spot,
// sit, look around…); the cat always walks between spots, never jumps.
// Coordinates: `x` is the cat's centre along the play floor, 0…`track`; the ball may roll a little further.

nonisolated enum PetPose: String, CaseIterable, Sendable {
    // Front-facing.
    case sit, look, perk, sad, sniff, purr, yawn, bat, sleep
    // Side view, drawn facing right (mirrored for left).
    case walk, run, carry, crouch, pounce, stretch, backRoll
    // Behind the floor's front lip.
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
        case away, hide, popUp, sit, look, perk, sad, sniff, leanIn, yawn, stretch, circle, curl, sleep,
             walk, run, carry, crouch, pounce, bat, backRoll, batTile, dropBall
    }

    enum Target: Equatable, Sendable {
        case none
        case x(Double)
        /// Next to the ball (follows it while it rolls).
        case ball
        /// Past a floor end, out of sight (`right` side or left).
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

    enum Routine: Equatable, Sendable { case nap, wake, explore, inspect, idle, stretch, shyPeek, wander, play, fetch, react }

    /// 0…1 each.
    struct Needs: Equatable, Sendable {
        var energy = 0.8, curiosity = 0.5, play = 0.4
    }

    static let sleepAfter: TimeInterval = 30
    static let appearDelay: ClosedRange<TimeInterval> = 2...5
    static let popDelay: ClosedRange<TimeInterval> = 0.5...1.0
    static let walkSpeed = 38.0, runSpeed = 120.0, carrySpeed = 45.0
    /// Rolling friction (pt/s²), bounce damping at the floor ends, and the speed that rolls the ball off an end.
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
    /// Favorite nap nook (a floor corner), remembered by the controller.
    var favorite = 0.0
    /// Pointer x on the floor, if known: a batted ball goes back toward it.
    var cursorX: Double?
    /// First-row tile centres on the floor's axis (for inspecting).
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
    private(set) var lastActive: TimeInterval = 0
    private(set) var happiness = 0.0
    private(set) var ball: Double?
    private(set) var ballSpeed = 0.0
    private(set) var ballSpin = 0.0
    private(set) var ballHeld = false
    /// Rolled off an end (`ballGoneAt`), hidden until the cat brings it back.
    private(set) var ballGone = false
    private(set) var ballGoneAt: TimeInterval = 0
    /// The cat holds the ball (carry, back roll).
    private(set) var catHasBall = false
    private(set) var rounds = 0
    private(set) var tileBats = 0
    private(set) var shelfVisible = false
    private(set) var hasItems = false
    private(set) var dragging = false
    private var from = 0.0, pounceTo = 0.0
    private var circled = false
    private var lastTick: TimeInterval?

    init(traits: PetTraits, seed: UInt64) {
        self.traits = traits
        rng = SplitMix64(seed: seed)
    }

    var activity: Activity { current.activity }
    var isVisible: Bool { activity != .away && !isOffstage }
    var isAsleep: Bool { activity == .sleep || activity == .curl }
    /// Out past a floor end (fetching the ball).
    var isOffstage: Bool { x < -40 || x > track + 40 }
    /// Takes clicks (not hidden behind the lip or offstage).
    var isInteractive: Bool { isVisible && activity != .hide && activity != .popUp }
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
        var p = progress(at: now)
        let side = now - lastFlip < Self.turnTime && !reduceMotion ? 0.0 : 1.0
        let pose: PetPose
        var turn = 0.0
        switch activity {
        case .away: return nil
        case .hide:
            pose = .hide
            p = reduceMotion ? 1 : min(1, (now - started) / 0.3)
        case .popUp: pose = .peek
        case .sit, .dropBall: pose = .sit
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
        case .bat, .batTile: pose = .bat
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
        plan = []
        pending = []
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
        ballHeld = false
        catHasBall = false
        rounds = 0
    }

    /// Items changed. `addedAt` / `removedAt`: floor x of a tile that arrived or left (ears perk, look, inspect;
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
        if !isVisible || activity == .hide || activity == .popUp {
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

    /// Any drag (in, out, over the shelf): the cat ducks behind the floor's lip, ear tips showing, and pops up
    /// 0.5–1 s after the drag ends.
    mutating func setDragging(_ on: Bool, now: TimeInterval) {
        guard on != dragging else { return }
        dragging = on
        if on {
            if activity != .away {
                if routine != .react { pending = [] }
                if catHasBall && !ballGone { dropBallHere() }
                set(Step(.hide), now)
            }
            appearAt = nil
        } else if shelfVisible && hasItems {
            lastActive = now
            appearAt = now + Double.random(in: Self.popDelay, using: &rng)
        }
    }

    /// Click (or VoiceOver "Pet"): leans in and purrs; asleep → wakes with a stretch first.
    mutating func pet(now: TimeInterval) {
        guard isInteractive else { return }
        happiness = min(1, happiness + 0.25)
        lastActive = now
        run(.react, (isAsleep ? [Step(.stretch, 1.8)] : []) + [Step(.leanIn, 2.4)], now)
    }

    /// Header button: the ball appears on the far side of the floor, still.
    mutating func placeBall(now: TimeInterval) {
        ball = x < track / 2 ? track * 0.85 : track * 0.15
        ballSpeed = 0
        ballGone = false
        catHasBall = false
        needs.play = min(1, needs.play + 0.25)
        noticeBall(now)
    }

    mutating func removeBall(now: TimeInterval) {
        ball = nil
        ballSpeed = 0
        ballGone = false
        ballHeld = false
        catHasBall = false
        if routine == .play || routine == .fetch { run(nil, [Step(.sit, 1.5)], now) }
    }

    /// The user grabbed the ball and is moving it.
    mutating func holdBall(at bx: Double, now: TimeInterval) {
        let b = min(max(bx, ballRange.lowerBound), ballRange.upperBound)
        if let old = ball { ballSpin += (b - old) / Self.ballRadius }
        ball = b
        ballHeld = true
        ballSpeed = 0
        ballGone = false
        lastActive = now
        if isInteractive && !isAsleep && !reduceMotion && routine != .play && activity != .perk {
            run(.react, [Step(.perk, 0.8, look: b)], now)
        }
    }

    /// Let go with the drag's release velocity (pt/s): the ball rolls with friction and the cat plays.
    mutating func releaseBall(at bx: Double, velocity: Double, now: TimeInterval) {
        holdBall(at: bx, now: now)
        ballHeld = false
        ballSpeed = min(max(velocity, -Self.maxFlick), Self.maxFlick)
        needs.play = min(1, needs.play + 0.35)
        noticeBall(now)
    }

    // MARK: Time

    mutating func tick(now: TimeInterval) {
        let raw = lastTick.map { max(0, now - $0) } ?? 0
        lastTick = now
        let dt = min(0.25, raw)
        updateNeeds(raw)
        rollBall(dt, now)
        guard shelfVisible, hasItems else {
            if activity != .away { set(Step(.away), now) }
            return
        }
        if dragging {
            if activity != .away && activity != .hide { set(Step(.hide), now) }
            return
        }
        // Waiting to appear or to pop up after a drag.
        if activity == .away || (activity == .hide && current.duration == 0) {
            guard let t = appearAt, now >= t else { return }
            appearAt = nil
            lastActive = now
            let reaction = pending
            pending = []
            run(reaction.isEmpty ? nil : .react, [Step(.popUp, 0.7)] + reaction, now)
            return
        }
        if ballGone && routine != .fetch && !isAsleep && !reduceMotion && needs.play > 0.15 && current.target == .none {
            return run(.fetch, fetchPlan(), now)
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
            // A nap ends when rested, but only if someone is around; idle dozing waits for an event.
            if needs.energy >= 0.98 && now - lastActive < Self.sleepAfter { return run(.wake, wakePlan(), now) }
        default:
            break
        }
        if current.duration > 0 && now >= started + current.duration { return advance(now) }
        if !isAsleep && routine != .nap && now - lastActive >= Self.sleepAfter {
            run(.nap, napPlan(at: favorite), now)
        }
    }

    /// Seconds until the next `tick` matters; nil = nothing changes until an event (no CPU at all).
    func nextWake(now: TimeInterval) -> TimeInterval? {
        guard shelfVisible else { return nil }
        let frameRate = 1.0 / 30
        if ball != nil && ballSpeed != 0 && !ballHeld { return frameRate }
        if ballGone && now - ballGoneAt < 0.4 { return frameRate }
        let end = current.duration > 0 ? started + current.duration - now : .infinity
        let doze = isAsleep || routine == .nap ? .infinity : lastActive + Self.sleepAfter - now
        let wait: TimeInterval?
        switch activity {
        case .away: wait = appearAt.map { $0 - now }
        case .hide:
            if current.duration > 0 { wait = min(end, reduceMotion ? end : frameRate) }
            else { wait = now - started < 0.35 && !reduceMotion ? frameRate : appearAt.map { $0 - now } }
        case .walk, .run, .carry, .circle, .pounce, .popUp, .crouch, .backRoll: wait = reduceMotion ? min(end, doze) : frameRate
        case .sleep: wait = reduceMotion ? nil : 1.4
        case .sit, .dropBall: wait = min(end, doze)
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

    /// Odds of each free-time routine from the current needs, scaled by personality.
    func routineWeights() -> [(Routine, Double)] {
        let t = mood(), n = needs
        return [(.explore, 0.2 + 1.5 * n.curiosity * (0.4 + t.curiosity)),
                (.inspect, tiles.isEmpty ? 0 : 0.1 + 1.0 * n.curiosity * (0.4 + t.curiosity) + 0.6 * t.mischief),
                (.idle, 0.4 + 1.2 * (1 - n.energy) + 0.8 * t.sleepiness),
                (.stretch, 0.1 + 0.3 * t.sleepiness),
                (.shyPeek, 0.03 + 1.0 * t.shyness * t.shyness),
                (.wander, 0.1 + 1.2 * t.energy * n.energy)]
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
            let tile = tiles.randomElement(using: &rng) ?? x
            let bat = Double.random(in: 0..<1, using: &rng) < t.mischief * 0.8
            return [Step(.walk, to: .x(tile + (tile >= x ? -16 : 16))), Step(.sniff, 1.4, look: tile)]
                + (bat ? [Step(.batTile, 0.9)] : []) + [Step(.sit, Double.random(in: 2...4, using: &rng))]
        case .idle: return [Step(.sit, Double.random(in: 3...7, using: &rng) * (1 + t.sleepiness))]
        case .stretch: return [Step(.stretch, 1.8), Step(.sit, 2)]
        case .shyPeek: return [Step(.hide, Double.random(in: 2...4, using: &rng)), Step(.popUp, 0.7)]
        case .wander:
            let spot = min(max(x + Double.random(in: -90...90, using: &rng), 0), track)
            return [Step(.walk, to: .x(spot)), Step(.sit, 2)]
        case .play: return playPlan()
        case .fetch: return fetchPlan()
        case .react: return [Step(.sit, 2)]
        }
    }

    /// Play loop: notice → run over → crouch (butt wiggle) → pounce → bat, or roll on its back holding the ball →
    /// bat it back toward the pointer.
    private mutating func playPlan() -> [Step] {
        let roll = Double.random(in: 0..<1, using: &rng) < 0.25 + 0.4 * traits.mischief
        return [Step(.perk, 0.5, look: ball), Step(.run, to: .ball), Step(.crouch, 1.0, look: ball), Step(.pounce, 0.45)]
            + (roll ? [Step(.backRoll, 1.6)] : []) + [Step(.bat, 0.5), Step(.sit, 1.2)]
    }

    /// The ball rolled off an end: run there, out of sight, back carrying it, put it down.
    private func fetchPlan() -> [Step] {
        let right = (ball ?? x) > track / 2
        return [Step(.run, to: .x(right ? track : 0)), Step(.run, to: .offstage(right: right)), Step(.sit, 0.8),
                Step(.carry, to: .x(right ? track - 50 : 50)), Step(.dropBall, 0.4), Step(.sit, 1.5)]
    }

    private func napPlan(at spot: Double) -> [Step] {
        [Step(.yawn, 1.6), Step(.walk, to: .x(spot)), Step(.circle, 1.2), Step(.curl, 0.8), Step(.sleep)]
    }

    private func wakePlan() -> [Step] { [Step(.stretch, 1.8), Step(.sit, 2)] }

    private mutating func nextPlan(_ now: TimeInterval) -> (Routine?, [Step]) {
        if reduceMotion { return (nil, [Step(.sit, 4)]) }
        if ballGone && needs.play > 0.15 { return (.fetch, fetchPlan()) }
        if ball != nil && !ballHeld && !ballGone {
            if needs.play > 0.35 { return (.play, playPlan()) }
            if rounds > 0 {
                // Interest used up: wander off, or nap next to the ball. The ball stays where it is.
                rounds = 0
                if needs.energy < 0.5, let b = ball { return (.nap, napPlan(at: min(max(b + (b > track / 2 ? -20 : 20), 0), track))) }
                return (.explore, plan(for: .explore))
            }
        }
        if needs.energy < 0.25 { return (.nap, napPlan(at: favorite)) }
        let r = chooseRoutine()
        return (r, plan(for: r))
    }

    // MARK: Internals

    private mutating func run(_ r: Routine?, _ steps: [Step], _ now: TimeInterval) {
        routine = r
        plan = steps
        advance(now)
    }

    private mutating func advance(_ now: TimeInterval) {
        if plan.isEmpty {
            let (r, steps) = nextPlan(now)
            routine = r
            plan = steps
        }
        begin(plan.removeFirst(), now)
    }

    private mutating func set(_ s: Step, _ now: TimeInterval) {
        current = s
        started = now
    }

    private mutating func begin(_ step: Step, _ now: TimeInterval) {
        var s = step
        if reduceMotion {
            // Static pet: no locomotion or animated beats; it sits (or sleeps) where it is.
            switch s.activity {
            case .sit, .sleep, .leanIn, .perk, .sad, .hide, .dropBall: break
            case .curl: s = Step(.sleep)
            case .popUp: s = Step(.sit, 0.1)
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
        case .batTile: tileBats += 1
        case .dropBall:
            if catHasBall { dropBallHere() }
        case .carry: catHasBall = ball != nil
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
        rounds += 1
        needs.play = max(0, needs.play - 0.22 * (1.3 - 0.6 * traits.energy))
    }

    private mutating func dropBallHere() {
        catHasBall = false
        ballGone = false
        ballSpeed = 0
        ball = min(max(x + (facingRight ? 14 : -14), ballRange.lowerBound), ballRange.upperBound)
    }

    /// A new ball situation the cat may react to: play now if awake and interested.
    private mutating func noticeBall(_ now: TimeInterval) {
        lastActive = now
        guard isInteractive, !reduceMotion, needs.play > 0.2 else { return }
        if isAsleep { return run(.play, [Step(.stretch, 1.8)] + playPlan(), now) }
        if routine != .play || [.sit, .perk, .look].contains(activity) { run(.play, playPlan(), now) }
    }

    /// Moves toward the step's target; true once there.
    private mutating func moveStep(_ dt: Double, _ now: TimeInterval) -> Bool {
        let speed = activity == .run ? Self.runSpeed : activity == .carry ? Self.carrySpeed : Self.walkSpeed
        switch current.target {
        case .none: return true
        case .x(let goal): return move(toward: min(max(goal, 0), track), speed: speed, dt: dt, now: now)
        case .offstage(let right): return move(toward: right ? track + 80 : -80, speed: speed, dt: dt, now: now)
        case .ball:
            guard let b = ball, !ballGone else { return true }
            let goal = min(max(b + (b >= x ? -Self.reach : Self.reach), 0), track)
            let there = move(toward: goal, speed: speed, dt: dt, now: now)
            if there { face(b, now) }
            return there && abs(ballSpeed) < 30 && !ballHeld
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
        guard var b = ball, !ballHeld, !ballGone, !catHasBall, ballSpeed != 0, dt > 0 else { return }
        let v0 = ballSpeed
        var v = v0 - (v0 > 0 ? 1 : -1) * Self.friction * dt
        if v * v0 <= 0 { v = 0 }
        let nb = b + (v0 + v) / 2 * dt
        ballSpin += (nb - b) / Self.ballRadius
        b = nb
        if !ballRange.contains(b) {
            if abs(v) > Self.rollOffSpeed {
                // Rolls off the end, out of sight; the cat fetches it.
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

    /// A spot at least 60 pt away when the floor allows.
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
