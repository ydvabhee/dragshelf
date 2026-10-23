import AppKit

/// Menu bar glyph matching the app icon: tilted file card dropping into a tray with a down arrow.
/// Drawn in an 18×18 pt box; black + alpha only (template).
func drawGlyph(in ctx: CGContext) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))

    // Card: outlined, tilted −10°, its lower part hidden behind the tray.
    ctx.saveGState()
    ctx.translateBy(x: 9, y: 9.6)
    ctx.rotate(by: -10 * .pi / 180)
    let card = CGRect(x: -3.6, y: -4.2, width: 7.2, height: 9.0)
    ctx.setLineWidth(1.5)
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
    ctx.strokePath()
    // Two content lines.
    ctx.setLineWidth(1.2); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: -1.6, y: 2.4)); ctx.addLine(to: CGPoint(x: 1.6, y: 2.4))
    ctx.move(to: CGPoint(x: -1.6, y: 0.4)); ctx.addLine(to: CGPoint(x: 1.0, y: 0.4))
    ctx.strokePath()
    ctx.restoreGState()

    // Tray: solid rounded bar; clear a gap above it so the card reads as going in.
    let tray = CGRect(x: 2.0, y: 1.6, width: 14.0, height: 6.0)
    let trayPath = CGPath(roundedRect: tray, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
    ctx.setBlendMode(.clear)
    ctx.addPath(CGPath(roundedRect: tray.insetBy(dx: -0.9, dy: -0.9), cornerWidth: 3.1, cornerHeight: 3.1, transform: nil))
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.addPath(trayPath); ctx.fillPath()

    // Down arrow knocked out of the tray.
    ctx.setBlendMode(.clear)
    ctx.setLineWidth(1.4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 9, y: 6.3)); ctx.addLine(to: CGPoint(x: 9, y: 3.0))
    ctx.move(to: CGPoint(x: 7.4, y: 4.5)); ctx.addLine(to: CGPoint(x: 9, y: 2.9)); ctx.addLine(to: CGPoint(x: 10.6, y: 4.5))
    ctx.strokePath()
    ctx.setBlendMode(.normal)
}

// Preview: glyph at 1x/2x on light and dark menu-bar colors, plus SF Symbol for comparison.
let scale: CGFloat = 8
let W = 18 * scale * 2 + 40, H = 18 * scale + 20
for (name, bg, fg) in [("light", 0xF2F2F2, 0x000000), ("dark", 0x2A2A2A, 0xFFFFFF)] as [(String, UInt32, UInt32)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    func col(_ h: UInt32) -> CGColor { CGColor(srgbRed: CGFloat(h >> 16 & 255)/255, green: CGFloat(h >> 8 & 255)/255, blue: CGFloat(h & 255)/255, alpha: 1) }
    c.setFillColor(col(bg)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // Big preview of the glyph (as a mask, tinted fg).
    let layer = CGLayer(c, size: CGSize(width: 18*scale, height: 18*scale), auxiliaryInfo: nil)!
    let lc = layer.context!
    lc.scaleBy(x: scale, y: scale); drawGlyph(in: lc)
    c.saveGState()
    c.translateBy(x: 10, y: 10)
    c.setBlendMode(.normal)
    // tint: draw layer then source-in fg
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in drawGlyph(in: NSGraphicsContext.current!.cgContext); return true }
    img.isTemplate = true
    let tinted = NSImage(size: NSSize(width: 18*scale, height: 18*scale), flipped: false) { r in
        img.draw(in: r); NSColor(cgColor: col(fg))!.set(); r.fill(using: .sourceAtop); return true }
    NSGraphicsContext.saveGraphicsState()
    tinted.draw(in: NSRect(x: 10, y: 10, width: 18*scale, height: 18*scale))
    // Actual-size 18 pt and 36 px versions to the right.
    let tiny = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        img.draw(in: r); NSColor(cgColor: col(fg))!.set(); r.fill(using: .sourceAtop); return true }
    tiny.draw(in: NSRect(x: 18*scale + 40, y: H/2 - 9, width: 18, height: 18))
    tiny.draw(in: NSRect(x: 18*scale + 80, y: H/2 - 18, width: 36, height: 36))
    NSGraphicsContext.restoreGraphicsState()
    c.restoreGState()
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "glyph-\(name).png"))
}
print("ok")
