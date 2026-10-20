import SwiftUI

/// One quiet line under the grid: optional SF Symbol, title, secondary subtitle, ✕ (ARCHITECTURE §12).
struct PromoFooter: View {
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
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
