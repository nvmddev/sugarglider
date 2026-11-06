import Testing
import Foundation
@testable import Sugarglider

private let oneReading = #"[{"sgv":100,"direction":"Flat","date":1700000400000}]"#

extension SugargliderTests {
    @Test func fetchWithoutASiteURLIsNotConfigured() async {
        await #expect(throws: NightscoutError.notConfigured) {
            try await Nightscout(baseURL: "", token: "").entries(count: 1)
        }
    }

    @Test func fetchRejectsAnInvalidSiteURL() async {
        await #expect(throws: NightscoutError.badURL) {
            try await Nightscout(baseURL: "http://exa mple.com", token: "").entries(count: 1)
        }
    }

    @Test func fetchDecodesReadingsOldestFirst() async throws {
        let site = StubbedSite(json: """
            [{"sgv":150,"direction":"Flat","date":1700000300000},
             {"sgv":100,"direction":"FortyFiveUp","date":1700000000000}]
            """)

        let readings = try await site.nightscout().entries(count: 10).items
        #expect(readings.map(\.sgv) == [100, 150])
        #expect(readings.first?.direction == .fortyFiveUp)
        #expect(readings.first?.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func fetchSkipsUnusableRowsAndDefaultsAMissingDirection() async throws {
        let site = StubbedSite(json: """
            [{"sgv":100,"direction":"Flat","date":1700000000000},
             {"direction":"Flat","date":1700000100000},
             {"sgv":110,"date":1700000200000},
             {"sgv":"bad","date":1700000300000},
             {"sgv":120,"direction":null,"date":null},
             {}]
            """)

        let readings = try await site.nightscout().entries(count: 10).items
        #expect(readings.map(\.sgv) == [100, 110])
        #expect(readings.last?.direction == nil)
    }

    /// Nightscout keeps Dexcom's error codes below LOW, and one absurd value must not trap.
    @Test func fetchDropsErrorCodesAndValuesOutOfReach() async throws {
        let site = StubbedSite(json: """
            [{"sgv":38,"date":1700000000000},
             {"sgv":1e20,"date":1700000100000},
             {"sgv":39,"date":1700000200000}]
            """)

        #expect(try await site.nightscout().entries(count: 10).items.map(\.sgv) == [39])
    }

    /// Full counts what the server sent, so a capped page stays full after unusable rows are dropped.
    @Test func aPageIsFullByWhatTheServerSent() async throws {
        let site = StubbedSite(json: """
            [{"sgv":100,"date":1700000000000},
             {"sgv":20,"date":1700000100000}]
            """)

        let page = try await site.nightscout().entries(count: 2)
        #expect(page.items.map(\.sgv) == [100])
        #expect(page.isFull)
        #expect(try await site.nightscout().entries(count: 3).isFull == false)
    }

    @Test func fetchRoundsFractionalSgv() async throws {
        let site = StubbedSite(json: """
            [{"sgv":100.4,"direction":"Flat","date":1700000000000},
             {"sgv":100.5,"direction":"Flat","date":1700000100000}]
            """)

        #expect(try await site.nightscout().entries(count: 10).items.map(\.sgv) == [100, 101])
    }

    @Test func fetchOfASiteWithoutReadingsThrowsEmpty() async throws {
        let site = StubbedSite(json: "[]")

        await #expect(throws: NightscoutError.empty) {
            try await site.nightscout().entries(count: 10)
        }
    }

    @Test func fetchSinceAcceptsAnEmptyAnswer() async throws {
        let site = StubbedSite(json: "[]")

        #expect(try await site.nightscout().entries(count: 10, since: .now).items.isEmpty)
    }

    /// Entries dated past the tolerance stay on the server, or they would fill `count`.
    @Test func fetchSendsTheDateFiltersInMilliseconds() async throws {
        let site = StubbedSite(json: oneReading)
        let now = Date(timeIntervalSince1970: 1_700_000_600)

        _ = try await site.nightscout().entries(count: 10, since: Date(timeIntervalSince1970: 1_700_000_000), now: now)
        #expect(site.requests == [
            "/api/v1/entries/sgv.json?count=10&find%5Bdate%5D%5B$lte%5D=1700000900000"
                + "&find%5Bdate%5D%5B$gt%5D=1700000000000",
        ])
    }

    @Test(arguments: [("   ", nil), (" secret ", "secret")] as [(String, String?)])
    func fetchTrimsTheSiteURLAndToken(token: String, secret: String?) async throws {
        let site = StubbedSite(json: oneReading)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await site.nightscout(token: token, baseURL: site.baseURL + "///").entries(count: 10, now: now)
        #expect(site.requests == ["/api/v1/entries/sgv.json?count=10&find%5Bdate%5D%5B$lte%5D=1700000300000"])
        #expect(site.secrets == [secret])
    }

    /// In a URL, the token would land in the site's access logs and in any proxy's.
    @Test func everyRequestSendsTheTokenInAHeaderOnly() async throws {
        let site = StubbedSite(json: "[]")
        let nightscout = site.nightscout(token: "reader-0123456789abcdef")

        _ = try? await nightscout.entries(count: 1)
        _ = try await nightscout.pumpStatus()
        _ = try await nightscout.treatments(count: 1, since: .now)
        _ = try await nightscout.latestEvent("Site Change", since: .now)
        #expect(site.requests.count == 4)
        #expect(site.requests.allSatisfy { !$0.contains("reader-0123456789abcdef") && !$0.contains("token") })
        #expect(site.secrets == Array(repeating: "reader-0123456789abcdef", count: 4))
    }

    @Test(arguments: ["not json at all", #"{"foo":1}"#])
    func fetchRejectsAnythingButAJSONArray(body: String) async throws {
        let site = StubbedSite(json: body)

        await #expect(throws: NightscoutError.decode) {
            try await site.nightscout().entries(count: 10)
        }
    }

    @Test func fetchReportsAnHTTPErrorStatus() async throws {
        let site = StubbedSite(status: 500, json: "[]")

        await #expect(throws: NightscoutError.http(500)) {
            try await site.nightscout().entries(count: 10)
        }
    }
}

