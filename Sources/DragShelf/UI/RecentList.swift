import SwiftUI

/// Recent drag outs (T-17), newest first, shown in the panel in place of the grid. Click a row to restore it,
/// drag it to drop its items again. In-panel, not an `NSPopover`: a popover window is not non-activating,
/// so a click in it would activate DragShelf (ARCHITECTURE §5 rule 6).
struct RecentList: View {
    let store: ShelfStore
    @State private var hovered: RecentEntry.ID?

    var body: some View {
        // Ages ("just now", "2 min. ago") refresh while the list is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.recent) { row($0, now: context.date) }
                Divider().padding(.vertical, 4)
                Button("Clear Recent") { store.clearRecent() }
                    .buttonStyle(.borderless)
                    .help("Forget recent drags")
                    .padding(.horizontal, 8)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private func row(_ entry: RecentEntry, now: Date) -> some View {
        let present = entry.items.filter(ShelfStore.exists)
        let missing = entry.items.count - present.count
        let title = Self.title(entry.items)
        return HStack(spacing: 8) {
            Image(nsImage: DragOutSource.icon(for: entry.items[0]))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(title).lineLimit(1).truncationMode(.middle)
                    Text(" · \(Self.age(entry.date, now: now))").foregroundStyle(.secondary).fixedSize()
                }
                if missing > 0 {
                    // Same "Missing" style as a tile (T-17 AC-4).
                    Label(present.isEmpty ? "Missing" : "\(missing) missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovered == entry.id ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 8, style: .continuous))
        .opacity(present.isEmpty ? 0.4 : 1)
        .contentShape(.rect)
        // Nothing present: dimmed, no click or drag.
        .overlay {
            if !present.isEmpty {
                DragOutHandle(store: store, onHover: { inside in
                    if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
                }, recentItems: present, onClick: { store.restore(entry.id) })
                .help("Restore to DragShelf")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Self.age(entry.date, now: now, style: .full))")
        .accessibilityValue(missing == 0 ? "" : present.isEmpty ? "Missing" : "\(missing) missing")
        .accessibilityHint(present.isEmpty ? "The files were moved or deleted" : "Restore to DragShelf, or drag into another app")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.restore(entry.id) }
        .accessibilityAction(named: "Restore") { store.restore(entry.id) }
    }

    /// "photo.heic" for one item, "3 files" when all are files, else "3 items".
    static func title(_ items: [ShelfItem]) -> String {
        if items.count == 1 { return items[0].displayName }
        let allFiles = items.allSatisfy { if case .file = $0.kind { true } else { false } }
        return "\(items.count) \(allFiles ? "files" : "items")"
    }

    /// "just now" under a minute, else the system relative date ("2 min. ago"; `.full` for VoiceOver).
    static func age(_ date: Date, now: Date, style: RelativeDateTimeFormatter.UnitsStyle = .short) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = style
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
