import AppKit
import Foundation
import Testing
@testable import DragShelf

/// Brain on a shown shelf with items: 280 pt floor track, three first-row tiles, clock at 0, midday.
nonisolated private func brain(_ p: PetPersonality = .playful, seed: UInt64 = 7, reduceMotion: Bool = false) -> PetBrain {
    var b = PetBrain(traits: p.traits, seed: seed)
    b.track = 280
    b.tiles = [40, 140, 240]
    b.reduceMotion = reduceMotion
    b.shelfShown(hasItems: true, now: 0)
    return b
}

/// Ticks every `dt` from `from` to `to`, calling `each` after every tick.
nonisolated private func run(_ b: inout PetBrain, from: Double, to: Double, dt: Double = 0.05,
                 _ each: (inout PetBrain, Double) -> Void = { _, _ in }) {
    var t = from
    while t <= to {
        b.tick(now: t)
        each(&b, t)
        t += dt
    }
}

/// Distinct activities in order of appearance from `from` to `to`.
nonisolated private func trace(_ b: inout PetBrain, from: Double, to: Double) -> [PetBrain.Activity] {
    var out: [PetBrain.Activity] = []
    run(&b, from: from, to: to) { b, _ in if out.last != b.activity { out.append(b.activity) } }
    return out
}

/// Visible and settled (popped up) at t = 6.
nonisolated private func awake(_ p: PetPersonality = .playful, seed: UInt64 = 7) -> PetBrain {
    var b = brain(p, seed: seed)
    run(&b, from: 0, to: 6)
    return b
}

nonisolated private func isSubsequence(_ needle: [PetBrain.Activity], of hay: [PetBrain.Activity]) -> Bool {
    var i = 0
    for a in hay where i < needle.count && a == needle[i] { i += 1 }
    return i == needle.count
}

// MARK: Personality and needs

nonisolated private func shares(_ p: PetPersonality) -> [PetBrain.Routine: Double] {
    var b = brain(p, seed: 42)
    var counts: [PetBrain.Routine: Double] = [:]
    for _ in 0..<4000 { counts[b.chooseRoutine(), default: 0] += 1 }
    return counts.mapValues { $0 / 4000 }
}

