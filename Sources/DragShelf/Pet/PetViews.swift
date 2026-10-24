import SwiftUI

/// The pet's play floor (V3-01): a recessed clay tray at the bottom of the shelf, with a soft front lip the cat
/// ducks behind. Present only while the pet is on. The whole panel stays the drop target.
struct PetFloor: View {
    let pet: PetController
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private typealias C = PetController

    var body: some View {
        ZStack(alignment: .topLeading) {
            tray
            stage
                .clipShape(SideClip(inset: C.trayInset))
        }
        .frame(maxWidth: .infinity, minHeight: C.floorHeight, maxHeight: C.floorHeight, alignment: .topLeading)
        .coordinateSpace(.named("petFloor"))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { pet.floorFrame = $0 }
    }

    // MARK: Tray

    private var dark: Bool { scheme == .dark }
    private var opacity: Double { reduceTransparency ? 1 : 0.7 }
    private var wall: [Color] {
        dark ? [Color(red: 0.10, green: 0.08, blue: 0.07), Color(red: 0.17, green: 0.14, blue: 0.12)]
            : [Color(red: 0.88, green: 0.82, blue: 0.75), Color(red: 0.95, green: 0.91, blue: 0.86)]
    }
    private var lip: [Color] {
        dark ? [Color(red: 0.36, green: 0.31, blue: 0.27), Color(red: 0.25, green: 0.21, blue: 0.18)]
            : [Color(red: 0.99, green: 0.96, blue: 0.92), Color(red: 0.90, green: 0.84, blue: 0.77)]
    }

    private var tray: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .top) {
            // Recessed back: darker at the top, as if lit from the front.
            shape.fill(LinearGradient(colors: wall, startPoint: .top, endPoint: .bottom)).opacity(opacity)
                .overlay(shape.strokeBorder(.black.opacity(dark ? 0.35 : 0.07), lineWidth: 1).blur(radius: 0.6))
            // Front lip: a soft rounded clay ledge with a top highlight.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: lip, startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(dark ? 0.12 : 0.7)).frame(height: 1).padding(.horizontal, 8).padding(.top, 0.5)
                }
                .shadow(color: .black.opacity(dark ? 0.35 : 0.10), radius: 1.5, y: -0.5)
                .frame(height: C.floorHeight - 4 - C.groundY + 1)
                .offset(y: C.groundY - 2 - 1)
                .overlay {
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                            .frame(height: C.floorHeight - 4 - C.groundY + 1).offset(y: C.groundY - 2 - 1)
                    }
                }
        }
        .overlay { if contrast == .increased { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) } }
        .frame(height: C.floorHeight - 4)
        .padding(.horizontal, C.trayInset)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: Cat, ball, bubble

    @ViewBuilder private var stage: some View {
        if let s = pet.snapshot {
            let cx = C.trackInset + s.x
            ZStack(alignment: .topLeading) {
                Color.clear
                if let b = s.ball {
                    YarnView(spin: s.ballSpin)
                        .offset(x: C.trackInset + b - 11, y: C.groundY - 17)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("petFloor"))
                            .onChanged { pet.holdBall(at: $0.location.x) }
                            .onEnded { pet.releaseBall(at: $0.location.x, velocity: $0.velocity.width) })
                        .help("Flick the yarn ball")
                        .accessibilityHidden(true)
                }
                let ducked = s.frame.pose == .hide || s.frame.pose == .peek
                PetSprite(frame: s.frame, facingRight: s.facingRight)
                    .contentShape(Rectangle().path(in: CGRect(x: 10, y: 10, width: 44, height: 48)))
                    .offset(x: cx - PetArt.size.width / 2, y: C.groundY - PetArt.ground)
                    .allowsHitTesting(!ducked)
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
                    .accessibilityHidden(ducked)
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
        }
    }

    /// Bubble on whichever side of the cat has more room, at head height.
    private func beside(_ cx: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        let right = cx < pet.floorFrame.width / 2
        return content()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: right ? .leading : .trailing)
            .padding(right ? .leading : .trailing, right ? cx + 24 : max(0, pet.floorFrame.width - cx + 24))
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

/// Clips the stage at the tray's sides only: the cat and ball leave the floor past an end, while ears, hearts and
/// bubbles may rise above the band.
private struct SideClip: Shape {
    let inset: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX + inset, y: rect.minY - 200, width: max(0, rect.width - 2 * inset), height: rect.height + 220))
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

/// Header button that puts the yarn ball out or away.
struct PetBallButton: View {
    let pet: PetController

    var body: some View {
        Button { pet.toggleBall() } label: {
            Label {
                Text(pet.ballOut ? "Put the yarn ball away" : "Yarn ball")
            } icon: {
                Canvas { ctx, _ in drawYarn(ctx, center: CGPoint(x: 9.5, y: 8), radius: 5.5, shadow: false) }
                    .frame(width: 16, height: 16)
            }
        }
        .help(pet.ballOut ? "Put the yarn ball away" : "Give \(pet.name) a yarn ball")
        .accessibilityAddTraits(pet.ballOut ? .isSelected : [])
    }
}

extension View {
    /// Bat a tile (V3-01): the tile wiggles once each time `count` changes. Purely visual.
    func petWiggle(_ count: Int) -> some View { modifier(PetWiggle(count: count)) }
}

private struct PetWiggle: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: count) { view, angle in
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
                Text("A little cat gets its own play floor at the bottom of DragShelf. It ducks while you drag and never touches your items. Click it to pet it; right-click to send it home.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
