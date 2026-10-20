import AppKit
import SwiftUI

// The only file that checks OS availability for styling (ARCHITECTURE §6).

extension View {
    /// Panel background: Liquid Glass on macOS 26, vibrant material on 14–15, solid with Reduce Transparency.
    func shelfBackground(isTargeted: Bool) -> some View {
        modifier(ShelfBackground(isTargeted: isTargeted))
    }

    /// Header buttons: circular glass on macOS 26, borderless on 14–15.
    @ViewBuilder func shelfButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(.borderless)
        }
    }
}

/// Groups glass buttons so they blend and morph together on macOS 26.
struct ShelfGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

private struct ShelfBackground: ViewModifier {
    let isTargeted: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let glass: Bool = if #available(macOS 26, *) { true } else { false }
        let shape = RoundedRectangle(cornerRadius: glass ? 22 : 16, style: .continuous)
        let tint = Color.accentColor.opacity(0.25)
        styled(content, shape: shape, tint: tint)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func styled(_ content: Content, shape: RoundedRectangle, tint: Color) -> some View {
        if reduceTransparency {
            content.background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .overlay { if isTargeted { shape.fill(tint) } }
            }
        } else if #available(macOS 26, *) {
            content.glassEffect(isTargeted ? .regular.tint(tint) : .regular, in: shape)
        } else {
            content.background {
                VisualEffectBackground(cornerRadius: shape.cornerSize.width)
                    .overlay { if isTargeted { shape.fill(tint) } }
            }
        }
    }
}

/// macOS 14–15 fallback. `state = .active` keeps it vibrant while the panel is not key.
private struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
