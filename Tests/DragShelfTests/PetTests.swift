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
    let mischievous = shares(.mischievous)
    func s(_ d: [PetBrain.Routine: Double], _ r: PetBrain.Routine) -> Double { d[r] ?? 0 }
    #expect(s(playful, .wander) > 2 * s(lazy, .wander))
    #expect(s(lazy, .idle) > s(playful, .idle))
    #expect(s(curious, .inspect) > 1.2 * s(playful, .inspect)) // Curious plays with the tiles.
    #expect(s(curious, .explore) > s(lazy, .explore))
    #expect(s(mischievous, .inspect) > s(lazy, .inspect))
}

/// The cat is mostly asleep: napping is the likeliest routine for every personality, and over half for most.
@Test func sleepIsTheDefault() {
    for p in PetPersonality.concrete {
        let d = shares(p)
        let nap = d[.nap] ?? 0
        #expect(nap > 0.45, "\(p) \(nap)")
        #expect(d.allSatisfy { $0.key == .nap || $0.value < nap }, "\(p)")
    }
    // Over a long session it spends most visible time asleep.
    var b = brain(.curious, seed: 5)
    var asleep = 0.0, total = 0.0
    run(&b, from: 0, to: 600, dt: 0.25) { b, t in
        if t > 10 && b.isVisible { total += 1; if b.isAsleep { asleep += 1 } }
    }
    #expect(asleep / max(total, 1) > 0.6, "\(asleep / max(total, 1))")
}

@Test func routineNapsAreLong() {
    var b = awake(.lazy)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.2))
    b.start(.nap, now: 6)
    var sleepStart: Double?, wokeAt: Double?
    run(&b, from: 6, to: 300) { b, t in
        if sleepStart == nil && b.activity == .sleep { sleepStart = t }
        if sleepStart != nil && wokeAt == nil && !b.isAsleep { wokeAt = t }
    }
    let start = try! #require(sleepStart), woke = try! #require(wokeAt)
    #expect(woke - start >= 59 && woke - start <= 181, "\(woke - start)")
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
            case 1200: b.setDragging(true, now: t)
            case 1300: b.setDragging(false, now: t)
            case 1500: b.cursorMoved(200, now: t)
            case 2200: b.pet(now: t)
            default: break
            }
            // Walking in from out of view (invisible) is not a jump.
            if let l = last, b.isVisible { maxStep = max(maxStep, abs(b.x - l)) }
            last = b.isVisible ? b.x : nil
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

@Test func runsOutToNearerSideDuringDragAndWalksBack() {
    for (start, right) in [(40.0, false), (240.0, true)] {
        var b = awake()
        b.place(at: start)
        b.start(.idle, now: 6)
        b.setDragging(true, now: 6)
        #expect(b.routine == .exit && b.activity == .run)
        b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: 7) // The drop that ends the drag: no interruption.
        var xs: [Double] = []
        run(&b, from: 6, to: 30) { b, _ in if b.isVisible { xs.append(b.x) } }
        #expect(!b.isVisible && b.isOffstage && (b.x > 0) == right, "x \(b.x)")
        #expect(b.entryRight == right)
        #expect(b.nextWake(now: 30) == nil) // Out of view and still: no ticks.
        // Never ducks: it only ever runs outward.
        #expect(zip(xs, xs.dropFirst()).allSatisfy { right ? $1 >= $0 : $1 <= $0 })
        b.setDragging(false, now: 30)
        var back: Double?
        var probe = b
        run(&probe, from: 30, to: 33) { b, t in if back == nil && b.isVisible { back = t } }
        // Walks back in about a second after the drag ends (the walk from out of view takes a moment to show).
        #expect(back.map { $0 >= 30.9 && $0 <= 32.5 } == true, "\(String(describing: back))")
        // The drop's reaction plays once it is back.
        #expect(isSubsequence([.walk, .perk, .walk, .sniff], of: trace(&b, from: 30, to: 45)))
    }
}

@Test func hiddenShelfStopsEverything() {
    var b = awake()
    b.start(.bringBall, now: 6)
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

// MARK: Own ball

@Test func catBringsItsOwnBallPlaysAndPushesItOut() {
    var b = awake(.playful)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.9))
    #expect(b.ball == nil)
    b.start(.bringBall, now: 6)
    var seen: [PetBrain.Activity] = []
    var wentOffstage = false, ballShown = false, ballGoneSeen = false
    var ballAtPush: Double?
    run(&b, from: 6, to: 80) { b, _ in
        if seen.last != b.activity { seen.append(b.activity) }
        if b.isOffstage { wentOffstage = true }
        if b.ballVisible { ballShown = true }
        if b.ballGone { ballGoneSeen = true }
        if b.activity == .pushOut && ballAtPush == nil { ballAtPush = b.ball }
    }
    #expect(wentOffstage && ballShown && ballGoneSeen)
    #expect(isSubsequence([.run, .carry, .dropBall, .perk, .run, .crouch, .pounce, .bat, .run, .pushOut], of: seen), "\(seen)")
    #expect(b.ball == nil && !b.ballGone && !b.catHasBall) // Pushed off the edge: gone.
}

