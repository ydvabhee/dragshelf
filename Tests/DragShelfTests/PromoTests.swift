import Foundation
import Testing
@testable import DragShelf

// MARK: PromoFeed (AC-1..AC-3)

/// Copy of backend/promos.json (AC-1).
private let backendJSON = """
{
  "version": 1,
  "promos": [
    {
      "id": "example-app",
      "title": "ExampleApp: a tiny tool for your Mac",
      "subtitle": "Free on the Mac App Store",
      "url": "https://example.com/exampleapp",
      "symbol": "sparkles",
      "minAppVersion": "0.1",
      "excludeBundleIds": ["com.abhishekyadav.ExampleApp"]
    },
    {
      "id": "launch-week",
      "title": "AnotherApp is out: launch week discount",
      "url": "https://example.com/anotherapp",
      "startsAt": "2026-11-01T00:00:00Z",
      "endsAt": "2026-11-08T00:00:00Z",
      "excludeBundleIds": ["com.abhishekyadav.AnotherApp"]
    }
  ]
}
"""

private nonisolated func feed(_ entries: [[String: Any]], version: Int = 1) -> Data {
    try! JSONSerialization.data(withJSONObject: ["version": version, "promos": entries])
}

private nonisolated func entry(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["id": id, "title": "App \(id)", "url": "https://example.com/\(id)"].merging(extra) { $1 }
}

@Test func backendFeedDecodes() throws {
    let f = try #require(PromoFeed.decode(Data(backendJSON.utf8)))
    #expect(f.promos.map(\.id) == ["example-app", "launch-week"])
    #expect(f.promos[0].symbol == "sparkles")
    #expect(f.promos[0].minAppVersion == [0, 1, 0])
    #expect(f.promos[1].startsAt == Date(timeIntervalSince1970: 1_793_491_200))
}

@Test(arguments: [
    ["url": "http://example.com/x"],
    ["url": "file:///etc/passwd"],
    ["url": "javascript:alert(1)"],
    ["url": "dragshelf://x"],
    ["url": "https://evil.com/x"],
    ["url": "https://example.com.evil.com/x"],
    ["url": "https://user:pw@example.com/x"],
    ["url": "https://example.com:8443/x"],
    ["url": "https://example.com/" + String(repeating: "a", count: 2048)],
    ["title": String(repeating: "t", count: 61)],
    ["title": ""],
    ["title": "Two\nlines"],
    ["title": "Evil \u{202E}gpj.exe"],
    ["title": "Z" + String(repeating: "\u{0301}", count: 130)],
    ["subtitle": String(repeating: "s", count: 81)],
    ["subtitle": "tab\there"],
    ["id": "Bad_ID"],
    ["id": String(repeating: "a", count: 41)],
    ["id": 7],
    ["minAppVersion": "1"],
    ["maxAppVersion": "1.2.3.4"],
    ["minAppVersion": "v1.0"],
    ["startsAt": "tomorrow"],
    ["excludeBundleIds": Array(repeating: "a", count: 21)],
] as [[String: any Sendable]])
func invalidEntryDroppedNeighborsKept(bad: [String: any Sendable]) throws {
    let f = try #require(PromoFeed.decode(feed([entry("a"), entry("bad", bad), entry("c")])))
    #expect(f.promos.map(\.id) == ["a", "c"])
}

@Test func wholeFeedRejected() {
    #expect(PromoFeed.decode(feed([entry("a")], version: 2)) == nil)
    #expect(PromoFeed.decode(Data("not json".utf8)) == nil)
    let pad = String(repeating: "x", count: PromoConfig.maxBytes)
    #expect(PromoFeed.decode(feed([entry("a", ["pad": pad])])) == nil)
}

@Test func feedLimitsAndLenientFields() throws {
    let many = (0..<25).map { entry("p\($0)") } + [entry("p0")]
    let f = try #require(PromoFeed.decode(feed(many)))
    #expect(f.promos.count == 20)
    let g = try #require(PromoFeed.decode(feed([entry("a", ["symbol": "no.such.symbol.xyz", "unknown": 1])])))
    #expect(g.promos.first?.symbol == nil)
}

@Test func eligibleWindowsAndExclusions() throws {
    let f = try #require(PromoFeed.decode(feed([
        entry("min", ["minAppVersion": "1.2"]),
        entry("max", ["maxAppVersion": "1.1.9"]),
        entry("dated", ["startsAt": "2026-01-01T00:00:00Z", "endsAt": "2026-02-01T00:00:00Z"]),
        entry("self", ["excludeBundleIds": ["com.abhishekyadav.DragShelf"]]),
        entry("plain"),
    ])))
    let iso = { (s: String) in try! Date(s, strategy: .iso8601) }
    func ids(_ now: String, _ v: String, dismissed: Set<String> = []) -> [String] {
        f.eligible(now: iso(now), appVersion: v, bundleID: "com.abhishekyadav.DragShelf", dismissed: dismissed).map(\.id)
    }
    #expect(ids("2026-01-15T00:00:00Z", "1.2") == ["dated", "min", "plain"])
    #expect(ids("2026-01-15T00:00:00Z", "1.1.9") == ["dated", "max", "plain"])
    #expect(ids("2025-12-31T23:59:59Z", "1.10") == ["min", "plain"])
    #expect(ids("2026-02-01T00:00:00Z", "1.2.0") == ["min", "plain"]) // endsAt exclusive
    #expect(ids("2026-01-15T00:00:00Z", "garbage") == ["dated", "plain"])
    #expect(ids("2026-01-15T00:00:00Z", "1.2", dismissed: ["plain"]) == ["dated", "min"])
}

