import Foundation
import Testing
@testable import DragShelf

/// Brain on a shown shelf with items: 280 pt floor track, three first-row tiles, clock at 0, midday.
private func brain(_ p: PetPersonality = .playful, seed: UInt64 = 7, reduceMotion: Bool = false) -> PetBrain {
    var b = PetBrain(traits: p.traits, seed: seed)
    b.track = 280
    b.tiles = [40, 140, 240]
    b.reduceMotion = reduceMotion
    b.shelfShown(hasItems: true, now: 0)
    return b
}

/// Ticks every `dt` from `from` to `to`, calling `each` after every tick.
private func run(_ b: inout PetBrain, from: Double, to: Double, dt: Double = 0.05,
                 _ each: (inout PetBrain, Double) -> Void = { _, _ in }) {
    var t = from
    while t <= to {
        b.tick(now: t)
        each(&b, t)
        t += dt
    }
}

/// Distinct activities in order of appearance from `from` to `to`.
private func trace(_ b: inout PetBrain, from: Double, to: Double) -> [PetBrain.Activity] {
    var out: [PetBrain.Activity] = []
    run(&b, from: from, to: to) { b, _ in if out.last != b.activity { out.append(b.activity) } }
    return out
}

/// Visible and settled (popped up) at t = 6.
private func awake(_ p: PetPersonality = .playful, seed: UInt64 = 7) -> PetBrain {
    var b = brain(p, seed: seed)
    run(&b, from: 0, to: 6)
    return b
}

private func isSubsequence(_ needle: [PetBrain.Activity], of hay: [PetBrain.Activity]) -> Bool {
    var i = 0
    for a in hay where i < needle.count && a == needle[i] { i += 1 }
    return i == needle.count
}

// MARK: Personality and needs

private func shares(_ p: PetPersonality) -> [PetBrain.Routine: Double] {
    var b = brain(p, seed: 42)
    var counts: [PetBrain.Routine: Double] = [:]
    for _ in 0..<4000 { counts[b.chooseRoutine(), default: 0] += 1 }
    return counts.mapValues { $0 / 4000 }
}

@Test func personalitiesShapeRoutines() {
    let playful = shares(.playful), lazy = shares(.lazy), curious = shares(.curious)
    let shy = shares(.shy), mischievous = shares(.mischievous)
    func s(_ d: [PetBrain.Routine: Double], _ r: PetBrain.Routine) -> Double { d[r] ?? 0 }
    #expect(s(playful, .wander) > 2 * s(lazy, .wander))
    #expect(s(lazy, .idle) > s(playful, .idle) + 0.1)
    #expect(s(shy, .shyPeek) > 3 * s(playful, .shyPeek))
    #expect(s(mischievous, .inspect) > s(shy, .inspect))
    #expect(s(curious, .explore) > s(lazy, .explore))
}

@Test func needsDriftByPersonality() {
    var lazy = awake(.lazy), playful = awake(.playful)
    run(&lazy, from: 6, to: 26) { b, t in if Int(t * 20) % 100 == 0 { b.pet(now: t) } }
    run(&playful, from: 6, to: 26) { b, t in if Int(t * 20) % 100 == 0 { b.pet(now: t) } }
    #expect(lazy.needs.energy < playful.needs.energy)
    #expect(playful.needs.play > 0.4)
}

@Test func tiredCatNapsAtItsFavoriteSpot() {
    var b = awake(.playful)
    b.favorite = 0
    b.setNeeds(PetBrain.Needs(energy: 0.1, curiosity: 0.2, play: 0.1))
    var napped = false
    run(&b, from: 6, to: 40) { b, _ in if b.routine == .nap { napped = true } }
    #expect(napped)
    #expect(b.isAsleep)
    #expect(abs(b.x - 0) < 1)
}

// MARK: Routines and continuity

@Test func napRoutineRunsInOrder() {
    var b = awake()
    b.favorite = 0
    b.place(at: 200)
    b.setNeeds(PetBrain.Needs(energy: 0.2, curiosity: 0.2, play: 0.2)) // Tired: sleeps until rested.
    b.start(.nap, now: 6)
    let seen = trace(&b, from: 6, to: 20)
    #expect(Array(seen.prefix(5)) == [.yawn, .walk, .circle, .curl, .sleep], "\(seen)")
    #expect(abs(b.x) < 1)
    #expect(b.isAsleep, "\(seen)")
    // Petting wakes it: stretch, then lean in and purr.
    b.pet(now: 20)
    #expect(isSubsequence([.stretch, .leanIn], of: trace(&b, from: 20, to: 25)))
}

