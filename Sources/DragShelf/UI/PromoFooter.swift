import SwiftUI

/// One quiet line under the grid: optional SF Symbol, title, secondary subtitle, ✕ (ARCHITECTURE §12).
struct PromoFooter: View {
    /// Shared with `HintFooter`: swapping promo ↔ hint never changes the panel height (T-18).
    static let rowHeight: CGFloat = 18, bottomPadding: CGFloat = 10
    let promo: Promo
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { PromoLoader.open(promo) } label: {
                HStack(spacing: 5) {
                    if let symbol = promo.symbol {
                        Image(systemName: symbol).imageScale(.small)
                    }
                    Text(promo.title)
                        .layoutPriority(1)
                    if let subtitle = promo.subtitle {
                        Text(subtitle).foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(promo.url.absoluteString)
            .accessibilityLabel(promo.subtitle.map { "\(promo.title), \($0). Opens in browser" } ?? "\(promo.title). Opens in browser")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Hide this suggestion")
            .accessibilityLabel("Hide this suggestion")
        }
        .frame(height: Self.rowHeight)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, PromoFooter.bottomPadding)
    }
}

/// Contextual tip in the footer slot (T-18): lightbulb, one caption line, ✕ retires it for good.
struct HintFooter: View {
    let hint: HintEngine.Hint
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb").imageScale(.small)
                Text(hint.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(hint.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hint.spokenText)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Dismiss tip")
            .accessibilityLabel("Dismiss tip")
        }
        .frame(height: PromoFooter.rowHeight)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, PromoFooter.bottomPadding)
    }
}

extension HintEngine.Hint {
    /// VoiceOver: "Tip: …" with key symbols spelled out.
    var spokenText: String { Self.spoken(text) }
    /// VoiceOver for the pet's speech bubble (V3-01).
    var spokenBubble: String { Self.spoken(bubbleText) }

    private static func spoken(_ text: String) -> String {
        let shortcut = Preferences.shortcut()
        var words = text.replacingOccurrences(of: shortcut.display, with: shortcut.spoken)
        for key in ["Z", "V", "F"] { words = words.replacingOccurrences(of: "⌘" + key, with: "Command-" + key) }
        words = words.replacingOccurrences(of: "⌘", with: "Command")
            .replacingOccurrences(of: " · ", with: ", ")
        return words.hasPrefix("Tip: ") ? words : "Tip: " + words
    }
}
