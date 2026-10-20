import AppKit

/// Hardcoded feed location and link allowlist (ARCHITECTURE §12, ADR-015).
/// OQ-26: placeholders. Change these two constants before release (T-12).
nonisolated enum PromoConfig {
    static let feedURL = URL(string: "https://example.com/dragshelf/promos.json")!
    static let allowedHosts: Set<String> = ["example.com"]
    static let maxBytes = 64 * 1024
    static let maxEntries = 20
    static let selfBundleID = "com.abhishekyadav.DragShelf"

    /// The only URLs the app fetches from or opens: `https`, host exactly on the allowlist, no credentials.
    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host) && url.port == nil && url.user == nil && url.password == nil
    }
}

nonisolated struct Promo: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let url: URL
    let symbol: String?
    let minAppVersion: [Int]?
    let maxAppVersion: [Int]?
    let startsAt: Date?
    let endsAt: Date?
    let excludeBundleIds: [String]

    /// Validates one untrusted feed entry; nil drops it (ARCHITECTURE §12 field table).
    init?(_ e: PromoFeed.Entry) {
        guard (1...40).contains(e.id.unicodeScalars.count),
              e.id.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }),
              Self.isCleanText(e.title, max: 60), !e.title.isEmpty,
              e.subtitle.map({ Self.isCleanText($0, max: 80) }) ?? true,
              e.url.count <= 2048, let url = URL(string: e.url), PromoConfig.isAllowed(url),
              (e.excludeBundleIds?.count ?? 0) <= 20, e.excludeBundleIds?.allSatisfy({ $0.count <= 255 }) ?? true
        else { return nil }
        let min = e.minAppVersion.map(Self.parseVersion), max = e.maxAppVersion.map(Self.parseVersion)
        let start = e.startsAt.map(Self.parseDate), end = e.endsAt.map(Self.parseDate)
        // Present but unparsable → drop the entry (`.some(nil)`).
        if min == .some(nil) || max == .some(nil) || start == .some(nil) || end == .some(nil) { return nil }
        id = e.id
        title = e.title
        subtitle = e.subtitle?.isEmpty == false ? e.subtitle : nil
        self.url = url
        // A bad symbol is ignored, not the entry.
        symbol = e.symbol.flatMap { $0.count <= 64 && NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil }
        minAppVersion = min ?? nil
        maxAppVersion = max ?? nil
        startsAt = start ?? nil
        endsAt = end ?? nil
        excludeBundleIds = e.excludeBundleIds ?? []
    }

    /// ≤ `max` characters and ≤ 2×`max` scalars (no Zalgo stacks of combining marks), no control/format/
    /// line-separator scalars (blocks `\n` and bidi overrides).
    static func isCleanText(_ s: String, max: Int) -> Bool {
        s.count <= max && s.unicodeScalars.count <= 2 * max && !s.unicodeScalars.contains {
            [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
        }
    }

    /// `MAJOR.MINOR[.PATCH]` → 3 ints; anything else nil.
    static func parseVersion(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        return parts.compactMap { Int($0) } + (parts.count == 2 ? [0] : [])
    }

    static func parseDate(_ s: String) -> Date? {
        try? Date(s, strategy: .iso8601)
    }
}

/// Remote "More apps" feed (US-15). Decoding is lenient per entry: a broken entry is dropped, its neighbors kept.
nonisolated struct PromoFeed: Equatable, Sendable {
    let promos: [Promo]

    /// Raw shape of one entry; every field still untrusted.
    struct Entry: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let url: String
        let symbol: String?
        let minAppVersion: String?
        let maxAppVersion: String?
        let startsAt: String?
        let endsAt: String?
        let excludeBundleIds: [String]?
    }

    private struct FailableEntry: Decodable {
        let entry: Entry?
        init(from decoder: any Decoder) throws { entry = try? Entry(from: decoder) }
    }

    private struct Raw: Decodable {
        let version: Int
        let promos: [FailableEntry]
    }

    /// nil = whole feed rejected (too big, not JSON, `version != 1`); caller keeps its last good cache.
    static func decode(_ data: Data) -> PromoFeed? {
        guard data.count <= PromoConfig.maxBytes,
              let raw = try? JSONDecoder().decode(Raw.self, from: data), raw.version == 1 else { return nil }
        var seen = Set<String>()
        let promos = raw.promos.prefix(PromoConfig.maxEntries)
            .compactMap { $0.entry.flatMap(Promo.init) }
            .filter { seen.insert($0.id).inserted }
        return PromoFeed(promos: promos)
    }

    /// Promos to show now, sorted by id: inside version and date windows, not for this app, not dismissed.
    func eligible(now: Date, appVersion: String, bundleID: String, dismissed: Set<String>) -> [Promo] {
        // Unparsable app version: only promos without a version window qualify.
        let v = Promo.parseVersion(appVersion)
        return promos.filter { p in
            if let min = p.minAppVersion { guard let v, !v.lexicographicallyPrecedes(min) else { return false } }
            if let max = p.maxAppVersion { guard let v, !max.lexicographicallyPrecedes(v) else { return false } }
            if let start = p.startsAt, now < start { return false }
            if let end = p.endsAt, now >= end { return false }
            return !p.excludeBundleIds.contains(bundleID) && !dismissed.contains(p.id)
        }.sorted { $0.id < $1.id }
    }

    /// Daily rotation: same promo all day, next one tomorrow.
    static func pick(from eligible: [Promo], now: Date, calendar: Calendar = .current) -> Promo? {
        guard !eligible.isEmpty, let day = calendar.ordinality(of: .day, in: .era, for: now) else { return nil }
        return eligible[day % eligible.count]
    }
}