@Test func exploreAndInspectRoutines() {
    var e = awake(.curious)
    e.start(.explore, now: 6)
    #expect(isSubsequence([.walk, .sit, .look], of: trace(&e, from: 6, to: 30)))
    var i = awake(.curious)
    i.start(.inspect, now: 6)
    #expect(isSubsequence([.walk, .sniff, .sit], of: trace(&i, from: 6, to: 30)))
}

@Test func neverTeleports() {
    for seed: UInt64 in 1...6 {
        var b = brain(.playful, seed: seed)
        var last: Double?
        var maxStep = 0.0
        run(&b, from: 0, to: 150) { b, t in
            switch Int(t * 20) {
            case 400: b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: t)
            case 800: b.releaseBall(at: 100, velocity: 400, now: t)
            case 1200: b.setDragging(true, now: t)
            case 1300: b.setDragging(false, now: t)
            case 1600: b.releaseBall(at: 250, velocity: 800, now: t) // Rolls off: fetch.
            case 2200: b.pet(now: t)
            default: break
            }
            if let l = last { maxStep = max(maxStep, abs(b.x - l)) }
            last = b.x
        }
        #expect(maxStep <= PetBrain.runSpeed * 0.05 + 1, "seed \(seed): \(maxStep)")
    }
}

@Test func facesWhereItWalks() {
    var b = awake()
    b.place(at: 250)
    b.start(.explore, now: 6)
    var last = b.x
    var flipped: Double?
    run(&b, from: 6, to: 20) { b, t in
        if b.activity == .walk && abs(b.x - last) > 0.01 { #expect(b.facingRight == (b.x > last)) }
        if b.lastFlip == t { flipped = t }
        if let f = flipped, b.activity == .walk {
            // Head turns through a front-facing in-between, then looks along the walk.
            let turn = b.frame(at: t)?.turn
            #expect(turn == (t - f < PetBrain.turnTime ? 0 : 1))
        }
        last = b.x
    }
}

// MARK: Reactions

@Test func reactionsFire() {
    var b = awake()
    b.place(at: 140)
    b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: 6)
    #expect(b.activity == .perk)
    #expect(b.facingRight) // Looks toward the new tile.
    #expect(isSubsequence([.perk, .walk, .sniff], of: trace(&b, from: 6, to: 12)))
    #expect(abs(b.x - 224) < 1)

    var r = awake()
    r.place(at: 140)
    r.itemsChanged(count: 2, addedAt: nil, removedAt: 40, now: 6)
    #expect(!r.facingRight)
    #expect(isSubsequence([.perk, .sad], of: trace(&r, from: 6, to: 9)))

    var p = awake()
    p.pet(now: 6)
    #expect(p.activity == .leanIn)
    #expect(p.frame(at: 6)?.pose == .purr)
}

// MARK: Drag

@Test func ducksBehindTheLipDuringDragAndPopsUp() {
    var b = awake()
    b.setDragging(true, now: 6)
    #expect(b.activity == .hide)
    #expect(!b.isInteractive)
    b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: 7) // The drop that ends the drag.
    run(&b, from: 6, to: 30) { b, _ in #expect(b.activity == .hide && b.frame(at: 30)?.pose == .hide) }
    #expect(b.nextWake(now: 30) == nil) // Ducked and still: no ticks.
    b.setDragging(false, now: 30)
    var up: Double?
    var probe = b
    run(&probe, from: 30, to: 33) { b, t in if up == nil && b.activity == .popUp { up = t } }
    #expect(up.map { $0 >= 30.5 && $0 <= 31.05 } == true)
    // The drop's reaction plays after popping up.
    #expect(isSubsequence([.popUp, .perk, .walk, .sniff], of: trace(&b, from: 30, to: 40)))
}

@Test func hiddenShelfStopsEverything() {
    var b = awake()
    b.placeBall(now: 6)
    b.shelfHidden(now: 7)
    #expect(!b.isVisible && b.ball == nil)
    #expect(b.nextWake(now: 7) == nil)
}