extension SugargliderTests {
    @Test(arguments: [#"[{"sgv":100,"direction":"Flat","date":1700000000000}]"#, "[]"])
    func probeCountsAReachableSiteAsConnectedEvenWithoutReadings(body: String) async throws {
        let site = StubbedSite(json: body)

        #expect(await site.nightscout().probe() == .connected)
    }

    @Test(arguments: [401, 403])
    func probeReportsRejectedCredentials(status: Int) async throws {
        let site = StubbedSite(status: status, json: "[]")

        #expect(await site.nightscout(token: "wrong").probe() == .failed("Authentication failed. Check the token."))
    }

    @Test func probeReportsAnyOtherHTTPStatus() async throws {
        let site = StubbedSite(status: 500, json: "[]")

        #expect(await site.nightscout().probe() == .failed("HTTP 500"))
    }

    @Test func probeReportsAnInvalidURL() async {
        #expect(await Nightscout(baseURL: "http://exa mple.com", token: "").probe() == .failed("Invalid URL"))
    }

    @Test func probeReportsAnUnconfiguredURL() async {
        #expect(await Nightscout(baseURL: "   ", token: "").probe() == .failed("Not configured"))
    }

    /// The store's wake-from-sleep behavior and the stale-cache fix live in these numbers; a
    /// "simplification" that reuses the probe session for polling would bring both bugs back.
    @Test func sessionsCarryTheLoadBearingConfigurations() {
        let polling = Nightscout.pollingSession.configuration
        let probe = Nightscout.sharedSession.configuration
        #expect(polling.waitsForConnectivity)
        #expect(!probe.waitsForConnectivity)
        #expect(polling.timeoutIntervalForRequest == 15)
        #expect(polling.timeoutIntervalForResource == 60)
        #expect(polling.urlCache == nil)
        #expect(probe.urlCache == nil)
    }
}