@Test func ownBallIsOccasionalAndNeverWhileStatic() {
    var b = brain(.playful, seed: 42)
    var n = 0
    for _ in 0..<2000 where b.chooseRoutine() == .bringBall { n += 1 }
    #expect(n > 20 && n < 400, "\(n)") // Occasional, not constant.
    var s = brain(.playful, reduceMotion: true)
    run(&s, from: 0, to: 200) { s, _ in #expect(s.ball == nil) }
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
        if Int(t * 20) == 200 { b.cursorMoved(200, now: t) } // Static: no follow.
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

// MARK: Mouse follow

@Test func catWakesRunsToCursorAndActsCute() {
    var b = awake(.playful)
    b.place(at: 30)
    b.start(.nap, now: 6)
    run(&b, from: 6, to: 20)
    #expect(b.isAsleep)
    let at = b.x
    b.cursorMoved(220, now: 20)
    #expect(b.routine == .follow && b.followX == 220)
    #expect(b.frame(at: 20)?.pose == .stretch) // Wakes first.
    var seen: [PetBrain.Activity] = []
    var faced: Bool?, arrived: Double?
    run(&b, from: 20, to: 40) { b, _ in
        if seen.last != b.activity { seen.append(b.activity) }
        if b.activity == .run && faced == nil { faced = b.facingRight }
        if b.activity == .sit && arrived == nil { arrived = b.x }
    }
    #expect(isSubsequence([.stretch, .run, .sit, .look, .perk, .leanIn], of: seen), "\(seen)")
    #expect(faced == (220 > at)) // Faces where it runs.
    #expect(arrived.map { abs($0 - 220) < 1 } == true, "\(String(describing: arrived))")
}

@Test func followIsThrottledAndStopsWhenCursorLeaves() {
    var b = awake(.playful)
    b.place(at: 30)
    b.start(.idle, now: 6)
    b.cursorMoved(250, now: 6)
    #expect(b.followX == 250)
    // Inside the throttle window: ignored (no re-aim, no RNG use).
    b.cursorMoved(100, now: 6.05)
    #expect(b.followX == 250)
    run(&b, from: 6, to: 6.4)
    #expect(b.activity == .run && b.x > 30)
    // A small move is ignored; a big move re-aims the run.
    b.cursorMoved(255, now: 6.5)
    #expect(b.followX == 250)
    b.cursorMoved(40, now: 6.7)
    #expect(b.followX == 40 && b.activity == .run)
    run(&b, from: 6.7, to: 7.5)
    // Cursor leaves: back to routines (sits a moment, then picks its own).
    b.cursorMoved(nil, now: 7.5)
    #expect(b.followX == nil && b.routine == nil && b.activity == .sit)
    run(&b, from: 7.5, to: 20)
    #expect(b.routine != .follow)
}

@Test func followIgnoredWhenStaticOrDraggingOrAway() {
    var s = brain(.playful, reduceMotion: true)
    run(&s, from: 0, to: 8)
    s.cursorMoved(200, now: 8)
    #expect(s.followX == nil && s.routine != .follow)
    var d = awake()
    d.setDragging(true, now: 6)
    d.cursorMoved(200, now: 7)
    #expect(d.followX == nil)
    var away = brain()
    away.cursorMoved(200, now: 0.5)
    #expect(away.activity == .away && away.followX == nil) // Not summoned before it appears.
}

@Test func shyCatFollowsLessOften() {
    func follows(_ p: PetPersonality) -> Int {
        var n = 0
        for seed: UInt64 in 1...200 {
            var b = awake(p, seed: seed)
            b.place(at: 30)
            b.start(.idle, now: 6)
            b.cursorMoved(250, now: 6)
            if b.routine == .follow { n += 1 }
        }
        return n
    }
    #expect(follows(.playful) > follows(.shy) + 30)
}

@Test func curiousCatBatsATile() {
    var b = awake(.curious, seed: 3)
    var bats = 0
    for seed: UInt64 in 1...40 {
        var c = awake(.curious, seed: seed)
        c.start(.inspect, now: 6)
        if trace(&c, from: 6, to: 30).contains(.batTile) { bats += 1 }
    }
    #expect(bats > 15, "\(bats)")
    b.start(.inspect, now: 6)
    #expect(isSubsequence([.walk, .sniff], of: trace(&b, from: 6, to: 20)))
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
    #expect(Preferences.petPersonalityChoice(d) == .curious) // New users get Curious…
    d.set(PetPersonality.lazy.rawValue, forKey: Preferences.petPersonality)
    #expect(Preferences.petPersonalityChoice(d) == .lazy) // …a saved choice is kept.
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
