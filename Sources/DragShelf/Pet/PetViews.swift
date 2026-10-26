import SwiftUI

/// The cat on the shelf's bottom rim (V3-01): an overlay over the panel's own background, no band, no extra
/// height. Only the cat takes clicks; everything else falls through to the tiles. Clipped at the panel's sides, so
/// the cat leaves the shelf past an edge.
struct PetStage: View {
    let pet: PetController

    private typealias C = PetController

    var body: some View {
        stage
            .frame(maxWidth: .infinity, minHeight: C.stageHeight, maxHeight: C.stageHeight, alignment: .topLeading)
            .clipShape(SideClip())
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { pet.stageFrame = $0 }
    }

    @ViewBuilder private var stage: some View {
        if let s = pet.snapshot {
            let cx = C.trackInset + s.x
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if let b = s.ball {
                    YarnView(spin: s.ballSpin)
                        .offset(x: C.trackInset + b - 11, y: C.stageHeight - C.rimInset - 17)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if s.lift > 1 {
                    // Mid-jump: its shadow stays on the rim, smaller the higher it goes.
                    Ellipse()
                        .fill(Color.black.opacity(0.16 * (1 - s.lift / 70)))
                        .frame(width: 34 - s.lift / 3, height: 4)
                        .blur(radius: 1.2)
                        .offset(x: cx - 17 + s.lift / 6, y: C.stageHeight - C.rimInset - 2)
                        .allowsHitTesting(false)
                }
                PetSprite(frame: s.frame, facingRight: s.facingRight)
                    .contentShape(Rectangle().path(in: CGRect(x: 10, y: 10, width: 44, height: 48)))
                    .offset(x: cx - PetArt.size.width / 2, y: C.stageHeight - C.rimInset - PetArt.ground - s.lift)
                    .onTapGesture { pet.petTapped() }
                    .contextMenu {
                        Button("Pet \(pet.name)") { pet.petTapped() }
                        Button("Send Home") { pet.sendHome() }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pet, \(pet.name)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { pet.petTapped() }
                    .accessibilityAction(named: "Pet") { pet.petTapped() }
                    .accessibilityAction(named: "Send Home") { pet.sendHome() }
                if pet.asking {
                    beside(cx) { question }
                } else if let text = s.bubble {
                    beside(cx) {
                        Text(text)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .bubble()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        } else {
            Color.clear.allowsHitTesting(false)
        }
    }

    /// Bubble on whichever side of the cat has more room, at head height.
    private func beside(_ cx: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        let right = cx < pet.stageFrame.width / 2
        return content()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: right ? .leading : .trailing)
            .padding(right ? .leading : .trailing, right ? cx + 24 : max(0, pet.stageFrame.width - cx + 24))
            .padding(.top, 8)
    }

    private var question: some View {
        HStack(spacing: 6) {
            Text("Keep \(pet.name) on DragShelf?")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Button("Keep") { pet.answer(keep: true) }
                .buttonStyle(.borderedProminent)
            Button("No thanks") { pet.answer(keep: false) }
        }
        .controlSize(.mini)
        .bubble()
    }
}

/// Clips at the panel's sides only: ears, hearts and bubbles may rise above the overlay.
private struct SideClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 200, width: rect.width, height: rect.height + 220))
    }
}

private extension View {
    func bubble() -> some View {
        foregroundStyle(PetArt.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(PetArt.paper).shadow(color: .black.opacity(0.18), radius: 2, y: 1))
            .overlay(Capsule().strokeBorder(PetArt.ink.opacity(0.2), lineWidth: 0.5))
    }
}

/// One tile's wiggle (V3-01): `count` changes → it plays once. `freeze` (0…1 through it) draws one still moment
/// (snapshot review).
struct TileWiggle: Equatable {
    var count = 0
    /// Knock: a bigger shove toward the nearer edge (`toRight`), held a beat, then back.
    var knock = false
    var toRight = true
    var freeze: Double?
}

