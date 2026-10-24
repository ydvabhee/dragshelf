import Foundation
import Testing
@testable import DragShelf

/// Brain on a shown shelf with items, clock at 0, midday.
private func brain(_ p: PetPersonality = .playful, seed: UInt64 = 7, reduceMotion: Bool = false) -> PetBrain {
    var b = PetBrain(traits: p.traits, seed: seed)
    b.reduceMotion = reduceMotion
    b.shelfShown(hasItems: true, now: 0)
    return b
}

/// Ticks every `dt` from `from` to `to`, calling `each` after every tick.
private func run(_ b: inout PetBrain, from: Double, to: Double, dt: Double = 0.05, _ each: (inout PetBrain, Double) -> Void = { _, _ in }) {
    var t = from
    while t <= to {
        b.tick(now: t)
        each(&b, t)
        t += dt
    }
}

/// Share of each next activity over many weighted picks (idle mood: no recent activity, midday, not petted).
private func shares(_ p: PetPersonality) -> [PetBrain.Activity: Double] {
    var b = brain(p, seed: 42)
    var counts: [PetBrain.Activity: Double] = [:]
    let n = 4000
    for _ in 0..<n { counts[b.choose(now: 1000), default: 0] += 1 }
    return counts.mapValues { $0 / Double(n) }
}

@Test func personalitiesShapeChoices() {
    let playful = shares(.playful), lazy = shares(.lazy), curious = shares(.curious)
    let shy = shares(.shy), mischievous = shares(.mischievous)
    func s(_ d: [PetBrain.Activity: Double], _ a: PetBrain.Activity) -> Double { d[a] ?? 0 }
    #expect(s(playful, .walk) > 2 * s(lazy, .walk))
    #expect(s(lazy, .nap) + s(lazy, .sit) > s(playful, .nap) + s(playful, .sit) + 0.2)
    #expect(s(shy, .peek) > 3 * s(playful, .peek))
    #expect(s(mischievous, .batTile) > 4 * s(shy, .batTile))
    #expect(s(curious, .walk) > s(lazy, .walk))
    #expect(s(playful, .pounce) > s(lazy, .pounce))
    // No ball out → never "chase".
    #expect(s(playful, .chase) == 0)
}

@Test func moodFollowsTimeAndPetting() {
    var b = brain(.playful)
    b.hour = 23
    #expect(b.mood(now: 1000).sleepiness > b.traits.sleepiness)
    #expect(b.mood(now: 1000).energy < b.traits.energy)
    var shy = brain(.shy)
    let before = shy.mood(now: 1000).shyness
    run(&shy, from: 0, to: 6)
    shy.pet(now: 6)
    #expect(shy.mood(now: 1000).shyness < before)
}

@Test func sameSeedSameBehavior() {
    func trace() -> [PetBrain.Activity] {
        var b = brain(.curious, seed: 99)
        var out: [PetBrain.Activity] = []
        run(&b, from: 0, to: 60) { b, _ in if out.last != b.activity { out.append(b.activity) } }
        return out
    }
    #expect(trace() == trace())
    #expect(trace().count > 3)
}

@Test func appearsTwoToFiveSecondsAfterShow() {
    for seed: UInt64 in 1...20 {
        var b = brain(.playful, seed: seed)
        var first: Double?
        run(&b, from: 0, to: 8) { b, t in if first == nil && b.isVisible { first = t } }
        #expect(first.map { $0 >= 2 && $0 <= 5.05 } == true)
        #expect(b.nextWake(now: 0) != nil)
    }
}

@Test func emptyShelfHasNoPet() {
    var b = PetBrain(traits: PetPersonality.playful.traits, seed: 1)
    b.shelfShown(hasItems: false, now: 0)
    run(&b, from: 0, to: 10)
    #expect(!b.isVisible)
    #expect(b.nextWake(now: 10) == nil)
    b.itemsChanged(count: 2, added: true, now: 10)
    run(&b, from: 10, to: 16)
    #expect(b.isVisible)
}

