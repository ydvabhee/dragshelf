import SwiftUI

// The shelf pet's look (V3-01): original soft-clay chibi characters drawn in code. Matte shapes shaded with
// gradients (top-left light, darker underside), a soft rim and contact shadow, warm pastel palette.
// Canvas is `PetArt.size`; y grows down and `PetArt.ground` is the play floor's surface (top of the front lip).
// Side poses are drawn facing right; the view mirrors the whole pet for left.

/// Which character lives on the shelf. Each species draws every `PetPose`; behavior (`PetBrain`) is shared.
/// Only the cat exists so far; planned: penguin, baby dino, bee (flies: will need an altitude in the brain).
nonisolated enum PetSpecies: String, CaseIterable, Sendable {
    case cat
}

enum PetArt {
    static let size = CGSize(width: 64, height: 64)
    static let ground: CGFloat = 58

    /// Speech bubble ink and fill.
    static let ink = Color(red: 0.36, green: 0.27, blue: 0.22)
    static let paper = Color(red: 1.0, green: 0.98, blue: 0.95)

    static func draw(_ ctx: GraphicsContext, species: PetSpecies, frame: PetFrame) {
        switch species {
        case .cat: drawCat(ctx, frame)
        }
    }
}

// MARK: Clay toolkit (shared by every species)

/// One clay material: highlight, body color, underside.
struct Clay {
    var light, base, shade: Color

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    static let cream = Clay(light: rgb(1.0, 0.965, 0.91), base: rgb(0.96, 0.865, 0.745), shade: rgb(0.82, 0.67, 0.52))
    /// Far-side limbs: same fur, in shadow.
    static let creamShadow = Clay(light: rgb(0.92, 0.83, 0.72), base: rgb(0.87, 0.76, 0.63), shade: rgb(0.74, 0.60, 0.46))
    static let caramel = Clay(light: rgb(0.99, 0.84, 0.66), base: rgb(0.92, 0.70, 0.49), shade: rgb(0.78, 0.55, 0.37))
    static let pink = Clay(light: rgb(1.0, 0.85, 0.87), base: rgb(0.96, 0.69, 0.74), shade: rgb(0.87, 0.53, 0.61))
    static let yarn = Clay(light: rgb(1.0, 0.80, 0.86), base: rgb(0.94, 0.57, 0.68), shade: rgb(0.76, 0.39, 0.52))
}

private let eyeInk = Color(red: 0.24, green: 0.18, blue: 0.15)
private let mouthInk = Color(red: 0.45, green: 0.30, blue: 0.26)
private let shadowInk = Color(red: 0.30, green: 0.20, blue: 0.14)

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

/// A thick round-capped stroke as a fillable shape.
private func limb(_ points: CGPoint..., width: CGFloat) -> Path {
    var p = Path()
    p.addLines(points)
    return p.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

/// Fills the union of `parts` as one clay piece: radial light from the top left, darker toward the bottom right,
/// a soft rim so it reads on a white shelf. `lift` casts a soft shadow onto whatever is behind it.
private func clay(_ ctx: GraphicsContext, _ parts: [Path], _ c: Clay, lift: Bool = false) {
    guard var shape = parts.first else { return }
    for p in parts.dropFirst() { shape = shape.union(p) }
    if lift {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 1.4))
            l.fill(shape.offsetBy(dx: 0.6, dy: 1.6), with: .color(shadowInk.opacity(0.24)))
        }
    }
    let b = shape.boundingRect
    ctx.fill(shape, with: .radialGradient(
        Gradient(stops: [.init(color: c.light, location: 0), .init(color: c.base, location: 0.55),
                         .init(color: c.shade, location: 1)]),
        center: pt(b.minX + b.width * 0.36, b.minY + b.height * 0.3), startRadius: 0,
        endRadius: max(b.width, b.height) * 1.0))
    ctx.stroke(shape, with: .color(c.shade.opacity(0.6)), lineWidth: 0.7)
}

/// Soft blurred spot (highlights, blush, shadows).
private func glow(_ ctx: GraphicsContext, _ path: Path, _ color: Color, blur: CGFloat) {
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: blur))
        l.fill(path, with: .color(color))
    }
}

/// Soft shadow where the pet touches the floor.
private func contactShadow(_ ctx: GraphicsContext, x: CGFloat, halfWidth: CGFloat, strength: Double = 1) {
    glow(ctx, ellipse(x, PetArt.ground + 0.6, halfWidth, 2.2), shadowInk.opacity(0.34 * strength), blur: 1.6)
}

