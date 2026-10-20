import AppKit
import os

/// Fetches the promo feed at most once per 24 h with ETag, caches the last good copy on disk, fails silently
/// (ARCHITECTURE §12). The feed is untrusted input: every entry goes through `PromoFeed.decode`.
@Observable
final class PromoLoader {
    private(set) var feed: PromoFeed?
    private(set) var dismissed: Set<String>

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var fetching = false

    static let etagKey = "promoETag"
    static let lastFetchKey = "promoLastFetch"
    static let interval: TimeInterval = 24 * 3600
    private static let log = Logger(subsystem: PromoConfig.selfBundleID, category: "promos")

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var userAgent: String { "DragShelf/\(appVersion)" }

    static var defaultCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.abhishekyadav.DragShelf/Promos/feed.json")
    }

    /// No cookies, no cache, no credentials store: the request carries nothing that identifies the user.
    static func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return c
    }

    init(session: URLSession = URLSession(configuration: PromoLoader.configuration()),
         cacheURL: URL = PromoLoader.defaultCacheURL, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.cacheURL = cacheURL
        self.defaults = defaults
        self.now = now
        dismissed = Set(defaults.stringArray(forKey: Preferences.dismissedPromoIDs) ?? [])
        // Offline launch: the last good feed shows right away.
        feed = (try? Data(contentsOf: cacheURL)).flatMap(PromoFeed.decode)
    }

    /// Every eligible promo, dismissed included (menu bar "More Apps").
    var menuPromos: [Promo] {
        feed?.eligible(now: now(), appVersion: Self.appVersion, bundleID: Self.bundleID, dismissed: []) ?? []
    }

    /// Today's footer promo, skipping dismissed ones.
    var footerPromo: Promo? {
        PromoFeed.pick(from: feed?.eligible(now: now(), appVersion: Self.appVersion, bundleID: Self.bundleID,
                                            dismissed: dismissed) ?? [], now: now())
    }

    private static var bundleID: String { Bundle.main.bundleIdentifier ?? PromoConfig.selfBundleID }

    /// ✕: hide this promo in the footer for good.
    func dismiss(_ id: String) {
        dismissed.insert(id)
        defaults.set(dismissed.sorted(), forKey: Preferences.dismissedPromoIDs)
    }

    /// Re-checks the allowlist at click time; opens in the default browser without activating DragShelf.
    static func open(_ promo: Promo) {
        guard PromoConfig.isAllowed(promo.url) else { return }
        NSWorkspace.shared.open(promo.url)
    }

    /// Launch, panel show, and toggle-on. No-op when promos are off, a fetch runs, or the last one is < 24 h old.
    func refreshIfStale() async {
        guard Preferences.promosOn(defaults), !fetching else { return }
        if let last = defaults.object(forKey: Self.lastFetchKey) as? Date, now().timeIntervalSince(last) < Self.interval,
           now() >= last { return }
        fetching = true
        defer { fetching = false }
        // Bumped up front: any failure waits a full day (no retry storm).
        defaults.set(now(), forKey: Self.lastFetchKey)

        var request = URLRequest(url: PromoConfig.feedURL)
        request.httpShouldHandleCookies = false
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if feed != nil, let etag = defaults.string(forKey: Self.etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectGuard.shared)
            guard let http = response as? HTTPURLResponse, PromoConfig.isAllowed(http.url) else { throw Failure.response }
            if http.statusCode == 304 { return }
            guard http.statusCode == 200, http.expectedContentLength <= PromoConfig.maxBytes else { throw Failure.status(http.statusCode) }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > PromoConfig.maxBytes { throw Failure.tooLarge }
            }
            guard let decoded = PromoFeed.decode(data) else { throw Failure.invalid }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            defaults.set(http.value(forHTTPHeaderField: "ETag"), forKey: Self.etagKey)
            feed = decoded
        } catch {
            Self.log.error("Promo feed fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private enum Failure: Error { case response, status(Int), tooLarge, invalid }
}

/// Follows a redirect only to another allowlisted `https` URL; anything else stops the load.
private nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectGuard()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard PromoConfig.isAllowed(request.url) else {
            task.cancel()
            return nil
        }
        return request
    }
}
