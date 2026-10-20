import AppKit
import SwiftUI

/// One shelf tile: 64 pt thumbnail + 2-line caption.
struct ShelfItemView: View {
    let item: ShelfItem
    var isSelected = false

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
                .frame(width: 64, height: 64)
            Text(name)
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(isSelected ? Color.accentColor.opacity(0.22) : .clear,
                    in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(typeDescription), \(name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
