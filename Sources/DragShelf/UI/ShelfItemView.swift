import AppKit
import SwiftUI

/// One shelf tile: 64 pt thumbnail + 2-line caption. A missing file is dimmed with a "Missing" line.
struct ShelfItemView: View {
    let item: ShelfItem
    var isSelected = false
    var isMissing = false
    var onRemove: () -> Void = {}
    var onQuickLook: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
                .frame(width: 64, height: 64)
                .opacity(isMissing ? 0.4 : 1)
            VStack(spacing: 1) {
                Text(name)
                    .font(.caption)
                    .lineLimit(isMissing ? 1 : 2, reservesSpace: !isMissing)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isMissing ? .secondary : .primary)
                if isMissing {
                    Label("Missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear,
                    in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMissing ? "\(typeDescription), \(name), missing" : "\(typeDescription), \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Remove", onRemove)
        .accessibilityAction(named: "Quick Look", onQuickLook)
    }

    @ViewBuilder private var thumbnail: some View {
        switch item.kind {
        case .file(let url):
            FileThumbnail(url: url)
        case .url:
            symbol("link")
        case .text:
            symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
            .frame(width: 56, height: 56)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var name: String {
        switch item.kind {
        case .file(let url): url.lastPathComponent
        // Zero-width spaces let long hosts wrap at dots instead of hyphenating.
        case .url(let url): (url.host(percentEncoded: false) ?? url.absoluteString)
            .replacingOccurrences(of: ".", with: ".\u{200B}")
        case .text(let text):
            text.split(whereSeparator: \.isNewline)
                .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        }
    }

    private var typeDescription: String {
        switch item.kind {
        case .file(let url):
            (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "File"
        case .url: "Link"
        case .text: "Text"
        }
    }
}