private func heart(_ ctx: GraphicsContext, at c: CGPoint, size s: CGFloat) {
    var p = Path()
    p.move(to: pt(c.x, c.y + s * 0.45))
    p.addCurve(to: pt(c.x - s * 0.5, c.y - s * 0.15), control1: pt(c.x - s * 0.2, c.y + s * 0.25),
               control2: pt(c.x - s * 0.5, c.y + s * 0.1))
    p.addArc(center: pt(c.x - s * 0.25, c.y - s * 0.15), radius: s * 0.25, startAngle: .degrees(180),
             endAngle: .degrees(0), clockwise: false)
    p.addArc(center: pt(c.x + s * 0.25, c.y - s * 0.15), radius: s * 0.25, startAngle: .degrees(180),
             endAngle: .degrees(0), clockwise: false)
    p.addCurve(to: pt(c.x, c.y + s * 0.45), control1: pt(c.x + s * 0.5, c.y + s * 0.1),
               control2: pt(c.x + s * 0.2, c.y + s * 0.25))
    p.closeSubpath()
    clay(ctx, [p], .pink)
}

private enum Face { case happy, sleepy, open, sad, yawn(CGFloat) }

/// Chibi face: dot eyes with a sparkle or closed "^ ^" / sleepy arcs, blush, tiny nose, "ω" mouth, whiskers.
/// Local coordinates: (0, 0) = middle of the face. `turn` (-1…1) turns the head: features slide toward that
/// side and the far side narrows (3/4 view).
private func face(_ ctx: GraphicsContext, _ f: Face, turn k: CGFloat = 0) {
    func fx(_ x: CGFloat) -> CGFloat { x * (1 - 0.3 * abs(k)) + 4 * k }
    /// 1 on the near side, shrinking on the far side.
    func near(_ s: CGFloat) -> CGFloat { 1 - 0.35 * max(0, -s * k) }
    for s: CGFloat in [-1, 1] where s * k > -0.6 {
        glow(ctx, ellipse(fx(11.2 * s), 6.2, 3.6 * near(s), 2.2), Color(red: 0.98, green: 0.55, blue: 0.62).opacity(0.55), blur: 1)
    }
    let arc = StrokeStyle(lineWidth: 1.6, lineCap: .round)
    for s: CGFloat in [-1, 1] {
        let ex = fx(7.2 * s), ey: CGFloat = 1.6, w = 2.6 * near(s)
        var p = Path()
        switch f {
        case .happy:
            p.move(to: pt(ex - w, ey + 1))
            p.addQuadCurve(to: pt(ex + w, ey + 1), control: pt(ex, ey - 2.6))
            ctx.stroke(p, with: .color(eyeInk), style: arc)
        case .sleepy, .yawn:
            p.move(to: pt(ex - w, ey - 0.6))
            p.addQuadCurve(to: pt(ex + w, ey - 0.6), control: pt(ex, ey + 2.4))
            ctx.stroke(p, with: .color(eyeInk), style: arc)
        case .open:
            ctx.fill(ellipse(ex, ey, 2.2 * near(s), 2.7), with: .color(eyeInk))
            ctx.fill(ellipse(ex + 0.75 * near(s), ey - 1, 0.85, 0.85), with: .color(.white))
            ctx.fill(ellipse(ex - 0.8, ey + 1.1, 0.4, 0.4), with: .color(.white.opacity(0.8)))
        case .sad:
            // Eyes looking down, little worried brows.
            ctx.fill(ellipse(ex, ey + 1, 1.8 * near(s), 2.1), with: .color(eyeInk))
            ctx.fill(ellipse(ex + 0.5, ey + 0.2, 0.6, 0.6), with: .color(.white))
            var brow = Path()
            // Inner ends raised: worried, not cross.
            brow.move(to: pt(ex - 2 * s, ey - 4.9))
            brow.addLine(to: pt(ex + 1.8 * s, ey - 3.7))
            ctx.stroke(brow, with: .color(eyeInk.opacity(0.7)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }
    let nx = fx(0)
    var nose = Path()
    nose.move(to: pt(nx - 1.6, 4.6))
    nose.addQuadCurve(to: pt(nx + 1.6, 4.6), control: pt(nx, 4.1))
    nose.addQuadCurve(to: pt(nx, 6.1), control: pt(nx + 1.1, 5.7))
    nose.addQuadCurve(to: pt(nx - 1.6, 4.6), control: pt(nx - 1.1, 5.7))
    ctx.fill(nose, with: .color(Color(red: 0.93, green: 0.55, blue: 0.62)))
    let whisker = StrokeStyle(lineWidth: 0.7, lineCap: .round)
    for s: CGFloat in [-1, 1] {
        let len = 5 * near(s) * near(s)
        for (y0, y1) in [(3.6, 2.4), (5.4, 5.6), (7.2, 8.6)] as [(CGFloat, CGFloat)] {
            var w = Path()
            let x0 = fx(13.6 * s)
            w.move(to: pt(x0, y0))
            w.addLine(to: pt(x0 + len * s, y1))
            ctx.stroke(w, with: .color(mouthInk.opacity(0.45)), style: whisker)
        }
    }
    let ink = StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
    switch f {
    case .yawn(let open) where open > 0.05:
        let mouth = ellipse(nx, 8.4 + 1.4 * open, 2.2 + 0.8 * open, 1.0 + 2.4 * open)
        ctx.fill(mouth, with: .color(Color(red: 0.55, green: 0.28, blue: 0.32)))
        ctx.fill(ellipse(nx, 9.4 + 2.6 * open, 1.4 + 0.5 * open, 0.8 + 0.7 * open), with: .color(Color(red: 0.95, green: 0.60, blue: 0.66)))
    case .sad:
        var mouth = Path()
        mouth.move(to: pt(nx - 2, 8.4))
        mouth.addQuadCurve(to: pt(nx + 2, 8.4), control: pt(nx, 6.9))
        ctx.stroke(mouth, with: .color(mouthInk), style: ink)
    default:
        var mouth = Path()
        mouth.move(to: pt(nx - 2.6, 6.8))
        mouth.addQuadCurve(to: pt(nx, 6.4), control: pt(nx - 1.4, 8.6))
        mouth.addQuadCurve(to: pt(nx + 2.6, 6.8), control: pt(nx + 1.4, 8.6))
        ctx.stroke(mouth, with: .color(mouthInk), style: ink)
    }
}

// MARK: Cat
// A squishy clay loaf: head and body are one rounded blob (no neck), small rounded ears, short chunky tapered
// legs with bean paws, a thick tail curling up behind one side.

/// Triangle with rounded corners (ears).
private func roundedTriangle(_ a: CGPoint, _ tip: CGPoint, _ b: CGPoint, radius: CGFloat) -> Path {
    var p = Path()
    p.addLines([a, tip, b])
    p.closeSubpath()
    return p.union(p.strokedPath(StrokeStyle(lineWidth: radius * 2, lineJoin: .round)))
}

/// One ear as (outer shape, faint pink inner) from its base corners and tip.
private func catEar(_ a: CGPoint, _ tip: CGPoint, _ b: CGPoint) -> (Path, Path) {
    let c = pt((a.x + tip.x + b.x) / 3, (a.y + tip.y + b.y) / 3 + 1)
    func toward(_ p: CGPoint, _ k: CGFloat) -> CGPoint { pt(c.x + (p.x - c.x) * k, c.y + (p.y - c.y) * k) }
    return (roundedTriangle(a, tip, b, radius: 1.8),
            roundedTriangle(toward(a, 0.45), toward(tip, 0.55), toward(b, 0.45), radius: 1.2))
}

/// Chunky leg: wide where it leaves the body (`hip`, buried in it), narrowing to `foot`, ending in a bean paw a
/// little wider than the leg. `dir` = the way the toes point (+1 right). Paw bottom ≈ `foot.y + 3`.
private func catLeg(_ hip: CGPoint, _ foot: CGPoint, dir: CGFloat = 1, hipWidth: CGFloat = 8.5,
                    footWidth: CGFloat = 5.8) -> Path {
    let dx = foot.x - hip.x, dy = foot.y - hip.y, len = max(0.01, hypot(dx, dy))
    let nx = -dy / len, ny = dx / len
    var shaft = Path()
    shaft.addLines([pt(hip.x + nx * hipWidth / 2, hip.y + ny * hipWidth / 2),
                    pt(foot.x + nx * footWidth / 2, foot.y + ny * footWidth / 2),
                    pt(foot.x - nx * footWidth / 2, foot.y - ny * footWidth / 2),
                    pt(hip.x - nx * hipWidth / 2, hip.y - ny * hipWidth / 2)])
    shaft.closeSubpath()
    return shaft.union(ellipse(hip.x, hip.y, hipWidth / 2, hipWidth / 2))
        .union(ellipse(foot.x + dir * 1, foot.y + 0.3, 3.9, 2.7))
}

/// Pink toe beans on a visible sole.
private func toeBeans(_ ctx: GraphicsContext, at c: CGPoint) {
    let bean = Clay.pink.base.opacity(0.8)
    ctx.fill(ellipse(c.x, c.y + 0.4, 1.3, 1), with: .color(bean))
    for dx: CGFloat in [-1.5, 0, 1.5] { ctx.fill(ellipse(c.x + dx, c.y - 1.2, 0.5, 0.5), with: .color(bean)) }
}

/// The clay blob with its ears and `attached` legs (one shape, no seams), then pink inner ears, a sheen and the
/// face. `body`, `ears`, `faceAt`, `sheen` are in blob-local coordinates mapped by `local`; `attached` is not.
private func catBlob(_ ctx: GraphicsContext, local: CGAffineTransform = .identity, body: [Path],
                     ears: [(CGPoint, CGPoint, CGPoint)], attached: [Path] = [], faceAt: CGPoint,
                     faceScale: CGFloat = 1, face f: Face, turn: CGFloat = 0, sheen: CGPoint) {
    let shapes = ears.map { catEar($0.0, $0.1, $0.2) }
    clay(ctx, (body + shapes.map(\.0)).map { $0.applying(local) } + attached, .cream)
    for (_, inner) in shapes { ctx.fill(inner.applying(local), with: .color(Clay.pink.base.opacity(0.55))) }
    let s = sheen.applying(local)
    glow(ctx, ellipse(s.x, s.y, 6, 3.4), .white.opacity(0.6), blur: 2)
    var fc = ctx
    fc.concatenate(local)
    fc.translateBy(x: faceAt.x, y: faceAt.y)
    fc.scaleBy(x: faceScale, y: faceScale)
    face(fc, f, turn: turn)
}

/// Thick clay tail along `build`'s spine.
private func catTail(_ ctx: GraphicsContext, width: CGFloat = 6.5, _ build: (inout Path) -> Void) {
    var spine = Path()
    build(&spine)
    clay(ctx, [spine.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))], .cream)
}

/// Rounded bean paw resting in front of the body.
private func beanPaw(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ c: Clay = .cream) {
    clay(ctx, [ellipse(x, y, 4.4, 3.1)], c, lift: true)
    for dx: CGFloat in [-1.3, 1.3] {
        var toe = Path()
        toe.move(to: pt(x + dx, y - 0.4))
        toe.addLine(to: pt(x + dx, y + 1.3))
        ctx.stroke(toe, with: .color(c.shade.opacity(0.6)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
    }
}

/// Sitting loaf (front view): tucked haunches with back feet at the sides, two bean paws under the chest.
/// `dy` lowers it (behind the lip); `squash` flattens it (sniff); `paw` raises the right front paw (0…1 = swipe
/// down); `ears` lifts (+, alert) or droops (−) them; `ball` puts the yarn ball in its mouth.
private func catSitting(_ ctx: GraphicsContext, face f: Face, turn: CGFloat = 0, dy: CGFloat = 0, stretchUp: CGFloat = 0,
                        squash: CGFloat = 0, tailSway: CGFloat = 0, paw raised: Double? = nil, paws: Bool = true,
                        ears lift: CGFloat = 0, ball: Bool = false) {
    let g = PetArt.ground + dy, top = g - 41 - stretchUp + squash
    catTail(ctx) { t in
        t.move(to: pt(40, g - 6))
        t.addQuadCurve(to: pt(51, g - 12), control: pt(52, g - 3))
        t.addQuadCurve(to: pt(50 + tailSway, g - 29), control: pt(57, g - 21))
        t.addQuadCurve(to: pt(45 + tailSway, g - 31), control: pt(48 + tailSway, g - 34))
    }
    // Back feet peek out under the haunches.
    clay(ctx, [ellipse(17.5, g - 2.4, 4.2, 2.6), ellipse(46.5, g - 2.4, 4.2, 2.6)], .creamShadow)
    let wide = squash * 0.5, droop = max(0, -lift)
    let faceY = top + 15 + squash * 0.4
    catBlob(ctx, body: [Path(roundedRect: CGRect(x: 16 - wide, y: top, width: 32 + 2 * wide, height: g - top - 2),
                             cornerRadius: 16, style: .continuous),
                        ellipse(32, g - 10, 16 + wide, 9.5), ellipse(20.5, g - 8.5, 7.5, 7), ellipse(43.5, g - 8.5, 7.5, 7)],
            ears: [(pt(19 - wide, top + 8), pt(20.5 - wide - droop * 1.5, top - 4.5 - lift), pt(28, top + 2)),
                   (pt(45 + wide, top + 8), pt(43.5 + wide + droop * 1.5, top - 4.5 - lift), pt(36, top + 2))],
            faceAt: pt(32, faceY), face: f, turn: turn, sheen: pt(24, top + 7))
    // Haunch curves: soft shading, no line.
    for s: CGFloat in [-1, 1] {
        var arc = Path()
        arc.addArc(center: pt(32 + 11.5 * s, g - 8), radius: 6, startAngle: .degrees(s < 0 ? 200 : -20),
                   endAngle: .degrees(s < 0 ? 300 : 240), clockwise: s > 0)
        glow(ctx, arc.strokedPath(StrokeStyle(lineWidth: 1.4, lineCap: .round)), Clay.cream.shade.opacity(0.35), blur: 0.8)
    }
    glow(ctx, ellipse(32, g - 10, 7, 5), .white.opacity(0.35), blur: 2)
    if ball { drawYarn(ctx, center: pt(32 + 4 * turn, faceY + 11), radius: 4.6, shadow: false) }
    guard paws else { return }
    beanPaw(ctx, 27.5, g - 2.6)
    if let a = raised {
        let foot = pt(50 + 3 * sin(a * .pi), g - 21 + 17 * a)
        clay(ctx, [catLeg(pt(39, g - 12), foot, hipWidth: 8, footWidth: 6)], .cream, lift: true)
        toeBeans(ctx, at: pt(foot.x + 1, foot.y + 0.3))
    } else {
        beanPaw(ctx, 36.5, g - 2.6)
    }
}

/// One leg of a side-view cat in body-local coordinates: hip, foot, near (true) or far side.
private typealias SideLeg = (hip: CGPoint, foot: CGPoint, near: Bool)

/// Side-view loaf facing right, centred at `center`, tilted by `tilt`, squashed by `squash` (crouch). Far legs sit
/// behind and a shade darker; near legs are part of the body shape. The head looks where it walks (`turn`).
private func catSide(_ ctx: GraphicsContext, center: CGPoint, tilt: Double = 0, squash: CGFloat = 1, face f: Face,
                     turn: CGFloat = 1, legs: [SideLeg], ball: Bool = false, tail: (inout Path) -> Void) {
    let local = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: tilt * .pi / 180)
        .scaledBy(x: 1 + (1 - squash) * 0.3, y: squash)
    clay(ctx, legs.filter { !$0.near }.map { catLeg($0.hip, $0.foot, hipWidth: 8, footWidth: 5.4).applying(local) },
         .creamShadow)
    catTail(ctx, tail)
    catBlob(ctx, local: local,
            body: [Path(roundedRect: CGRect(x: -21, y: -12.5, width: 42, height: 25), cornerRadius: 12.5, style: .continuous),
                   ellipse(9, -3, 13, 13)],
            ears: [(pt(1.5, -11.5), pt(3.5, -21.5), pt(10, -14.5)), (pt(20.5, -9.5), pt(17.5, -20.5), pt(12.5, -14.5))],
            attached: legs.filter(\.near).map { catLeg($0.hip, $0.foot).applying(local) },
            faceAt: pt(10, -2), faceScale: 0.88, face: f, turn: turn, sheen: pt(-6, -8))
    if ball { drawYarn(ctx, center: pt(10 + 4 * turn, 8.5).applying(local), radius: 4.6, shadow: false) }
}

private func drawCat(_ ctx: GraphicsContext, _ fr: PetFrame) {
    let g = PetArt.ground
    let step = fr.step, progress = fr.progress, turn = CGFloat(fr.turn)
    var behindLip = ctx
    behindLip.clip(to: Path(CGRect(x: -20, y: -20, width: PetArt.size.width + 40, height: g + 20)))
    switch fr.pose {
    case .sit, .look, .perk, .sad:
        contactShadow(ctx, x: 32, halfWidth: 20)
        let f: Face = fr.pose == .sit ? .happy : fr.pose == .sad ? .sad : .open
        catSitting(ctx, face: f, turn: turn, tailSway: step % 2 == 0 ? 0 : 1.5,
                   ears: fr.pose == .perk ? 2.5 : fr.pose == .sad ? -3 : 0)

    case .purr:
        contactShadow(ctx, x: 32, halfWidth: 20)
        var c = ctx
        // Leans in, swaying from the bottom.
        c.translateBy(x: 32, y: g)
        c.rotate(by: .degrees(step % 2 == 0 ? -4 : 3))
        c.translateBy(x: -32, y: -g)
        catSitting(c, face: .happy, tailSway: step % 2 == 0 ? 0 : 1.5)
        let rise = CGFloat(progress) * 5
        heart(ctx, at: pt(54, 14 - rise), size: 9)
        heart(ctx, at: pt(60, 6 - rise), size: 6)

    case .sniff:
        contactShadow(ctx, x: 32, halfWidth: 21)
        catSitting(ctx, face: .sleepy, squash: 5 + (step % 2 == 0 ? 0 : 0.6))
        for i in 0..<2 {
            ctx.stroke(ellipse(25 + CGFloat(i) * 14, g - 4, 1.4, 1), with: .color(Clay.cream.shade.opacity(0.6)), lineWidth: 0.7)
        }

    case .yawn:
        let open = CGFloat(sin(progress * .pi))
        contactShadow(ctx, x: 32, halfWidth: 20)
        catSitting(ctx, face: .yawn(open), stretchUp: 1.5 * open)

    case .bat:
        contactShadow(ctx, x: 33, halfWidth: 21)
        catSitting(ctx, face: .open, turn: 0.3, paw: progress)

    case .walk, .run, .carry:
        // Trot: diagonal pairs (near front + far rear, far front + near rear) swing together; the pair passing
        // forward lifts. Run: longer reach, more bounce.
        let running = fr.pose == .run
        let f = step % 4
        let reach: CGFloat = running ? 5.5 : 3.5
        let a = [reach, 0, -reach, 0][f], b = -a
        let lift: CGFloat = running ? 3.2 : 2.2
        let liftA: CGFloat = f == 3 ? lift : 0, liftB: CGFloat = f == 1 ? lift : 0
        let bob: CGFloat = (f % 2 == 0 ? 0.8 : -0.8) * (running ? 1.8 : 1)
        let groundY = 20 - bob - 3
        contactShadow(ctx, x: 31, halfWidth: 20)
        catSide(ctx, center: pt(31, g - 20 + bob), tilt: running ? -3 : 0, face: .open, turn: turn, legs: [
            (pt(14, 8), pt(14 + b + 1, groundY - liftB), false),
            (pt(-10, 8), pt(-10 + a + 1, groundY - liftA), false),
            (pt(11, 8), pt(11 + a, groundY - liftA), true),
            (pt(-13, 8), pt(-13 + b, groundY - liftB), true),
        ], ball: fr.pose == .carry) { t in
            let sway: CGFloat = [0, 1, 0, -1][f]
            if running {
                t.move(to: pt(12, g - 20 + bob))
                t.addQuadCurve(to: pt(1, g - 28 + sway), control: pt(5, g - 21))
                t.addQuadCurve(to: pt(2, g - 34 + sway), control: pt(-1, g - 32))
            } else {
                t.move(to: pt(13, g - 18 + bob))
                t.addQuadCurve(to: pt(6 + sway, g - 31), control: pt(3, g - 20))
                t.addQuadCurve(to: pt(12 + sway * 1.5, g - 38), control: pt(6 + sway, g - 38))
            }
        }

    case .crouch:
        // Low and ready: butt wiggles, tail tip flicks.
        let w = step % 2 == 0 ? 0.0 : 1.0
        contactShadow(ctx, x: 32, halfWidth: 22)
        catSide(ctx, center: pt(32, g - 15), tilt: 5 + 2 * w, squash: 0.84, face: .open, turn: turn, legs: [
            (pt(13, 7), pt(17, 14), false), (pt(-12, 6), pt(-10, 15), false),
            (pt(10, 7), pt(14, 15), true), (pt(-15, 6), pt(-13, 15.5), true),
        ]) { t in
            let flick = CGFloat(w) * 3
            t.move(to: pt(14, g - 18))
            t.addQuadCurve(to: pt(5, g - 22), control: pt(9, g - 17))
            t.addQuadCurve(to: pt(1 - flick, g - 29 + flick), control: pt(1, g - 24))
        }

    case .pounce:
        // Stretch arc: front paws reach forward and down, back legs push off behind.
        let lift = CGFloat(sin(progress * .pi)) * 9
        contactShadow(ctx, x: 32, halfWidth: 20 - lift * 0.7, strength: 1 - Double(lift) / 18)
        catSide(ctx, center: pt(32, g - 21 - lift), tilt: -8, face: .open, turn: turn, legs: [
            (pt(14, 6), pt(24, 13), false), (pt(-10, 6), pt(-21, 14), false),
            (pt(11, 7), pt(21, 15), true), (pt(-13, 7), pt(-24, 13), true),
        ]) { t in
            t.move(to: pt(13, g - 20 - lift))
            t.addQuadCurve(to: pt(2, g - 30 - lift), control: pt(5, g - 21 - lift))
            t.addQuadCurve(to: pt(2, g - 37 - lift), control: pt(-1, g - 34 - lift))
        }

    case .stretch:
        // Play bow: front legs flat forward with paws on the floor, rear up, tail high.
        let k = CGFloat(sin(min(1, progress * 1.4) * .pi / 2))
        contactShadow(ctx, x: 34, halfWidth: 23)
        let local = CGAffineTransform(translationX: 30, y: g - 16).rotated(by: Double(12 + 6 * k) * .pi / 180)
        clay(ctx, [catLeg(pt(36, g - 8), pt(51 + 3 * k, g - 3.2), hipWidth: 8, footWidth: 5.4),
                   catLeg(pt(20, g - 14), pt(18, g - 3.2), hipWidth: 8, footWidth: 5.4)], .creamShadow)
        catTail(ctx) { t in
            t.move(to: pt(12, g - 24))
            t.addQuadCurve(to: pt(8, g - 40), control: pt(3, g - 30))
            t.addQuadCurve(to: pt(14, g - 46), control: pt(9, g - 46))
        }
        catBlob(ctx, local: local,
                body: [Path(roundedRect: CGRect(x: -19, y: -9, width: 34, height: 18), cornerRadius: 9, style: .continuous),
                       ellipse(11, 1, 12.5, 11.5)],
                ears: [(pt(3.5, -7.5), pt(4.5, -16.5), pt(11, -10.5)), (pt(20.5, -5.5), pt(18.5, -15.5), pt(14.5, -10.5))],
                attached: [catLeg(pt(40, g - 7), pt(56 + 3 * k, g - 3.2)), catLeg(pt(16, g - 15), pt(14, g - 3.2))],
                faceAt: pt(12, 2), faceScale: 0.84, face: .sleepy, turn: 0.5, sheen: pt(-8, -4))

    case .backRoll:
        // On its back, all four paws up hugging the yarn ball, rocking.
        let rock = sin(progress * 4 * .pi) * 7
        contactShadow(ctx, x: 33, halfWidth: 22)
        var c = ctx
        c.translateBy(x: 32, y: g - 4)
        c.rotate(by: .degrees(rock))
        c.translateBy(x: -32, y: -(g - 4))
        catTail(c) { t in
            t.move(to: pt(48, g - 5))
            t.addQuadCurve(to: pt(58, g - 10), control: pt(56, g - 3))
            t.addQuadCurve(to: pt(55, g - 19), control: pt(61, g - 16))
        }
        clay(c, [catLeg(pt(44, g - 13), pt(48, g - 25), hipWidth: 7.5, footWidth: 5.2)], .creamShadow)
        catBlob(c, body: [Path(roundedRect: CGRect(x: 14, y: g - 18, width: 38, height: 17), cornerRadius: 8.5, style: .continuous),
                          ellipse(19, g - 14, 12.5, 12)],
                ears: [(pt(8, g - 22), pt(2.5, g - 30), pt(14, g - 25.5)), (pt(7, g - 10), pt(0, g - 11), pt(7.5, g - 16))],
                attached: [catLeg(pt(39, g - 13), pt(40, g - 26), hipWidth: 7.5, footWidth: 5.4)],
                faceAt: pt(20, g - 14), faceScale: 0.84, face: .happy, sheen: pt(30, g - 15))
        glow(c, ellipse(36, g - 11, 9, 4), .white.opacity(0.45), blur: 1.6)
        drawYarn(c, center: pt(31, g - 30), radius: 6, spin: progress * 6, shadow: false)
        clay(c, [catLeg(pt(26, g - 15), pt(26, g - 27), hipWidth: 7.5, footWidth: 5.4),
                 catLeg(pt(34, g - 15), pt(35.5, g - 28), hipWidth: 7.5, footWidth: 5.4)], .cream, lift: true)
        toeBeans(c, at: pt(26.5, g - 28.5))
        toeBeans(c, at: pt(36, g - 29.5))

    case .sleep:
        // Flattened mochi loaf, eyes closed, tail wrapped in front.
        let breath: CGFloat = step % 2 == 0 ? 0 : 0.7
        contactShadow(ctx, x: 33, halfWidth: 23)
        catBlob(ctx, body: [Path(roundedRect: CGRect(x: 12, y: g - 21 - breath, width: 42, height: 21 + breath),
                                 cornerRadius: 10.5, style: .continuous)],
                ears: [(pt(14, g - 15), pt(14.5, g - 27), pt(22, g - 20)), (pt(33, g - 17), pt(30, g - 28), pt(25, g - 21))],
                faceAt: pt(23, g - 10.5), faceScale: 0.8, face: .sleepy, sheen: pt(30, g - 17))
        catTail(ctx, width: 6) { t in
            t.move(to: pt(53, g - 5))
            t.addQuadCurve(to: pt(38, g - 1.6), control: pt(51, g - 0.5))
            t.addQuadCurve(to: pt(30, g - 3), control: pt(33, g - 1.6))
        }
        let z = step % 2
        for (i, (p, size)) in [(pt(42, g - 26), 8.0), (pt(50, g - 36), 10.5)].enumerated() {
            ctx.draw(Text("z").font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Clay.caramel.shade.opacity(i == z ? 0.95 : 0.5)), at: pt(p.x, p.y - CGFloat(z)))
        }

    case .hide:
        // Ducked behind the front lip: only the ear tips show.
        catSitting(behindLip, face: .open, dy: 39.5 * CGFloat(progress), paws: false)

    case .peek:
        // Pops up from behind the lip: peeks with paws over it, then climbs up.
        let p = CGFloat(progress)
        let dy = p < 0.45 ? 39.5 - 23.5 * (p / 0.45) : 16 * (1 - (p - 0.45) / 0.55)
        if p > 0.45 { contactShadow(ctx, x: 32, halfWidth: 20, strength: Double((p - 0.45) / 0.55)) }
        catSitting(behindLip, face: .open, dy: dy, paws: false)
        if p > 0.3 && p < 0.8 {
            beanPaw(ctx, 23, g + 0.8)
            beanPaw(ctx, 41, g + 0.8)
        }
    }
}

// MARK: Toys

/// Clay yarn ball (`center` = its middle) with a loose thread; `spin` rotates the wound strands as it rolls.
func drawYarn(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat = 7, spin: Double = 0, shadow: Bool = true) {
    if shadow { glow(ctx, ellipse(c.x, c.y + r + 0.4, r * 0.9, 1.6), shadowInk.opacity(0.3), blur: 1.2) }
    var thread = Path()
    thread.move(to: pt(c.x - r * 0.7, c.y + r * 0.7))
    thread.addQuadCurve(to: pt(c.x - r * 1.8, c.y + r * 0.95), control: pt(c.x - r * 1.2, c.y + r * 1.35))
    ctx.stroke(thread, with: .color(Clay.yarn.shade), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    let ball = ellipse(c.x, c.y, r, r)
    clay(ctx, [ball], .yarn)
    var inner = ctx
    inner.clip(to: ball)
    inner.translateBy(x: c.x, y: c.y)
    inner.rotate(by: .radians(spin))
    let strand = StrokeStyle(lineWidth: max(0.8, r * 0.14), lineCap: .round)
    for i in 0..<3 {
        var a = Path()
        let o = CGFloat(i - 1) * r * 0.55
        a.move(to: pt(-r, o - r * 0.5))
        a.addQuadCurve(to: pt(r, o + r * 0.5), control: pt(0, o - r * 0.2))
        inner.stroke(a, with: .color(Clay.yarn.light.opacity(0.9)), style: strand)
    }
    var cross = Path()
    cross.move(to: pt(-r * 0.4, -r))
    cross.addQuadCurve(to: pt(r * 0.3, r), control: pt(r * 0.5, 0))
    inner.stroke(cross, with: .color(Clay.yarn.light.opacity(0.9)), style: strand)
    glow(ctx, ellipse(c.x - r * 0.35, c.y - r * 0.4, r * 0.35, r * 0.22), .white.opacity(0.6), blur: 0.8)
}

/// The pet as a view; `facingRight == false` mirrors the whole pet.
struct PetSprite: View {
    var species = PetSpecies.cat
    var frame: PetFrame
    var facingRight = true

    var body: some View {
        Canvas { ctx, _ in PetArt.draw(ctx, species: species, frame: frame) }
            .frame(width: PetArt.size.width, height: PetArt.size.height)
            .scaleEffect(x: facingRight ? 1 : -1, y: 1)
    }
}

/// The yarn ball as a view, centred in a 22 pt square.
struct YarnView: View {
    var spin = 0.0
    var body: some View {
        Canvas { ctx, size in drawYarn(ctx, center: CGPoint(x: size.width / 2, y: size.height / 2 - 1), spin: spin) }
            .frame(width: 22, height: 22)
    }
}
