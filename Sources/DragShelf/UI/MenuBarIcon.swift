import AppKit

/// Menu bar glyph matching the app icon: tilted file card dropping into a tray with a down arrow (T-20).
/// Drawn in an 18×18 pt box; black + alpha only, so the system tints it (template).
enum MenuBarIcon {
    static let image = make()

    /// Nonisolated, `@Sendable` handler: AppKit may run the drawing handler on any thread.
    nonisolated static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { @Sendable _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawGlyph(in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DragShelf"
        return image
    }

    /// Reference drawing: `docs/assets/menubar-glyph-prototype.swift`.
    nonisolated static func drawGlyph(in ctx: CGContext) {
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
}
