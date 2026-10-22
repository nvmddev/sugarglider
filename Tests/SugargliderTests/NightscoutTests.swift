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
        let server = try LocalHTTPServer(json: """
            [{"sgv":150,"direction":"Flat","date":1700000300000},
             {"sgv":100,"direction":"FortyFiveUp","date":1700000000000}]
            """)
        defer { server.stop() }

        let readings = try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
        #expect(readings.map(\.sgv) == [100, 150])
        #expect(readings.first?.direction == .fortyFiveUp)
        #expect(readings.first?.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func fetchSkipsUnusableRowsAndDefaultsAMissingDirection() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100,"direction":"Flat","date":1700000000000},
             {"direction":"Flat","date":1700000100000},
             {"sgv":110,"date":1700000200000},
             {"sgv":"bad","date":1700000300000},
             {"sgv":120,"direction":null,"date":null},
             {}]
            """)
        defer { server.stop() }

        let readings = try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
        #expect(readings.map(\.sgv) == [100, 110])
        #expect(readings.last?.direction == nil)
    }

    @Test func fetchRoundsFractionalSgv() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100.4,"direction":"Flat","date":1700000000000},
             {"sgv":100.5,"direction":"Flat","date":1700000100000}]
            """)
        defer { server.stop() }

        #expect(try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
            .map(\.sgv) == [100, 101])
    }

    @Test func fetchOfASiteWithoutReadingsThrowsEmpty() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }

        await #expect(throws: NightscoutError.empty) {
            try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
        }
    }

    @Test func fetchSinceAcceptsAnEmptyAnswer() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }

        #expect(try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10, since: .now)
            .isEmpty)
    }

    @Test func fetchSinceSendsTheDateFilterInMilliseconds() async throws {
        let server = try LocalHTTPServer(json: oneReading)
        defer { server.stop() }

        _ = try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10, since: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(server.requestLines == [
            "GET /api/v1/entries/sgv.json?count=10&find%5Bdate%5D%5B$gt%5D=1700000000000 HTTP/1.1",
        ])
    }

    @Test(arguments: [("   ", ""), (" secret ", "&token=secret")])
    func fetchTrimsTheSiteURLAndToken(token: String, tokenQuery: String) async throws {
        let server = try LocalHTTPServer(json: oneReading)
        defer { server.stop() }

        _ = try await Nightscout(baseURL: server.baseURL + "///", token: token).entries(count: 10)
        #expect(server.requestLines == ["GET /api/v1/entries/sgv.json?count=10\(tokenQuery) HTTP/1.1"])
    }

    @Test(arguments: ["not json at all", #"{"foo":1}"#])
    func fetchRejectsAnythingButAJSONArray(body: String) async throws {
        let server = try LocalHTTPServer(json: body)
        defer { server.stop() }

        await #expect(throws: NightscoutError.decode) {
            try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
        }
    }

    @Test func fetchReportsAnHTTPErrorStatus() async throws {
        let server = try LocalHTTPServer(status: 500, json: "[]")
        defer { server.stop() }

        await #expect(throws: NightscoutError.http(500)) {
            try await Nightscout(baseURL: server.baseURL, token: "").entries(count: 10)
        }
    }
}

extension SugargliderTests {
    @Test(arguments: [#"[{"sgv":100,"direction":"Flat","date":1700000000000}]"#, "[]"])
    func probeCountsAReachableSiteAsConnectedEvenWithoutReadings(body: String) async throws {
        let server = try LocalHTTPServer(json: body)
        defer { server.stop() }

        #expect(await Nightscout(baseURL: server.baseURL, token: "").probe() == .connected)
    }

    @Test(arguments: [401, 403])
    func probeReportsRejectedCredentials(status: Int) async throws {
        let server = try LocalHTTPServer(status: status, json: "[]")
        defer { server.stop() }

        #expect(await Nightscout(baseURL: server.baseURL, token: "wrong").probe()
            == .failed("Authentication failed — check the token"))
    }

    @Test func probeReportsAnyOtherHTTPStatus() async throws {
        let server = try LocalHTTPServer(status: 500, json: "[]")
        defer { server.stop() }

        #expect(await Nightscout(baseURL: server.baseURL, token: "").probe() == .failed("HTTP 500"))
    }

    @Test func probeReportsAnInvalidURL() async {
        #expect(await Nightscout(baseURL: "http://exa mple.com", token: "").probe() == .failed("Invalid URL"))
    }
}