@Test func appearsTwoToFiveSecondsAfterShow() {
    for seed: UInt64 in 1...20 {
        var b = brain(.playful, seed: seed)
        var first: Double?
        run(&b, from: 0, to: 8) { b, t in if first == nil && b.activity != .away { first = t } }
        #expect(first.map { $0 >= 2 && $0 <= 5.05 } == true)
    }
}

// MARK: Ball

@Test func flickedBallRollsWithFrictionAndSpins() {
    var b = awake(.lazy)
    b.releaseBall(at: 100, velocity: 200, now: 6)
    run(&b, from: 6, to: 9)
    // v²/2f = 133 pt of travel, then it stops.
    #expect(abs((b.ball ?? 0) - 233.3) < 4)
    #expect(b.ballSpeed == 0)
    #expect(b.ballSpin > 133 / PetBrain.ballRadius - 1)
}

@Test func ballBouncesOffFloorEndsAndRollsOffOnHardFlick() {
    var b = awake(.lazy)
    var bounced = false
    b.releaseBall(at: 250, velocity: 230, now: 6)
    run(&b, from: 6, to: 9) { b, _ in if b.ballSpeed < 0 { bounced = true } }
    #expect(bounced && !b.ballGone)
    #expect(b.ballRange.contains(b.ball ?? -999))
    var hard = awake(.lazy)
    hard.releaseBall(at: 250, velocity: 700, now: 6)
    run(&hard, from: 6, to: 6.5)
    #expect(hard.ballGone)
}

@Test func catFetchesTheBallBack() {
    var b = awake(.playful)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.9))
    b.releaseBall(at: 250, velocity: 700, now: 6)
    var seen: [PetBrain.Activity] = []
    var wentOffstage = false
    run(&b, from: 6, to: 30) { b, _ in
        if seen.last != b.activity { seen.append(b.activity) }
        if b.isOffstage { wentOffstage = true }
    }
    #expect(wentOffstage)
    #expect(isSubsequence([.run, .carry, .dropBall], of: seen), "\(seen)")
    #expect(b.ballVisible && !b.ballGone)
}

@Test func playLoopBatsBackTowardPointer() {
    var b = awake(.mischievous)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.95))
    b.place(at: 40)
    b.cursorX = 100
    b.releaseBall(at: 200, velocity: 0, now: 6)
    var seen: [PetBrain.Activity] = []
    var stopsAt: Double?
    run(&b, from: 6, to: 12) { b, _ in
        if seen.last != b.activity { seen.append(b.activity) }
        if b.activity == .bat && stopsAt == nil, let ball = b.ball {
            stopsAt = ball + b.ballSpeed * abs(b.ballSpeed) / (2 * PetBrain.friction)
        }
    }
    #expect(isSubsequence([.perk, .run, .crouch, .pounce, .bat], of: seen), "\(seen)")
    #expect(b.rounds >= 1)
    // Batted back so it rolls to a stop near the pointer.
    #expect(stopsAt.map { abs($0 - 100) < 3 } == true, "\(String(describing: stopsAt))")
}

@Test func interestFadesAfterRounds() {
    var b = awake(.lazy)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.5))
    b.cursorX = 140
    b.releaseBall(at: 200, velocity: 0, now: 6)
    var lastPlay: Double = 0
    var other: PetBrain.Routine?
    run(&b, from: 6, to: 60) { b, t in
        if b.routine == .play { lastPlay = t } else if lastPlay > 0, other == nil, b.routine != nil { other = b.routine }
    }
    #expect(other == .explore || other == .nap)
    #expect(b.ball != nil) // The ball idles where it stopped.
}

// MARK: Sleep, Reduce Motion

@Test func sleepsAfterIdle() {
    for p in PetPersonality.concrete {
        var b = brain(p, seed: 3)
        var asleepAt: Double?
        run(&b, from: 0, to: 70) { b, t in if asleepAt == nil && b.activity == .sleep { asleepAt = t } }
        // Appear (≤ 5 s) + 30 s idle + the walk to its nook.
        #expect(asleepAt.map { $0 <= 5 + PetBrain.sleepAfter + 15 } == true, "\(p)")
        #expect((b.nextWake(now: 70) ?? 0) >= 1) // Asleep: only a slow tick for the z's.
    }
}

