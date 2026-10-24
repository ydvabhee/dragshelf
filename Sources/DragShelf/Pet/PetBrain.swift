import Foundation

// Shelf pet behavior (V3-01): pure, deterministic state machine. Time and randomness are injected so tests can
// drive it; `PetController` feeds it real time and shelf events and draws what it says.

nonisolated enum PetPose: String, CaseIterable, Sendable {
    case sit, walk, stretch, yawn, sleep, peek, pounce, bat, purr
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
        /// `sleep` = dozed off after idling (until something happens); `nap` = chose a short nap.
        case away, peek, sit, walk, stretch, yawn, sleep, nap, pounce, bat, batTile, purr, chase
    }

    static let sleepAfter: TimeInterval = 30
    static let appearDelay: ClosedRange<TimeInterval> = 2...5
    static let walkSpeed = 40.0, chaseSpeed = 120.0
    /// How close (pt) the cat gets to the ball before it pounces.
    static let pounceRange = 40.0

    var traits: PetTraits
    var reduceMotion = false { didSet { if reduceMotion, isVisible, !isAsleep { start(.sit, at: started) } } }
    /// Local hour, for the time-of-day mood.
    var hour = 12
    /// Walkable length of the shelf's top edge (pt); `x` and `ball` live in 0…track.
    var track = 280.0 { didSet { x = clamp(x); ball = ball.map(clamp) } }
    var rng: SplitMix64

    private(set) var activity = Activity.away
    private(set) var x = 140.0
    private(set) var facingRight = true
    private(set) var started: TimeInterval = 0
    private(set) var duration: TimeInterval = .infinity
    private(set) var appearAt: TimeInterval?
    /// Last shelf activity or interaction; idle for `sleepAfter` → sleep.
    private(set) var lastActive: TimeInterval = 0
    /// 0…1, grows with petting: shorter waits, less shy, more energy.
    private(set) var happiness = 0.0
    private(set) var ball: Double?
    /// Counts tile bats; the controller wiggles a tile on each change.
    private(set) var tileBats = 0
    private(set) var shelfVisible = false
    private(set) var hasItems = false
    private(set) var dragging = false
    private var ballSpeed = 0.0
    private var ballTouched: TimeInterval = -.infinity
    private var from = 0.0, target = 0.0
    private var queued: Activity?
    private var lastTick: TimeInterval?

    init(traits: PetTraits, seed: UInt64) {
        self.traits = traits
        rng = SplitMix64(seed: seed)
    }

    var isVisible: Bool { activity != .away }
    var isAsleep: Bool { activity == .sleep || activity == .nap }

    var pose: PetPose? {
        switch activity {
        case .away: nil
        case .walk, .chase: .walk
        case .sleep, .nap: .sleep
        case .bat, .batTile: .bat
        case .peek: .peek
        case .sit: .sit
        case .stretch: .stretch
        case .yawn: .yawn
        case .pounce: .pounce
        case .purr: .purr
        }
    }

    /// 0…1 through a timed activity (0 for open-ended ones).
    func progress(at now: TimeInterval) -> Double {
        duration.isFinite && duration > 0 ? min(1, max(0, (now - started) / duration)) : 0
    }

    /// Animation frame counter; always 0 with Reduce Motion (static pet).
    func step(at now: TimeInterval) -> Int {
        guard !reduceMotion else { return 0 }
        let rate: Double = switch activity {
        case .walk: 8
        case .chase: 12
        case .purr: 3
        case .sleep, .nap: 0.7
        default: 0
        }
        return Int(max(0, now - started) * rate)
    }

    // MARK: Events

    mutating func shelfShown(hasItems: Bool, now: TimeInterval) {
        shelfVisible = true
        self.hasItems = hasItems
        lastActive = now
        lastTick = now
        set(.away, at: now)
        appearAt = nil
        if hasItems && !dragging { scheduleAppear(now) }
    }

    mutating func shelfHidden(now: TimeInterval) {
        shelfVisible = false
        set(.away, at: now)
        appearAt = nil
        ball = nil
    }

    /// Items changed; `added` = something landed (drop, paste, restore).
    mutating func itemsChanged(count: Int, added: Bool, now: TimeInterval) {
        hasItems = count > 0
        guard hasItems else {
            set(.away, at: now)
            appearAt = nil
            return
        }
        guard added else { return }
        lastActive = now
        if !isVisible {
            if appearAt == nil && shelfVisible && !dragging { scheduleAppear(now) }
        } else if isAsleep {
            wake(then: nil, now: now)
        }
    }

    /// Any drag (in, out, or over the shelf) hides the pet at once; it comes back 2–5 s after.
    mutating func setDragging(_ on: Bool, now: TimeInterval) {
        guard on != dragging else { return }
        dragging = on
        if on {
            set(.away, at: now)
            appearAt = nil
        } else if shelfVisible && hasItems {
            lastActive = now
            scheduleAppear(now)
        }
    }

    /// Click (or VoiceOver "Pet"): purr; asleep → wake with a stretch first.
    mutating func pet(now: TimeInterval) {
        guard isVisible else { return }
        happiness = min(1, happiness + 0.25)
        lastActive = now
        if isAsleep { wake(then: .purr, now: now) } else { start(.purr, at: now) }
    }

    /// The user put the ball down or is dragging it: the cat chases it (not with Reduce Motion).
    mutating func moveBall(to bx: Double, now: TimeInterval) {
        ball = clamp(bx)
        ballSpeed = 0
        ballTouched = now
        lastActive = now
        guard isVisible, !reduceMotion else { return }
        if isAsleep { wake(then: .chase, now: now) }
        else if ![.chase, .pounce, .bat, .stretch, .peek].contains(activity) { start(.chase, at: now) }
    }

    /// Puts the cat at `x` on the track (room for a speech bubble beside it).
    mutating func place(at newX: Double) { x = clamp(newX) }

    mutating func removeBall(now: TimeInterval) {
        ball = nil
        ballSpeed = 0
        if activity == .chase { start(.sit, at: now) }
    }

    // MARK: Time

    mutating func tick(now: TimeInterval) {
        let dt = lastTick.map { min(0.25, max(0, now - $0)) } ?? 0
        lastTick = now
        rollBall(dt)
        guard shelfVisible, !dragging, hasItems else {
            if isVisible { set(.away, at: now) }
            return
        }
        if activity == .away {
            if let t = appearAt, now >= t {
                appearAt = nil
                lastActive = now
                reduceMotion ? start(.sit, at: now) : start(.peek, at: now, then: .sit)
            }
            return
        }
        switch activity {
        case .walk:
            if move(toward: target, speed: Self.walkSpeed, dt: dt) { return next(now) }
        case .chase:
            guard let b = ball else { return start(.sit, at: now) }
            if abs(b - x) <= Self.pounceRange {
                facingRight = b >= x
                start(.pounce, at: now)
                target = clamp(b - (facingRight ? 12 : -12))
            } else {
                _ = move(toward: b, speed: Self.chaseSpeed, dt: dt)
            }
            return
        case .pounce:
            x = from + (target - from) * progress(at: now)
        default:
            break
        }
        if now >= started + duration { return next(now) }
        if !isAsleep && activity != .yawn && now - lastActive >= Self.sleepAfter {
            reduceMotion ? start(.sleep, at: now) : start(.yawn, at: now, then: .sleep)
        }
    }

    /// Seconds until the next `tick` matters; nil = nothing will change until an event (idle CPU 0).
    func nextWake(now: TimeInterval) -> TimeInterval? {
        guard shelfVisible, !dragging else { return nil }
        if ball != nil && ballSpeed != 0 { return 1.0 / 30 }
        let end = started + duration - now
        let doze = lastActive + Self.sleepAfter - now
        let wait: TimeInterval? = switch activity {
        case .away: appearAt.map { $0 - now }
        case .walk, .chase, .pounce: 1.0 / 30
        case .sleep: reduceMotion ? nil : 1.4
        case .nap: reduceMotion ? end : min(1.4, end)
        case .sit: min(end, doze)
        case .purr: reduceMotion ? end : min(1.0 / 6, end)
        case .peek, .stretch, .yawn, .bat, .batTile: reduceMotion ? end : min(1.0 / 20, end)
        }
        return wait.map { max(0.02, $0) }
    }

    // MARK: Choice

    /// Mood = personality adjusted by time of day, petting, and recent shelf activity.
    func mood(now: TimeInterval) -> PetTraits {
        var t = traits
        if hour >= 22 || hour < 6 {
            t.sleepiness = min(1, t.sleepiness * 1.5 + 0.2)
            t.energy *= 0.6
        } else if hour < 10 {
            t.energy = min(1, t.energy + 0.1)
        }
        t.shyness *= 1 - 0.6 * happiness
        t.energy = min(1, t.energy + 0.2 * happiness)
        if now - lastActive < 8 {
            t.curiosity = min(1, t.curiosity + 0.2)
            t.sleepiness *= 0.7
        }
        return t
    }

    /// Relative odds of each next activity.
    static func weights(_ t: PetTraits, hasItems: Bool, ball: Bool) -> [(Activity, Double)] {
        [(.sit, 1 + (1 - t.energy)),
         (.walk, 0.3 + 1.6 * t.energy + 0.6 * t.curiosity),
         (.stretch, 0.2 + 0.4 * t.sleepiness),
         (.yawn, 0.1 + 0.6 * t.sleepiness),
         (.nap, 0.05 + 0.9 * t.sleepiness * t.sleepiness),
         (.peek, 0.05 + 1.4 * t.shyness * t.shyness),
         (.pounce, 0.05 + 0.8 * t.energy * (0.4 + t.mischief)),
         (.batTile, hasItems ? 0.05 + 1.3 * t.mischief * t.mischief : 0),
         (.chase, ball ? 0.4 + 2 * t.energy : 0)]
    }

    /// Weighted pick of the next activity (exposed for tests).
    mutating func choose(now: TimeInterval) -> Activity {
        let options = Self.weights(mood(now: now), hasItems: hasItems, ball: ball != nil)
        var r = Double.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &rng)
        for (activity, w) in options {
            if r < w { return activity }
            r -= w
        }
        return .sit
    }

    // MARK: Internals

    private mutating func next(_ now: TimeInterval) {
        if let q = queued {
            queued = nil
            return start(q, at: now)
        }
        // Idle past the deadline (e.g. a nap or yawn ran over it): doze off for good.
        if now - lastActive >= Self.sleepAfter {
            return isAsleep || activity == .yawn || reduceMotion ? start(.sleep, at: now) : start(.yawn, at: now, then: .sleep)
        }
        if reduceMotion { return start(.sit, at: now) }
        // After batting the ball a playful cat often runs after it again.
        if activity == .bat, ball != nil, now - ballTouched < 12, Double.random(in: 0..<1, using: &rng) < mood(now: now).energy {
            return start(.chase, at: now)
        }
        start(choose(now: now), at: now)
    }

    private mutating func wake(then q: Activity?, now: TimeInterval) {
        reduceMotion ? start(q == .chase ? .sit : q ?? .sit, at: now) : start(.stretch, at: now, then: q)
    }

    private mutating func scheduleAppear(_ now: TimeInterval) {
        appearAt = now + Double.random(in: Self.appearDelay, using: &rng) * (1 - 0.4 * happiness)
    }

    private mutating func set(_ a: Activity, at now: TimeInterval) {
        activity = a
        started = now
        duration = .infinity
        queued = nil
    }

    mutating func start(_ a: Activity, at now: TimeInterval, then q: Activity? = nil) {
        set(a, at: now)
        queued = q
        let t = mood(now: now)
        if reduceMotion && ![.sit, .sleep, .nap, .purr].contains(a) { activity = .sit }
        switch activity {
        case .sit: duration = Double.random(in: 2...5, using: &rng) * (1 + t.sleepiness)
        case .walk:
            let span = max(0, track - 40)
            var goal = Double.random(in: 0...max(1, track), using: &rng)
            if abs(goal - x) < 40 && span > 0 { goal = x + (goal >= x ? 40 : -40) }
            target = clamp(goal)
            facingRight = target >= x
        case .stretch: duration = 1.8
        case .yawn: duration = 1.6
        case .peek: duration = 1.2 + 2.5 * t.shyness
        case .pounce:
            from = x
            target = clamp(x + (facingRight ? 30 : -30))
            duration = 0.5
        case .bat:
            duration = 0.6
            if let b = ball, abs(b - x) < Self.pounceRange { ballSpeed = (facingRight ? 1 : -1) * Double.random(in: 150...230, using: &rng) }
        case .batTile:
            duration = 0.9
            tileBats += 1
        case .purr: duration = 2.4
        case .nap: duration = Double.random(in: 8...20, using: &rng)
        case .away, .chase, .sleep: break
        }
        if activity == .pounce, queued == nil, ball != nil { queued = .bat }
    }

    /// Walks `x` toward `goal`; true once there.
    private mutating func move(toward goal: Double, speed: Double, dt: Double) -> Bool {
        let d = goal - x
        if abs(d) > 0.5 { facingRight = d > 0 }
        let len = speed * dt
        if abs(d) <= len { x = goal; return true }
        x += d > 0 ? len : -len
        return false
    }

    private mutating func rollBall(_ dt: Double) {
        guard var b = ball, ballSpeed != 0 else { return }
        b += ballSpeed * dt
        if b < 0 || b > track { ballSpeed = -ballSpeed * 0.5; b = clamp(b) }
        ballSpeed *= pow(0.25, dt)
        if abs(ballSpeed) < 8 { ballSpeed = 0 }
        ball = b
    }

    private func clamp(_ v: Double) -> Double { min(max(0, v), max(0, track)) }
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