@Test func neverVisibleDuringDrag() {
    var b = brain(.playful)
    run(&b, from: 0, to: 8)
    #expect(b.isVisible)
    b.setDragging(true, now: 8)
    #expect(!b.isVisible)
    #expect(b.pose == nil)
    // Petting, ball moves, and new items during the drag never bring it back.
    b.pet(now: 9)
    b.moveBall(to: 20, now: 9)
    b.itemsChanged(count: 3, added: true, now: 10)
    run(&b, from: 8, to: 40) { b, _ in #expect(!b.isVisible) }
    #expect(b.nextWake(now: 40) == nil)
    b.setDragging(false, now: 40)
    var back: Double?
    run(&b, from: 40, to: 46) { b, t in if back == nil && b.isVisible { back = t } }
    #expect(back.map { $0 >= 42 && $0 <= 45.05 } == true)
}

@Test func hiddenShelfStopsEverything() {
    var b = brain(.playful)
    run(&b, from: 0, to: 8)
    b.shelfHidden(now: 8)
    #expect(!b.isVisible)
    #expect(b.ball == nil)
    #expect(b.nextWake(now: 8) == nil)
}

@Test func sleepsAfterIdle() {
    for p in PetPersonality.concrete {
        var b = brain(p, seed: 3)
        var asleepAt: Double?
        run(&b, from: 0, to: 60) { b, t in if asleepAt == nil && b.activity == .sleep { asleepAt = t } }
        var trace: [String] = []
        var c = brain(p, seed: 3)
        run(&c, from: 0, to: 45) { b, t in if trace.last?.hasPrefix("\(b.activity)") != true { trace.append("\(b.activity)@\(Int(t))") } }
        // Appear (≤ 5 s) + idle deadline; a nap may run over it by up to 20 s.
        #expect(asleepAt.map { $0 <= 5 + PetBrain.sleepAfter + 20 + 2 } == true, "\(p) \(trace)")
        // Asleep: only a slow tick for the z's.
        #expect((b.nextWake(now: 60) ?? 0) >= 1)
    }
}

@Test func pettingWakesWithStretchThenPurr() {
    var b = brain(.lazy)
    run(&b, from: 0, to: 45)
    #expect(b.isAsleep)
    b.pet(now: 45)
    #expect(b.activity == .stretch)
    run(&b, from: 45, to: 47)
    #expect(b.activity == .purr)
}

@Test func ballChasePounceBat() {
    var b = brain(.playful, seed: 5)
    run(&b, from: 0, to: 6)
    b.place(at: 20)
    b.moveBall(to: 250, now: 6)
    #expect(b.activity == .chase)
    var seen: [PetBrain.Activity] = []
    run(&b, from: 6, to: 12) { b, _ in if seen.last != b.activity { seen.append(b.activity) } }
    #expect(seen.starts(with: [.chase, .pounce, .bat]))
    #expect(b.ball != 250) // Batted away.
    b.removeBall(now: 12)
    #expect(b.ball == nil)
    #expect(b.activity != .chase)
}

@Test func batTileCountsForWiggle() {
    var b = brain(.mischievous, seed: 11)
    run(&b, from: 0, to: 120) { b, t in if Int(t * 20) % 200 == 0 { b.pet(now: t) } }
    #expect(b.tileBats > 0)
}

@Test func reduceMotionKeepsPetStatic() {
    var b = brain(.playful, reduceMotion: true)
    var poses = Set<PetPose>()
    var xs = Set<Double>()
    run(&b, from: 0, to: 60) { b, t in
        if let p = b.pose { poses.insert(p) }
        xs.insert(b.x)
        #expect(b.step(at: t) == 0)
        if t > 10 && t < 10.06 { b.moveBall(to: 10, now: t) }
        if t > 12 && t < 12.06 { b.pet(now: t) }
    }
    #expect(poses.isSubset(of: [.sit, .sleep, .purr]))
    #expect(poses.contains(.sleep))
    #expect(xs.count == 1)
    #expect(b.nextWake(now: 60) == nil) // Asleep and static: no ticks at all.
}

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
