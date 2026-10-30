import Testing
import Foundation
import Synchronization
@testable import Sugarglider

@Suite(.defaultsCleanup) @MainActor
struct SugargliderTests {
    /// Pinned to this locale only where a test asserts a formatted string, so the
    /// expectations don't depend on this machine's region.
    static let enUS = Locale(identifier: "en_US")

    static func makeSettings(defaults: UserDefaults? = nil,
                             tokens: any TokenStorage = InMemoryTokenStore()) -> AppSettings {
        AppSettings(defaults: defaults ?? makeDefaults(), tokens: tokens)
    }

    static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: DefaultsCleanup.directory.appending(path: UUID().uuidString).path)!
    }

    /// The largest per-channel difference and how many bytes differ between two raw renders.
    /// Rasterization is reproducible only to ±1 per channel, so equality asserts must allow that.
    static func channelDifference(_ a: Data, _ b: Data) -> (max: Int, differing: Int) {
        guard a.count == b.count else { return (Int.max, Int.max) }
        var max = 0, differing = 0
        for (x, y) in zip(a, b) where x != y {
            max = Swift.max(max, abs(Int(x) - Int(y)))
            differing += 1
        }
        return (max, differing)
    }
}

/// A suite named by a path keeps its plist at that path, so the tests' suites live in a temporary directory
/// that goes once all tests have run. A plainly named suite is a plist in ~/Library/Preferences that no API
/// removes: dropping the domain leaves an empty file, and cfprefsd rewrites a deleted one seconds later.
struct DefaultsCleanup: SuiteTrait, TestScoping {
    static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SugargliderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws {
        defer { try? FileManager.default.removeItem(at: Self.directory) }
        try await function()
    }
}

extension Trait where Self == DefaultsCleanup {
    static var defaultsCleanup: Self { Self() }
}

/// The real Keychain would prompt, because the test binary's signature changes with every build.
@MainActor
final class InMemoryTokenStore: TokenStorage {
    private(set) var stored: String
    var refuseWrites = false

    init(_ stored: String = "") { self.stored = stored }

    func load() -> String { stored }

    func save(_ token: String) -> Bool {
        guard !refuseWrites else { return false }
        stored = token
        return true
    }
}

/// A Nightscout site that answers every request with the same canned response. Each has a host of
/// its own, so tests running side by side never see each other's responses or requests.
final class StubbedSite: Sendable {
    /// Answers for every stubbed site, by host.
    static var session: URLSession { SiteProtocol.session }

    let baseURL: String
    private let host = "\(UUID().uuidString.lowercased()).example"

    /// Path and query of every request, as sent.
    var requests: [String] { SiteProtocol.sites.withLock { $0[host]?.requests ?? [] } }

    /// Delays every answer, so a slow response to a replaced site can be tested.
    /// Set it before the request starts.
    var delay: TimeInterval {
        get { SiteProtocol.sites.withLock { $0[host]?.delay ?? 0 } }
        set { SiteProtocol.sites.withLock { $0[host]?.delay = newValue } }
    }

    init(status: Int = 200, json: String) {
        baseURL = "https://\(host)"
        SiteProtocol.sites.withLock { $0[host] = .init(status: status, body: Data(json.utf8)) }
    }

    deinit { SiteProtocol.sites.withLock { $0[host] = nil } }

    @MainActor func nightscout(token: String = "", baseURL: String? = nil) -> Nightscout {
        Nightscout(baseURL: baseURL ?? self.baseURL, token: token, session: Self.session)
    }

    /// Points `settings` at this site and returns a store that reads from it.
    @MainActor func store(_ settings: AppSettings) -> ReadingStore {
        settings.baseURL = baseURL
        return ReadingStore(settings: settings, session: Self.session)
    }
}

private final class SiteProtocol: URLProtocol {
    struct Site {
        var status: Int
        var body: Data
        var delay: TimeInterval = 0
        var requests: [String] = []
    }

    static let sites = Mutex<[String: Site]>([:])

    /// Set by stopLoading: a request cancelled during the delay window must get no callbacks.
    private let cancelled = Mutex(false)

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SiteProtocol.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(), let site = Self.sites.withLock({ sites in
            let request = url.path(percentEncoded: true) + (url.query(percentEncoded: true).map { "?\($0)" } ?? "")
            sites[host]?.requests.append(request)
            return sites[host]
        }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let answer = { [site, url] in
            guard !self.cancelled.withLock({ $0 }) else { return }
            guard let client = self.client else { return }
            let response = HTTPURLResponse(url: url, statusCode: site.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: site.body)
            client.urlProtocolDidFinishLoading(self)
        }
        if site.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + site.delay, execute: answer)
        } else {
            answer()
        }
    }

    override func stopLoading() {
        cancelled.withLock { $0 = true }
    }
}

/// `ReadingStore` fetches in `Task`s nothing can await, so tests poll for the effect.
@MainActor
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw WaitTimedOut(what: what)
}

/// The wait ended without the state: throw, so the test fails once at the wait
/// instead of running on against a state that never arrived.
struct WaitTimedOut: LocalizedError {
    var what: String
    var errorDescription: String? { "Timed out waiting for \(what)" }
}

/// Rounded the way `Nightscout.entries` rounds its date filter.
func epochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

func reading(_ sgv: Int, direction: Reading.Direction? = .flat, minutesAgo: Double = 0,
             from now: Date = .now) -> Reading {
    Reading(sgv: sgv, direction: direction, date: now.addingTimeInterval(-minutesAgo * 60))
}