extension View {
    /// Bat a tile (V3-01): the tile wiggles once each time the wiggle's count changes. Purely visual.
    func petWiggle(_ wiggle: TileWiggle?) -> some View { modifier(PetWiggle(wiggle: wiggle ?? TileWiggle())) }
}

private struct PetWiggle: ViewModifier {
    let wiggle: TileWiggle

    struct Pose { var angle = 0.0, x = 0.0, y = 0.0 }

    func body(content: Content) -> some View {
        if let f = wiggle.freeze {
            let timeline = KeyframeTimeline(initialValue: Pose()) { keyframes }
            Self.apply(content, timeline.value(progress: f))
        } else {
            content.keyframeAnimator(initialValue: Pose(), trigger: wiggle.count) { view, pose in
                Self.apply(view, pose)
            } keyframes: { _ in keyframes }
        }
    }

    nonisolated private static func apply(_ view: some View, _ pose: Pose) -> some View {
        view.rotationEffect(.degrees(pose.angle), anchor: .bottom).offset(x: pose.x, y: pose.y)
    }

    /// Bat: a springy rock of about 7° with a small hop. Knock: wind up, shoved ~12° and 8 pt toward the edge, held,
    /// then it springs back.
    @KeyframesBuilder<Pose> private var keyframes: some Keyframes<Pose> {
        let d = wiggle.toRight ? 1.0 : -1.0, k = wiggle.knock
        KeyframeTrack(\.angle) {
            CubicKeyframe((k ? -4 : -7) * d, duration: 0.11)
            SpringKeyframe((k ? 12 : 6) * d, duration: 0.14, spring: .snappy)
            SpringKeyframe((k ? 10 : -3) * d, duration: k ? 0.45 : 0.14)
            SpringKeyframe(0, duration: k ? 0.5 : 0.3, spring: .bouncy)
        }
        KeyframeTrack(\.x) {
            LinearKeyframe(0, duration: 0.11)
            SpringKeyframe(k ? 8 * d : 0, duration: 0.14, spring: .snappy)
            LinearKeyframe(k ? 7 * d : 0, duration: k ? 0.45 : 0.14)
            SpringKeyframe(0, duration: 0.5, spring: .bouncy)
        }
        KeyframeTrack(\.y) {
            CubicKeyframe(k ? -2 : -4, duration: 0.11)
            SpringKeyframe(k ? -6 : 0, duration: 0.14, spring: .snappy)
            SpringKeyframe(0, duration: 0.4, spring: .bouncy)
        }
    }
}

/// Settings → Pet.
struct PetSettingsSection: View {
    var onPlayBall: () -> Void = {}
    @AppStorage(Preferences.petEnabled) private var enabled = false
    @AppStorage(Preferences.petPersonality) private var personality = PetPersonality.curious.rawValue
    @AppStorage(Preferences.petName) private var name = Preferences.defaultPetName
    @AppStorage(Preferences.petPreview) private var preview = false

    var body: some View {
        if Preferences.petFeatureOn() {
            Section {
                Toggle("Show pet", isOn: $enabled)
                Picker("Personality", selection: $personality) {
                    ForEach(PetPersonality.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                TextField("Name", text: $name, prompt: Text(Preferences.defaultPetName))
                Toggle("Preview on the 2nd and 3rd drag, then ask", isOn: $preview)
                Button("Play with ball", action: onPlayBall)
                    .disabled(!enabled)
                    .help("Shows DragShelf and sends \(name.isEmpty ? Preferences.defaultPetName : name) off to fetch its ball")
            } header: {
                Text("Pet")
            } footer: {
                Text("A little cat lives on the bottom edge of DragShelf. It notices your pointer in its own way: watches, follows, pounces, or enjoys a rub. Double-click it or empty shelf space to call it over. It plays with its own ball, runs off while you drag, and never touches your items. Click it to pet it; right-click to send it home.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
