// Renders the DragShelf app icon (1024×1024 PNG) with Core Graphics.
// Usage: scripts/make-icon.sh  (regenerates Resources/AppIcon.icns and Resources/AppIcon.png)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Continuous-corner squircle (superellipse, n = 5), like macOS app icons.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5, steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

// Apple icon grid: 824 pt body centered in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

// Soft shadow under the icon body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.30))
ctx.addPath(shape); ctx.setFillColor(color(0x2F5BEA)); ctx.fillPath()
ctx.restoreGState()

// Background: blue gradient, lighter at the top.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [color(0x6FA8FF), color(0x3D6CF5), color(0x2A3FD6)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Gentle top sheen.
let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                       colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()

// File card dropping into the tray: white, slightly tilted, soft shadow.
ctx.saveGState()
ctx.translateBy(x: 512, y: 560)
ctx.rotate(by: -10 * .pi / 180)
let card = CGRect(x: -125, y: -150, width: 250, height: 310)
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x0A1A6B, 0.35))
ctx.addPath(CGPath(roundedRect: card, cornerWidth: 38, cornerHeight: 38, transform: nil))
ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Content lines on the card.
for (i, w) in [170.0, 170.0, 120.0].enumerated() {
    let y = card.maxY - 78 - CGFloat(i) * 52
    ctx.addPath(CGPath(roundedRect: CGRect(x: card.minX + 40, y: y, width: w, height: 20),
                       cornerWidth: 10, cornerHeight: 10, transform: nil))
}
ctx.setFillColor(color(0x9DB6FF)); ctx.fillPath()
ctx.restoreGState()

// Tray: solid white body with a faint top-to-bottom tint, drawn over the card's lower half
// so the card reads as sinking into it.
let trayRect = CGRect(x: 232, y: 250, width: 560, height: 210)
let trayPath = CGPath(roundedRect: trayRect, cornerWidth: 70, cornerHeight: 70, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x0A1A6B, 0.30))
ctx.addPath(trayPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(trayPath); ctx.clip()
let trayTint = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [color(0xFFFFFF), color(0xE3EBFF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(trayTint, start: CGPoint(x: 512, y: trayRect.maxY), end: CGPoint(x: 512, y: trayRect.minY), options: [])
ctx.restoreGState()
// Down arrow on the tray front.
ctx.saveGState()
ctx.setStrokeColor(color(0x3D6CF5)); ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 512, y: 360)); ctx.addLine(to: CGPoint(x: 512, y: 292))
ctx.move(to: CGPoint(x: 474, y: 328)); ctx.addLine(to: CGPoint(x: 512, y: 290)); ctx.addLine(to: CGPoint(x: 550, y: 328))
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
