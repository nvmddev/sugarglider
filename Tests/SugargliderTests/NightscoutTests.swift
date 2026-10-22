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

        let readings = try await site.nightscout().entries(count: 10)
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

        let readings = try await site.nightscout().entries(count: 10)
        #expect(readings.map(\.sgv) == [100, 110])
        #expect(readings.last?.direction == nil)
    }

    @Test func fetchRoundsFractionalSgv() async throws {
        let site = StubbedSite(json: """
            [{"sgv":100.4,"direction":"Flat","date":1700000000000},
             {"sgv":100.5,"direction":"Flat","date":1700000100000}]
            """)

        #expect(try await site.nightscout().entries(count: 10).map(\.sgv) == [100, 101])
    }

    @Test func fetchOfASiteWithoutReadingsThrowsEmpty() async throws {
        let site = StubbedSite(json: "[]")

        await #expect(throws: NightscoutError.empty) {
            try await site.nightscout().entries(count: 10)
        }
    }

    @Test func fetchSinceAcceptsAnEmptyAnswer() async throws {
        let site = StubbedSite(json: "[]")

        #expect(try await site.nightscout().entries(count: 10, since: .now).isEmpty)
    }

    @Test func fetchSinceSendsTheDateFilterInMilliseconds() async throws {
        let site = StubbedSite(json: oneReading)

        _ = try await site.nightscout().entries(count: 10, since: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(site.requests == ["/api/v1/entries/sgv.json?count=10&find%5Bdate%5D%5B$gt%5D=1700000000000"])
    }

    @Test(arguments: [("   ", ""), (" secret ", "&token=secret")])
    func fetchTrimsTheSiteURLAndToken(token: String, tokenQuery: String) async throws {
        let site = StubbedSite(json: oneReading)

        _ = try await site.nightscout(token: token, baseURL: site.baseURL + "///").entries(count: 10)
        #expect(site.requests == ["/api/v1/entries/sgv.json?count=10\(tokenQuery)"])
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

        #expect(await site.nightscout(token: "wrong").probe() == .failed("Authentication failed — check the token"))
    }

    @Test func probeReportsAnyOtherHTTPStatus() async throws {
        let site = StubbedSite(status: 500, json: "[]")

        #expect(await site.nightscout().probe() == .failed("HTTP 500"))
    }

    @Test func probeReportsAnInvalidURL() async {
        #expect(await Nightscout(baseURL: "http://exa mple.com", token: "").probe() == .failed("Invalid URL"))
    }
}