@Test func pickStableWithinDayRotatesNextDay() throws {
    let f = try #require(PromoFeed.decode(feed([entry("a"), entry("b"), entry("c")])))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let morning = try Date("2026-10-20T00:30:00Z", strategy: .iso8601)
    let p1 = PromoFeed.pick(from: f.promos, now: morning, calendar: cal)
    #expect(PromoFeed.pick(from: f.promos, now: morning.addingTimeInterval(23 * 3600), calendar: cal) == p1)
    let p2 = PromoFeed.pick(from: f.promos, now: morning.addingTimeInterval(24 * 3600), calendar: cal)
    #expect(p2 != nil && p2 != p1)
    #expect(PromoFeed.pick(from: [], now: morning, calendar: cal) == nil)
}

// MARK: PromoLoader (AC-4, AC-5): stub URLProtocol, never the network

nonisolated final class StubProtocol: URLProtocol {
    struct Reply {
        var status = 200; var headers: [String: String] = [:]; var body = Data(); var redirect: URL?; var error: URLError.Code?
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _reply = Reply()
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static var reply: Reply {
        get { lock.withLock { _reply } }
        set { lock.withLock { _reply = newValue } }
    }
    static var requests: [URLRequest] { lock.withLock { _requests } }
    static func reset() { lock.withLock { _reply = Reply(); _requests = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self._requests.append(request) }
        let r = Self.reply
        if let code = r.error { return client!.urlProtocol(self, didFailWithError: URLError(code)) }
        if let to = r.redirect, request.url != to {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": to.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: resp)
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: nil, headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct PromoLoaderTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = TestDefaults.make("PromoLoaderTests")
    let session: URLSession = {
        let c = PromoLoader.configuration()
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }()
    var cacheURL: URL { dir.appendingPathComponent("feed.json") }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        StubProtocol.reset()
    }

    func loader(at time: Date) -> PromoLoader {
        PromoLoader(session: session, cacheURL: cacheURL, defaults: defaults, now: { time })
    }

    @Test func fetchCachesAndUsesETag() async throws {
        StubProtocol.reply = .init(headers: ["ETag": "\"v1\""], body: feed([entry("a")]))
        let l = loader(at: t0)
        await l.refreshIfStale()
        #expect(l.feed?.promos.map(\.id) == ["a"])
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(defaults.string(forKey: PromoLoader.etagKey) == "\"v1\"")
        let req = try #require(StubProtocol.requests.first)
        #expect(req.value(forHTTPHeaderField: "User-Agent") == "DragShelf/\(PromoLoader.appVersion)")
        #expect(req.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(req.value(forHTTPHeaderField: "Accept-Language") == "en")
        #expect(req.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(req.url == PromoConfig.feedURL)

        // Within 24 h: no request.
        await loader(at: t0.addingTimeInterval(23 * 3600)).refreshIfStale()
        #expect(StubProtocol.requests.count == 1)

        // After 24 h: conditional GET; 304 keeps the cache (fresh loader reads it from disk).
        StubProtocol.reply = .init(status: 304)
        let later = loader(at: t0.addingTimeInterval(25 * 3600))
        #expect(later.feed?.promos.map(\.id) == ["a"])
        await later.refreshIfStale()
        #expect(StubProtocol.requests.count == 2)
        #expect(StubProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(later.feed?.promos.map(\.id) == ["a"])
    }

    @Test(arguments: [
        StubProtocol.Reply(status: 500, body: feed([entry("new")])),
        StubProtocol.Reply(body: Data("garbage".utf8)),
        StubProtocol.Reply(body: feed([entry("new")], version: 2)),
        StubProtocol.Reply(body: feed([entry("new", ["pad": String(repeating: "x", count: 70_000)])])),
        StubProtocol.Reply(redirect: URL(string: "http://example.com/promos.json")!),
        StubProtocol.Reply(redirect: URL(string: "https://evil.com/promos.json")!),
    ])
    func failureKeepsPreviousCache(reply: StubProtocol.Reply) async throws {
        StubProtocol.reply = .init(body: feed([entry("old")]))
        await loader(at: t0).refreshIfStale()
        StubProtocol.reply = reply
        let l = loader(at: t0.addingTimeInterval(25 * 3600))
        await l.refreshIfStale()
        #expect(l.feed?.promos.map(\.id) == ["old"])
        #expect(PromoFeed.decode(try Data(contentsOf: cacheURL))?.promos.map(\.id) == ["old"])
        // Redirect target never loaded.
        #expect(StubProtocol.requests.allSatisfy { $0.url == PromoConfig.feedURL })
    }

    @Test func networkErrorRetriesAfter3hServerErrorAfter24h() async {
        StubProtocol.reply = .init(error: .notConnectedToInternet)
        await loader(at: t0).refreshIfStale()
        await loader(at: t0.addingTimeInterval(2 * 3600)).refreshIfStale()
        #expect(StubProtocol.requests.count == 1)
        StubProtocol.reply = .init(status: 500)
        await loader(at: t0.addingTimeInterval(3 * 3600 + 1)).refreshIfStale()
        #expect(StubProtocol.requests.count == 2)
        await loader(at: t0.addingTimeInterval(23 * 3600)).refreshIfStale()
        #expect(StubProtocol.requests.count == 2)
    }

    @Test func offMakesNoRequest() async {
        defaults.set(false, forKey: Preferences.showPromos)
        StubProtocol.reply = .init(body: feed([entry("a")]))
        await loader(at: t0).refreshIfStale()
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func dismissPersists() {
        loader(at: t0).dismiss("a")
        #expect(loader(at: t0).dismissed == ["a"])
    }
}
