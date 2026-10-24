import SwiftUI

/// Pet window content: cat, yarn ball, speech bubble, laid out along the shelf's top edge.
struct PetStage: View {
    let pet: PetController

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let s = pet.snapshot {
                let cx = PetController.inset + s.x
                if let b = s.ball {
                    YarnView(spin: b / 7)
                        .offset(x: PetController.inset + b - 22, y: PetArt.ground - 15)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("stage"))
                            .onChanged { pet.dragBall(to: $0.location.x) }
                            .onEnded { _ in pet.ballDragEnded() })
                        .accessibilityHidden(true)
                }
                PetSprite(pose: s.pose, step: s.step, progress: s.progress, facingRight: s.facingRight)
                    .offset(x: cx - PetArt.size.width / 2)
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
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(width: pet.width, height: PetController.height, alignment: .topLeading)
        .coordinateSpace(.named("stage"))
    }

    /// Bubble on whichever side of the cat has more room, at head height.
    private func beside(_ cx: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        let right = cx < pet.width / 2
        return content()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: right ? .leading : .trailing)
            .padding(right ? .leading : .trailing, right ? cx + 24 : pet.width - cx + 24)
            .padding(.top, 14)
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
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("stage")) }) { pet.askRect = $0 }
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

/// Header button that puts the yarn ball out (only while the pet is on).
struct PetBallButton: View {
    private let hub = PetHub.shared

    var body: some View {
        if hub.available {
            Button { hub.toggleBall() } label: {
                Label {
                    Text(hub.ballOut ? "Put the yarn ball away" : "Yarn ball")
                } icon: {
                    Canvas { ctx, _ in drawYarn(ctx, center: CGPoint(x: 9.5, y: 8), radius: 5.5) }
                        .frame(width: 16, height: 16)
                }
            }
            .help(hub.ballOut ? "Put the yarn ball away" : "Give \(hub.name) a yarn ball")
            .accessibilityAddTraits(hub.ballOut ? .isSelected : [])
        }
    }
}

extension View {
    /// Bat a tile (V3-01): the tile wiggles once each time the pet bats it. Purely visual.
    func petWiggle(_ id: UUID) -> some View { modifier(PetWiggle(id: id)) }
}

private struct PetWiggle: ViewModifier {
    let id: UUID

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: PetHub.shared.wiggles[id] ?? 0) { view, angle in
            view.rotationEffect(.degrees(angle), anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-7, duration: 0.09)
                CubicKeyframe(6, duration: 0.12)
                CubicKeyframe(-4, duration: 0.12)
                CubicKeyframe(2, duration: 0.1)
                CubicKeyframe(0, duration: 0.1)
            }
        }
    }
}

/// Settings → Pet.
struct PetSettingsSection: View {
    @AppStorage(Preferences.petEnabled) private var enabled = false
    @AppStorage(Preferences.petPersonality) private var personality = PetPersonality.playful.rawValue
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
            } header: {
                Text("Pet")
            } footer: {
                Text("A little cat lives on top of DragShelf. It hides while you drag and never touches your items. Click it to pet it; right-click to send it home.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