@Test func reduceMotionKeepsPetStatic() {
    var b = brain(.playful, reduceMotion: true)
    var poses = Set<PetPose>()
    var xs = Set<Double>()
    run(&b, from: 0, to: 60) { b, t in
        if let f = b.frame(at: t) {
            poses.insert(f.pose)
            #expect(f.step == 0)
        }
        xs.insert(b.x)
        if Int(t * 20) == 200 { b.releaseBall(at: 10, velocity: 300, now: t) }
        if Int(t * 20) == 240 { b.pet(now: t) }
        if Int(t * 20) == 300 { b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: t) }
    }
    #expect(poses.isSubset(of: [.sit, .sleep, .purr, .perk, .sad, .hide]), "\(poses)")
    #expect(xs.count == 1)
    #expect(b.nextWake(now: 60) == nil) // Asleep and static: no ticks at all.
}

@Test func sameSeedSameBehavior() {
    func once() -> [PetBrain.Activity] {
        var b = brain(.curious, seed: 99)
        return trace(&b, from: 0, to: 90)
    }
    #expect(once() == once())
    #expect(once().count > 5)
}

// MARK: Opt-in, preferences

@Test func optInModes() {
    func mode(enabled: Bool = false, preview: Bool = true, sessions: Int, asked: Bool = false, feature: Bool = true) -> PetOptIn.Mode {
        PetOptIn.mode(feature: feature, enabled: enabled, preview: preview, sessions: sessions, asked: asked)
    }
    #expect(mode(sessions: 1) == .off)
    #expect(mode(sessions: 2) == .preview)
    #expect(mode(sessions: 3) == .preview)
    #expect(mode(sessions: 4) == .ask)
    #expect(mode(sessions: 4, asked: true) == .off)
    #expect(mode(preview: false, sessions: 2) == .off)
    #expect(mode(enabled: true, preview: false, sessions: 0) == .on)
    #expect(mode(enabled: true, sessions: 0, feature: false) == .off)
}

@Test func previewThenAskOnce() throws {
    let d = try #require(UserDefaults(suiteName: "PetTests-\(UUID().uuidString)"))
    #expect(Preferences.petMode(d) == .off) // Default: pet off, preview off.
    d.set(true, forKey: Preferences.petPreview)
    var modes: [PetOptIn.Mode] = []
    for _ in 1...5 {
        Preferences.recordPetSession(d)
        modes.append(Preferences.petMode(d))
    }
    #expect(modes == [.off, .preview, .preview, .ask, .ask])
    Preferences.answerPetQuestion(keep: false, d)
    #expect(Preferences.petMode(d) == .off)
    Preferences.recordPetSession(d)
    #expect(Preferences.petMode(d) == .off) // Never asked again.

    let keep = try #require(UserDefaults(suiteName: "PetTests-\(UUID().uuidString)"))
    keep.set(true, forKey: Preferences.petPreview)
    keep.set(4, forKey: Preferences.petSessions)
    Preferences.answerPetQuestion(keep: true, keep)
    #expect(Preferences.petMode(keep) == .on)
}

@Test func sendHomeTurnsPetOff() throws {
    let d = try #require(UserDefaults(suiteName: "PetTests-\(UUID().uuidString)"))
    d.set(true, forKey: Preferences.petEnabled)
    #expect(Preferences.petMode(d) == .on)
    Preferences.sendPetHome(d)
    #expect(!d.bool(forKey: Preferences.petEnabled))
    #expect(Preferences.petMode(d) == .off)
}

@Test func nameAndPersonalityDefaults() throws {
    let d = try #require(UserDefaults(suiteName: "PetTests-\(UUID().uuidString)"))
    #expect(Preferences.petDisplayName(d) == "Mochi")
    d.set("  ", forKey: Preferences.petName)
    #expect(Preferences.petDisplayName(d) == "Mochi")
    d.set("Biscuit", forKey: Preferences.petName)
    #expect(Preferences.petDisplayName(d) == "Biscuit")
    #expect(Preferences.petPersonalityChoice(d) == .playful)
    var rng = SplitMix64(seed: 1)
    #expect(PetPersonality.concrete.contains(PetPersonality.surprise.resolved(using: &rng)))
}

/// ADR-016: the store-observation callback may run off main; it must hop to main without trapping.
@Test func observationCallbackOffMain() async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        let callback = PetController.onMain { done.resume() }
        DispatchQueue.global().async { callback() }
    }
}