@Test nonisolated func personalitiesShapeRoutines() {
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
@Test nonisolated func sleepIsTheDefault() {
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

@Test nonisolated func routineNapsAreLong() {
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

@Test nonisolated func needsDriftByPersonality() {
    var lazy = awake(.lazy), playful = awake(.playful)
    run(&lazy, from: 6, to: 26) { b, t in if Int(t * 20) % 100 == 0 { b.pet(now: t) } }
    run(&playful, from: 6, to: 26) { b, t in if Int(t * 20) % 100 == 0 { b.pet(now: t) } }
    #expect(lazy.needs.energy < playful.needs.energy)
    #expect(playful.needs.play > 0.4)
}

@Test nonisolated func tiredCatNapsAtItsFavoriteSpot() {
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

@Test nonisolated func napRoutineRunsInOrder() {
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

@Test nonisolated func exploreAndInspectRoutines() {
    var e = awake(.curious)
    e.start(.explore, now: 6)
    #expect(isSubsequence([.walk, .sit, .look], of: trace(&e, from: 6, to: 30)))
    var i = awake(.curious)
    i.start(.inspect, now: 6)
    #expect(isSubsequence([.walk, .sniff, .sit], of: trace(&i, from: 6, to: 30)))
}

@Test nonisolated func neverTeleports() {
    for seed: UInt64 in 1...6 {
        var b = brain(.playful, seed: seed)
        var last: Double?
        var maxStep = 0.0
        run(&b, from: 0, to: 150) { b, t in
            switch Int(t * 20) {
            case 400: b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: t)
            case 1200: b.setDragging(true, now: t)
            case 1300: b.setDragging(false, now: t)
            case 1500: b.cursorMoved(SIMD2(200, 30), now: t)
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

@Test nonisolated func facesWhereItWalks() {
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

@Test nonisolated func reactionsFire() {
    var b = awake()
    b.place(at: 140)
    b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: 6)
    #expect(b.activity == .perk)
    #expect(b.facingRight) // Looks toward the new tile.
    #expect(isSubsequence([.perk, .walk, .sniff], of: trace(&b, from: 6, to: 12)))
    #expect(abs(b.x - 240) < 1) // Right under the new tile.

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

// MARK: Tile play

/// A curious cat walks under a new tile, sniffs, bats it (it wiggles) and sits admiring it.
@Test nonisolated func newTileIsPlayedWith() {
    var b = awake(.curious, seed: 3)
    b.place(at: 40)
    b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: 6)
    let seen = trace(&b, from: 6, to: 20)
    #expect(isSubsequence([.perk, .walk, .sniff, .batTile, .sit], of: seen), "\(seen)")
    #expect(b.tileBats >= 1)
    #expect(b.frame(at: 20) != nil)
}

/// Share of tile plays (over 300 seeds) that bat or knock the tile, and that knock it.
nonisolated private func tilePlayShares(_ p: PetPersonality) -> (bat: Double, knock: Double) {
    var bats = 0.0, knocks = 0.0
    for seed: UInt64 in 1...300 {
        var b = awake(p, seed: seed)
        b.place(at: 140)
        b.start(.inspect, now: 6)
        let seen = trace(&b, from: 6, to: 22)
        if seen.contains(.batTile) || seen.contains(.knockTile) { bats += 1 }
        if seen.contains(.knockTile) { knocks += 1 }
    }
    return (bats / 300, knocks / 300)
}

@Test nonisolated func tilePlayFollowsPersonality() {
    for p: PetPersonality in [.curious, .playful, .mischievous] {
        #expect(tilePlayShares(p).bat > 0.75, "\(p)")
    }
    for p: PetPersonality in [.lazy, .shy] {
        #expect(tilePlayShares(p).bat < 0.5, "\(p)")
    }
    // Only a mischievous cat knocks tiles (and then looks around as if nothing happened).
    #expect(tilePlayShares(.mischievous).knock > 0.25)
    #expect(tilePlayShares(.curious).knock == 0)
}

@Test nonisolated func knockThenInnocentLook() {
    for seed: UInt64 in 1...40 {
        var b = awake(.mischievous, seed: seed)
        b.start(.inspect, now: 6)
        let seen = trace(&b, from: 6, to: 22)
        if seen.contains(.knockTile) {
            #expect(isSubsequence([.knockTile, .look], of: seen))
            #expect(b.tileKnocks == 1)
            return
        }
    }
    Issue.record("no knock in 40 seeds")
}

/// Nothing on screen to play with: no inspect routine.
@Test nonisolated func noVisibleTilesNoInspect() {
    var b = brain(.curious)
    b.tiles = []
    #expect(b.routineWeights().first { $0.0 == .inspect }?.1 == 0)
}

/// Only tiles mostly inside the grid's visible area count; the lowest such row is the one above the cat.
@Test nonisolated func bottomRowIsTheLowestRowOnScreen() {
    let ids = (0..<8).map { _ in UUID() }
    func tile(_ col: Int, _ row: Int) -> CGRect { CGRect(x: 12 + CGFloat(col) * 88, y: 60 + CGFloat(row) * 115, width: 80, height: 103) }
    var frames: [UUID: CGRect] = [:]
    for i in 0..<8 { frames[ids[i]] = tile(i % 3, i / 3) } // Rows 0, 1, 2 (row 2: two tiles).
    // Scrolled so row 2 is cut off after 20 pt: row 1 is the bottom row on screen.
    let viewport = CGRect(x: 0, y: 60, width: 288, height: 250)
    let row = PetController.bottomRow(frames, viewport: viewport)
    #expect(row.map(\.id) == [ids[3], ids[4], ids[5]])
    #expect(row.map(\.x) == [52, 140, 228])
    // Scrolled to the end: row 2 is fully in view.
    let end = PetController.bottomRow(frames, viewport: viewport.offsetBy(dx: 0, dy: 115))
    #expect(end.map(\.id) == [ids[6], ids[7]])
    // Rows scrolled above the viewport never count.
    #expect(PetController.bottomRow(frames, viewport: CGRect(x: 0, y: 1000, width: 288, height: 250)).isEmpty)
}

// MARK: Tips

/// Each gesture walks to its spot and plays its pose; the bubble shows from the gesture for `tipLength`.
@Test nonisolated func tipGesturesAndBubbleTiming() {
    let cases: [(PetBrain.TipGesture, Double?, PetBrain.Activity)] = [
        (.patRim, nil, .pat), (.pawTap, nil, .pawTap), (.nudgeTile, 240, .batTile), (.pointUp, 230, .pointUp),
        (.pointAtTile, 240, .pointUp), (.wave, nil, .wave), (.shrug, nil, .shrug), (.lookAround, nil, .look),
    ]
    for (g, target, act) in cases {
        var b = awake(.curious, seed: 11)
        b.place(at: 140)
        b.start(.idle, now: 6)
        b.deliverTip(g, target: target, now: 6)
        var began: Double?, at = 0.0
        run(&b, from: 6, to: 20) { b, t in if began == nil && b.activity == act { began = t; at = b.x } }
        let start = try! #require(began, "\(g)")
        #expect(b.tipAt.map { abs($0 - start) < 0.06 } == true, "\(g)")
        #expect(b.tipShowing(at: start + 1) && !b.tipShowing(at: start + PetBrain.tipLength + 0.1), "\(g)")
        if g == .pointUp { #expect(abs(at - 230) < 1) } // Under the button.
        if g == .nudgeTile { #expect(b.tileBats == 1) }
        if g == .pointAtTile { #expect(abs(at - 214) < 1) } // Beside the tile.
    }
}

@Test nonisolated func tipWakesTheCatOrLazyPeeks() {
    var c = awake(.curious, seed: 4)
    c.setNeeds(PetBrain.Needs(energy: 0.2, curiosity: 0.2, play: 0.2))
    c.start(.nap, now: 6)
    run(&c, from: 6, to: 20)
    #expect(c.isAsleep)
    c.deliverTip(.wave, target: nil, now: 20)
    #expect(isSubsequence([.stretch, .wave], of: trace(&c, from: 20, to: 30)))

    var l = awake(.lazy, seed: 4)
    l.setNeeds(PetBrain.Needs(energy: 0.2, curiosity: 0.2, play: 0.2))
    l.start(.nap, now: 6)
    run(&l, from: 6, to: 20)
    l.deliverTip(.wave, target: nil, now: 20)
    #expect(l.activity == .peekEye)
    #expect(l.tipShowing(at: 21))
}

@Test nonisolated func tipNeverDuringDragAndEndsWhenOneStarts() {
    var b = awake(.curious, seed: 2)
    b.setDragging(true, now: 6)
    b.deliverTip(.wave, target: nil, now: 6)
    run(&b, from: 6, to: 12)
    #expect(b.tipAt == nil)

    var d = awake(.curious, seed: 2)
    d.deliverTip(.wave, target: nil, now: 6)
    run(&d, from: 6, to: 8)
    #expect(d.tipShowing(at: 8))
    d.setDragging(true, now: 8)
    #expect(!d.tipShowing(at: 8.1))
}

@Test nonisolated func learnedTipGetsAHappyBounce() {
    var b = awake(.curious, seed: 2)
    b.deliverTip(.pawTap, target: nil, now: 6)
    run(&b, from: 6, to: 8)
    b.tipLearned(now: 8)
    #expect(!b.tipShowing(at: 8.1))
    #expect(b.activity == .hop)
    #expect(b.lift(at: 8.17) > 4)
    #expect(isSubsequence([.hop, .leanIn], of: trace(&b, from: 8, to: 11)))
}

@Test nonisolated func reduceMotionTipHasNoGesture() {
    var b = brain(.curious, reduceMotion: true)
    run(&b, from: 0, to: 6)
    let x = b.x
    b.deliverTip(.wave, target: 200, now: 6)
    var poses = Set<PetPose>()
    run(&b, from: 6, to: 14) { b, t in if let f = b.frame(at: t) { poses.insert(f.pose) } }
    #expect(poses.isSubset(of: [.sit, .sleep, .perk]), "\(poses)")
    #expect(b.x == x)
    #expect(b.tipAt != nil) // The bubble still shows.
}

/// A tip arriving before the cat is in brings it in right away.
@Test nonisolated func tipCallsTheCatIn() {
    var b = brain(.curious)
    b.deliverTip(.patRim, target: nil, now: 0.1)
    #expect(isSubsequence([.walk, .pat], of: trace(&b, from: 0.1, to: 8)))
}

@MainActor @Test func gesturePerTip() {
    let expected: [HintEngine.Hint: PetBrain.TipGesture] = [
        .firstDrop: .patRim, .paste: .pawTap, .dragOut: .pawTap, .holdCommand: .nudgeTile, .recent: .pointUp,
        .moveResize: .pointUp, .pin: .pointAtTile, .hotkey: .wave, .clear: .shrug, .search: .lookAround,
    ]
    for hint in HintEngine.Hint.allCases { #expect(PetController.gesture(for: hint) == expected[hint], "\(hint)") }
}

// MARK: Drag

@Test nonisolated func runsOutToNearerSideDuringDragAndWalksBack() {
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

@Test nonisolated func hiddenShelfStopsEverything() {
    var b = awake()
    b.start(.bringBall, now: 6)
    b.shelfHidden(now: 7)
    #expect(!b.isVisible && b.ball == nil)
    #expect(b.nextWake(now: 7) == nil)
}

@Test nonisolated func appearsTwoToFiveSecondsAfterShow() {
    for seed: UInt64 in 1...20 {
        var b = brain(.playful, seed: seed)
        var first: Double?
        run(&b, from: 0, to: 8) { b, t in if first == nil && b.activity != .away { first = t } }
        #expect(first.map { $0 >= 2 && $0 <= 5.05 } == true)
    }
}

// MARK: Own ball

@Test nonisolated func catBringsItsOwnBallPlaysAndPushesItOut() {
    var b = awake(.playful)
    b.setNeeds(PetBrain.Needs(energy: 0.9, curiosity: 0.2, play: 0.9))
    #expect(b.ball == nil)
    b.start(.bringBall, now: 6)
    var seen: [PetBrain.Activity] = []
    var wentOffstage = false, ballShown = false, ballGoneSeen = false
    var ballAtPush: Double?
    var cleared = false
    run(&b, from: 6, to: 80) { b, _ in
        if seen.last != b.activity { seen.append(b.activity) }
        if b.isOffstage { wentOffstage = true }
        if b.ballVisible { ballShown = true }
        if b.ballGone { ballGoneSeen = true }
        if ballGoneSeen && b.ball == nil && !b.catHasBall { cleared = true }
        if b.activity == .pushOut && ballAtPush == nil { ballAtPush = b.ball }
    }
    #expect(wentOffstage && ballShown && ballGoneSeen)
    #expect(isSubsequence([.run, .carry, .dropBall, .perk, .run, .crouch, .pounce, .bat, .run, .pushOut], of: seen), "\(seen)")
    #expect(cleared) // Pushed off the edge: gone.
}

@Test nonisolated func ownBallIsOccasionalAndNeverWhileStatic() {
    var b = brain(.playful, seed: 42)
    var n = 0
    for _ in 0..<2000 where b.chooseRoutine() == .bringBall { n += 1 }
    #expect(n > 160 && n < 500, "\(n)") // A regular game, not constant.
    var s = brain(.playful, reduceMotion: true)
    run(&s, from: 0, to: 200) { s, _ in #expect(s.ball == nil) }
}

// MARK: Sleep, Reduce Motion

@Test nonisolated func sleepsAfterIdle() {
    for p in PetPersonality.concrete {
        var b = brain(p, seed: 3)
        var asleepAt: Double?
        run(&b, from: 0, to: 70) { b, t in if asleepAt == nil && b.activity == .sleep { asleepAt = t } }
        // Appear (≤ 5 s) + 30 s idle + the walk to its nook.
        #expect(asleepAt.map { $0 <= 5 + PetBrain.sleepAfter + 15 } == true, "\(p)")
        #expect((b.nextWake(now: 70) ?? 0) >= 1) // Asleep: only a slow tick for the z's.
    }
}

@Test nonisolated func reduceMotionKeepsPetStatic() {
    var b = brain(.playful, reduceMotion: true)
    var poses = Set<PetPose>()
    var xs = Set<Double>()
    run(&b, from: 0, to: 60) { b, t in
        if let f = b.frame(at: t) {
            poses.insert(f.pose)
            #expect(f.step == 0)
        }
        xs.insert(b.x)
        if Int(t * 20) == 200 { b.cursorMoved(SIMD2(200, 30), now: t) } // Static: no cursor play.
        if Int(t * 20) == 240 { b.pet(now: t) }
        if Int(t * 20) == 300 { b.itemsChanged(count: 4, addedAt: 240, removedAt: nil, now: t) }
    }
    #expect(poses.isSubset(of: [.sit, .sleep, .purr, .perk, .sad, .hide]), "\(poses)")
    #expect(xs.count == 1)
    #expect(b.nextWake(now: 60) == nil) // Asleep and static: no ticks at all.
}

@Test nonisolated func sameSeedSameBehavior() {
    func once() -> [PetBrain.Activity] {
        var b = brain(.curious, seed: 99)
        return trace(&b, from: 0, to: 90)
    }
    #expect(once() == once())
    #expect(once().count > 5)
}

// MARK: Cursor play

/// Awake and sitting at x = 140 at t = 6.
nonisolated private func sitting(_ p: PetPersonality, seed: UInt64) -> PetBrain {
    var b = awake(p, seed: seed)
    b.place(at: 140)
    b.start(.idle, now: 6)
    return b
}

/// Share of each response to a pointer at `at` for `s` over 400 seeds.
nonisolated private func responseShares(_ p: PetPersonality, _ s: PetBrain.Stimulus, at: SIMD2<Double>) -> [PetBrain.CursorResponse: Double] {
    var counts: [PetBrain.CursorResponse: Double] = [:]
    for seed: UInt64 in 1...400 {
        var b = sitting(p, seed: seed)
        b.cursorMoved(at, now: 6)
        b.stimulate(s, now: 30) // Fresh decision: attention back up, no cooldown.
        counts[b.lastResponse!, default: 0] += 1
    }
    return counts.mapValues { $0 / 400 }
}

/// Every decision (time, stimulus, response) while `drive` moves the pointer from `from` to `to`.
nonisolated private func decisions(_ b: inout PetBrain, from: Double, to: Double, dt: Double = 1.0 / 30,
                       _ drive: (inout PetBrain, Double) -> Void) -> [(Double, PetBrain.Stimulus, PetBrain.CursorResponse)] {
    var out: [(Double, PetBrain.Stimulus, PetBrain.CursorResponse)] = []
    var seen = b.decisions
    run(&b, from: from, to: to, dt: dt) { b, t in
        drive(&b, t)
        if b.decisions != seen {
            seen = b.decisions
            out.append((t, b.lastStimulus!, b.lastResponse!))
        }
    }
    return out
}

@Test nonisolated func personalitiesRespondToThePointerDifferently() {
    let above = SIMD2(170.0, 70.0)
    func share(_ p: PetPersonality, _ r: PetBrain.CursorResponse) -> Double { responseShares(p, .enter, at: above)[r] ?? 0 }
    // Lazy mostly ignores; curious mostly watches; playful pounces most; mischievous sneaks (fake ignore, then pounce).
    #expect(share(.lazy, .ignore) > 0.45)
    #expect(share(.curious, .watch) > max(share(.curious, .follow), share(.curious, .pounce), share(.curious, .ignore)))
    #expect(share(.curious, .follow) > 0.12) // Sometimes walks over and sniffs.
    #expect(share(.playful, .pounce) > share(.curious, .pounce) + 0.1)
    #expect(share(.playful, .pounce) > share(.mischievous, .pounce))
    #expect(share(.mischievous, .sneak) > 0.2 && share(.mischievous, .sneak) > share(.playful, .sneak) * 2)
    #expect(share(.shy, .watch) > 0.4 && share(.shy, .follow) < 0.1)
    // A pointer far above the cat is out of jumping range.
    #expect((responseShares(.playful, .enter, at: SIMD2(170, 200))[.pounce] ?? 0) == 0)
    // Very close: shy backs off, playful bats.
    let close = SIMD2(150.0, 25.0)
    #expect((responseShares(.shy, .near, at: close)[.backOff] ?? 0) > 0.3)
    #expect((responseShares(.playful, .near, at: close)[.backOff] ?? 0) == 0)
    #expect((responseShares(.playful, .near, at: close)[.bat] ?? 0) > 0.3)
}

@Test nonisolated func repeatedStimulationWearsAttentionOff() {
    var early = 0, late = 0
    for seed: UInt64 in 1...100 {
        var b = sitting(.playful, seed: seed)
        b.cursorMoved(SIMD2(200, 60), now: 6)
        for i in 0..<12 {
            b.stimulate(.periodic, now: 7 + Double(i) * 0.01)
            if b.lastResponse == .ignore { if i < 3 { early += 1 } else if i >= 9 { late += 1 } }
        }
    }
    #expect(late > early * 2, "early \(early), late \(late)")
    // Comes back once the pointer has been gone a while.
    var b = sitting(.playful, seed: 1)
    b.cursorMoved(SIMD2(200, 60), now: 6)
    for i in 0..<10 { b.stimulate(.periodic, now: 6 + Double(i) * 0.01) }
    let worn = b.attention
    b.cursorMoved(nil, now: 6.2)
    run(&b, from: 6.2, to: 40)
    #expect(worn < 0.2 && b.attention > 0.9)
}

@Test nonisolated func activeResponsesHaveACooldown() {
    // Find a pounce.
    var seed: UInt64 = 0, b = sitting(.playful, seed: 0)
    let t = 30.0
    while b.lastResponse != .pounce && seed < 50 {
        seed += 1
        b = sitting(.playful, seed: seed)
        b.cursorMoved(SIMD2(150, 60), now: 6)
        b.stimulate(.periodic, now: t)
    }
    #expect(b.lastResponse == .pounce)
    func active(_ now: Double) -> Double {
        b.responseWeights(.periodic, now: now).filter { $0.0.isActive }.reduce(0) { $0 + $1.1 }
    }
    #expect(active(t + 1) == 0 && active(t + 5) == 0)
    #expect(active(t + PetBrain.pounceCooldown + 0.1) > 0)
    // In real time, active responses never come closer together than the cooldown.
    for seed: UInt64 in 1...30 {
        var c = sitting(.playful, seed: seed)
        var last: Double?
        let made = decisions(&c, from: 6, to: 40) { c, t in
            // Wanders over the shelf, above the cat, now and then stopping.
            if Int(t * 30) % 45 < 30 { c.cursorMoved(SIMD2(100 + 80 * sin(t), 60 + 20 * cos(t * 0.7)), now: t) }
        }
        for (time, _, r) in made where r.isActive {
            if let l = last { #expect(time - l >= PetBrain.cursorCooldown - 0.05, "seed \(seed)") }
            last = time
        }
    }
}

@Test nonisolated func pointerIsNotChasedEveryPixel() {
    // Constant motion over the shelf: a handful of decisions, not one per move.
    var b = sitting(.curious, seed: 5)
    let made = decisions(&b, from: 6, to: 26) { b, t in b.cursorMoved(SIMD2(140 + 100 * sin(t * 0.8), 90), now: t) }
    #expect(made.count >= 2 && made.count <= 12, "\(made.count)")
    #expect(made.first?.1 == .enter)
}

@Test nonisolated func enterWakesSleepingCatOnlySometimesAndRunsOrWalksOver() {
    var woke = 0, ignored = 0, twitched = 0
    for seed: UInt64 in 1...60 {
        var b = awake(.playful, seed: seed)
        b.place(at: 30)
        b.start(.nap, now: 6)
        run(&b, from: 6, to: 20)
        guard b.isAsleep else { continue }
        b.cursorMoved(SIMD2(220, 60), now: 20)
        if b.lastResponse == .ignore {
            ignored += 1
            if b.frame(at: 20.1)?.turn == 1 { twitched += 1 } // An ear flicks.
        } else if b.activity == .stretch {
            woke += 1
            let seen = trace(&b, from: 20, to: 30)
            #expect(seen.contains(.run) || seen.contains(.walk) || seen.contains(.watch), "\(seen)")
        }
    }
    #expect(woke > 3 && ignored > 10 && twitched == ignored, "woke \(woke) ignored \(ignored)")
}

@Test nonisolated func pounceUpAtAPointerAbove() {
    var jumped = 0
    for seed: UInt64 in 1...60 {
        var b = sitting(.playful, seed: seed)
        var maxLift = 0.0
        var seen: [PetBrain.Activity] = []
        run(&b, from: 6, to: 16) { b, t in
            if t < 6.1 { b.cursorMoved(SIMD2(150, 80), now: t) }
            if seen.last != b.activity { seen.append(b.activity) }
            maxLift = max(maxLift, b.lift(at: t))
        }
        if isSubsequence([.crouch, .pounceUp, .sit], of: seen) {
            jumped += 1
            #expect(maxLift > 30 && maxLift <= 46, "\(maxLift)")
        }
    }
    #expect(jumped > 15, "\(jumped)")
}

@Test nonisolated func lingeringAtTheHeadGetsAHeadRub() {
    var rubs = 0
    for seed: UInt64 in 1...40 {
        var b = sitting(.curious, seed: seed)
        var arrived: Double?
        let made = decisions(&b, from: 6, to: 14) { b, t in
            // Rests on the cat's head (following it if it moves).
            if arrived == nil { arrived = t }
            b.cursorMoved(SIMD2(b.x + 4, 38), now: arrived!)
        }
        for (time, s, r) in made where s == .dwell {
            #expect(time - arrived! >= PetBrain.dwellAfter - 0.05)
            if r == .headRub { rubs += 1 }
        }
    }
    #expect(rubs > 20, "\(rubs)")
}

@Test nonisolated func slowAlongTheBackGetsABodyRubAndStrokingGetsPetting() {
    var bodyRubs = 0, petting = 0
    for seed: UInt64 in 1...40 {
        var b = sitting(.curious, seed: seed)
        b.stimulate(.enter, now: 6) // (no pointer yet: ignored)
        let slow = decisions(&b, from: 6, to: 9) { b, t in
            // 30 pt/s along the back, one way.
            b.cursorMoved(SIMD2(120 + 30 * (t - 6) * 0.5, 24), now: t)
        }
        if slow.contains(where: { $0.1 == .alongBack && $0.2 == .bodyRub }) { bodyRubs += 1 }
        var c = sitting(.curious, seed: seed)
        let strokes = decisions(&c, from: 6, to: 9) { c, t in
            // Back and forth over the cat, about twice a second.
            c.cursorMoved(SIMD2(c.x + 16 * sin(t * 12), 22), now: t)
        }
        if strokes.contains(where: { $0.1 == .stroke && $0.2 == .petting }) { petting += 1 }
    }
    #expect(bodyRubs > 10, "\(bodyRubs)")
    #expect(petting > 15, "\(petting)")
}

@Test nonisolated func pointerLeavingEndsCursorPlay() {
    var b = sitting(.curious, seed: 2)
    b.cursorMoved(SIMD2(150, 60), now: 6)
    var t = 6.0
    while b.routine != .cursor && t < 40 { t += 0.01; b.stimulate(.periodic, now: t) }
    #expect(b.routine == .cursor)
    b.cursorMoved(nil, now: t)
    #expect(b.routine == nil && b.activity == .perk) // Watches where it went out.
    run(&b, from: t, to: t + 15)
    #expect(b.routine != .cursor && b.cursor == nil)
}

@Test nonisolated func cursorIgnoredWhenStaticOrDraggingOrAway() {
    var s = brain(.playful, reduceMotion: true)
    run(&s, from: 0, to: 8)
    s.cursorMoved(SIMD2(200, 50), now: 8)
    #expect(s.decisions == 0)
    var d = awake()
    d.setDragging(true, now: 6)
    d.cursorMoved(SIMD2(200, 50), now: 7)
    #expect(d.decisions == 0)
    var away = brain()
    away.cursorMoved(SIMD2(200, 50), now: 0.5)
    #expect(away.activity == .away && away.decisions == 0) // Not summoned by hovering before it appears.
}

@Test nonisolated func doubleClickAlwaysCallsTheCat() {
    for p in PetPersonality.concrete {
        for seed: UInt64 in 1...10 {
            var b = awake(p, seed: seed)
            b.place(at: 30)
            b.start(.nap, now: 6)
            run(&b, from: 6, to: 20)
            b.call(at: SIMD2(220, 50), now: 20)
            #expect(b.routine == .call && b.attention == 1)
            var seen: [PetBrain.Activity] = []
            var landed: Double?
            run(&b, from: 20, to: 30) { b, _ in
                if seen.last != b.activity { seen.append(b.activity) }
                if b.activity == .watch && landed == nil { landed = b.x }
            }
            #expect(isSubsequence([.perk, .run, .crouch, .pounceUp, .sit, .watch], of: seen), "\(p) \(seen)")
            #expect(landed.map { abs($0 - 220) < 30 } == true)
            // Hangs around, more interested in the pointer for a while.
            #expect(b.interestUntil > 30)
        }
    }
    // A low spot: a ground pounce. Not on the shelf yet: comes in right away and answers.
    var low = awake(.lazy, seed: 4)
    low.call(at: SIMD2(150, 5), now: 6)
    #expect(isSubsequence([.perk, .crouch, .pounce], of: trace(&low, from: 6, to: 16)))
    var away = brain(.lazy)
    away.call(at: SIMD2(200, 40), now: 0.2)
    #expect(isSubsequence([.walk, .perk, .run, .crouch, .pounceUp], of: trace(&away, from: 0.2, to: 15)))
    // Never during a drag.
    var d = awake()
    d.setDragging(true, now: 6)
    d.call(at: SIMD2(100, 40), now: 6.5)
    #expect(d.routine != .call)
}

@MainActor @Test func doubleClickSkipsTilesHeaderAndControls() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    let tile = DragOutHandleView(frame: NSRect(x: 10, y: 10, width: 60, height: 60))
    let inTile = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    tile.addSubview(inTile)
    let header = WindowDragView(frame: .zero)
    let field = NSTextField(frame: .zero)
    for v in [tile, header, field] { root.addSubview(v) }
    #expect(ShelfPanel.callsPet(hit: root, yFromTop: 200))       // Empty grid space / bottom rim / the cat.
    #expect(ShelfPanel.callsPet(hit: nil, yFromTop: 200))
    #expect(!ShelfPanel.callsPet(hit: root, yFromTop: 20))       // Header band: double-click resets the position.
    #expect(!ShelfPanel.callsPet(hit: tile, yFromTop: 200))
    #expect(!ShelfPanel.callsPet(hit: inTile, yFromTop: 200))
    #expect(!ShelfPanel.callsPet(hit: header, yFromTop: 200))
    #expect(!ShelfPanel.callsPet(hit: field, yFromTop: 200))
}

@Test nonisolated func playWithBallStartsTheBallRoutineNow() {
    var b = sitting(.lazy, seed: 8)
    b.playBall(now: 6)
    #expect(b.routine == .bringBall)
    var shown = false
    run(&b, from: 6, to: 30) { b, _ in if b.ballVisible { shown = true } }
    #expect(shown)
    // Before the cat is in: it comes in carrying the ball.
    var away = brain(.lazy)
    away.playBall(now: 0.1)
    let seen = trace(&away, from: 0.1, to: 10)
    #expect(away.routine == .bringBall && seen.first == .carry, "\(seen)")
    var s = brain(.playful, reduceMotion: true)
    s.playBall(now: 0.1)
    #expect(s.routine != .bringBall)
}

@Test nonisolated func ballIsMoreFrequentForPlayfulAndCuriousCats() {
    func ballShare(_ p: PetPersonality) -> Double { shares(p)[.bringBall] ?? 0 }
    #expect(ballShare(.playful) > 0.08 && ballShare(.curious) > 0.07, "\(ballShare(.playful)) \(ballShare(.curious))")
    #expect(ballShare(.playful) > ballShare(.lazy) * 2)
}

// MARK: Pointer tracking

@MainActor @Test func pointerTrackerCoversThePanelAndThrottles() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless,
                          backing: .buffered, defer: true)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = view
    let tracker = PointerTracker()
    var got: [CGPoint?] = []
    tracker.onPointer = { got.append($0) }
    tracker.install(on: view)
    let area = try #require(view.trackingAreas.first { $0.owner === tracker })
    #expect(area.options.isSuperset(of: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]))
    func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, _ time: TimeInterval) -> NSEvent {
        type == .mouseMoved
            ? NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: time,
                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            : NSEvent.enterExitEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: time,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }
    tracker.mouseEntered(with: event(.mouseEntered, 10, 150, 1))
    tracker.mouseMoved(with: event(.mouseMoved, 20, 150, 1.01))  // Within 1/30 s: dropped.
    tracker.mouseMoved(with: event(.mouseMoved, 30, 40, 1.05))
    tracker.mouseExited(with: event(.mouseExited, 400, 40, 1.1))
    // Top-left origin, x and y.
    #expect(got == [CGPoint(x: 10, y: 50), CGPoint(x: 30, y: 160), nil])
    tracker.remove()
    #expect(!view.trackingAreas.contains { $0.owner === tracker })
}

@Test nonisolated func pointerMapsToRimCoordinates() {
    let stage = CGRect(x: 0, y: 236, width: 360, height: 64)
    #expect(PetController.rim(CGPoint(x: 140, y: 200), stage: stage) == SIMD2<Double>(140 - 40, 300 - 4 - 200))
    #expect(PetController.rim(CGPoint(x: 40, y: 296), stage: stage) == SIMD2<Double>(0, 0)) // Track start, on the rim.
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
