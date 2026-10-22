import Testing
import Foundation
import Synchronization
@testable import Sugarglider

extension SugargliderTests {
    @Test(arguments: [(5, "just now"), (65, "1 min ago"), (200, "3 min ago"), (3660, "1 h ago"), (7320, "2 h ago")])
    func relativeTime(secondsAgo: Int, expected: String) {
        let now = Date.now
        #expect(ReadingStore.relative(now.addingTimeInterval(-TimeInterval(secondsAgo)), now: now) == expected)
    }

    @Test(arguments: [
        (13 * 60, "13m"), (59 * 60 + 59, "59m"), (3600 + 30, "1h"), (50 * 3600, "2d"),
        (-30, "0m"),   // clock skew
    ] as [(Int, String)])
    func compactAgeRoundsDown(secondsAgo: Int, expected: String) {
        let now = Date.now
        #expect(ReadingStore.compactAge(now.addingTimeInterval(-TimeInterval(secondsAgo)), now: now) == expected)
    }

    @Test func isStaleAfterTheDefaultDelay() {
        let store = ReadingStore(settings: Self.makeSettings())
        #expect(!store.isStale)
        store.lastReading = reading(100, minutesAgo: 5)
        #expect(!store.isStale)
        store.lastReading = reading(100, minutesAgo: 12)   // past the 11 min default
        #expect(store.isStale)
    }

    @Test func isStaleFollowsTheConfiguredDelay() {
        let settings = Self.makeSettings()
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(100, minutesAgo: 15)
        #expect(store.isStale)
        settings.staleAfterMinutes = 20
        #expect(!store.isStale)
        settings.staleAfterMinutes = 5
        #expect(store.isStale)
    }

    /// The menu bar label redraws only when something it reads changes, and while polls fail nothing
    /// else does.
    @Test func clockTicksReachWhatTheStaleCheckReads() {
        let store = ReadingStore(settings: Self.makeSettings())
        store.lastReading = reading(100, minutesAgo: 5)
        let redrawn = Atomic(false)
        withObservationTracking { _ = store.isStale } onChange: { redrawn.store(true, ordering: .relaxed) }
        store.tick()
        let didRedraw = redrawn.load(ordering: .relaxed)
        #expect(didRedraw)
    }

    @Test(arguments: [
        (.mmol, 108, 90, "+1.0"),
        (.mgdl, 108, 90, "+18"),
        (.mmol, 90, 108, "-1.0"),
    ] as [(AppSettings.Units, Int, Int, String)])
    func deltaIsSignedInTheDisplayUnit(units: AppSettings.Units, sgv: Int, previousSGV: Int, expected: String) {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        settings.units = units
        let store = ReadingStore(settings: settings)
        let now = Date.now
        store.lastReading = reading(sgv, from: now)
        store.previousReading = reading(previousSGV, minutesAgo: 5, from: now)
        #expect(store.deltaText() == expected)
    }

    @Test(arguments: [
        (.off, 5),
        (.menu, nil),
        (.menu, 12),    // too far apart to count as consecutive
        (.menu, 20),
        (.menu, -5),    // the previous reading is the newer one
    ] as [(AppSettings.DeltaDisplay, Int?)])
    func deltaIsNilUnlessShownForConsecutiveReadings(display: AppSettings.DeltaDisplay, previousMinutesAgo: Int?) {
        let settings = Self.makeSettings()
        settings.deltaDisplay = display
        let store = ReadingStore(settings: settings)
        let now = Date.now
        store.lastReading = reading(108, from: now)
        store.previousReading = previousMinutesAgo.map { reading(90, minutesAgo: Double($0), from: now) }
        #expect(store.deltaText() == nil)
    }

    /// A marker is a bound, not a value, so a difference to it would be made up.
    @Test(arguments: [(39, 60), (60, 39), (401, 380), (380, 401), (39, 39)])
    func deltaIsNilAcrossLowOrHigh(sgv: Int, previousSGV: Int) {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        let store = ReadingStore(settings: settings)
        let now = Date.now
        store.lastReading = reading(sgv, from: now)
        store.previousReading = reading(previousSGV, minutesAgo: 5, from: now)
        #expect(store.deltaText() == nil)
    }

    @Test func historyCountFollowsTheSelectedRange() {
        #expect(ReadingStore.historyCount(forRangeHours: 6) == 420)
        #expect(ReadingStore.historyCount(forRangeHours: 24) == 1500)
        #expect(ReadingStore.historyCount(forRangeHours: 72) == 2880)
        for hours in AppSettings.rangeHoursLimits {
            let count = ReadingStore.historyCount(forRangeHours: hours)
            #expect(count > hours * 12)   // a site uploading every 5 min never reaches it
            #expect(count <= 2880)
        }
    }

    @Test func coverageComparesAgainstTheRequestedWindow() {
        let now = Date.now
        let requested = now.addingTimeInterval(-6 * 3600)
        #expect(!ReadingStore.historyCovers(requested: nil, from: now.addingTimeInterval(-3600)))
        #expect(ReadingStore.historyCovers(requested: requested, from: requested))
        #expect(ReadingStore.historyCovers(requested: requested, from: now.addingTimeInterval(-3600)))
        #expect(!ReadingStore.historyCovers(requested: requested, from: now.addingTimeInterval(-24 * 3600)))
        // An hour later the same window has slid forward, so it stays covered.
        #expect(ReadingStore.historyCovers(requested: requested, from: requested.addingTimeInterval(3600)))
    }

    @Test(arguments: [
        ([0, 5], true),
        ([5, 10], true),
        ([15, 20], true),    // a gap the chart still draws as one line
        ([20, 25], false),
        ([-5, 0], false),    // nothing new
    ])
    func polledEntriesJoinTheHistoryOnlyWithoutADropout(minutesAfterNewestCached: [Int], joins: Bool) {
        let newestCached = Date.now
        let history = [reading(110, minutesAgo: 5, from: newestCached), reading(120, from: newestCached)]
        let polled = minutesAfterNewestCached.map { reading(130, minutesAgo: -Double($0), from: newestCached) }
        #expect(ReadingStore.joinsUp(polled, with: history) == joins)
        #expect(!ReadingStore.joinsUp(polled, with: []))
    }

    @Test func mergedReadingsReplaceByTimestampAndDropTheVeryOld() {
        let now = Date.now
        let merged = ReadingStore.merged(
            [reading(100, minutesAgo: 80 * 60, from: now), reading(110, minutesAgo: 10, from: now)],
            with: [reading(120, minutesAgo: 5, from: now), reading(115, minutesAgo: 10, from: now)],
            now: now)
        #expect(merged.map(\.sgv) == [115, 120])
    }

    @Test(arguments: [(10.0, [100, 110, 120]), (40.0, [100])])
    func pollAddsToTheHistoryOnlyWithoutADropout(cachedMinutesAgo: Double, history: [Int]) async throws {
        let nowMs = epochMillis(.now)
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 300_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)
        store.readings = [reading(100, minutesAgo: cachedMinutesAgo)]

        store.refresh()
        try await waitUntil("the poll") { store.lastReading != nil }
        #expect(store.lastReading?.sgv == 120)
        #expect(store.readings.map(\.sgv) == history)
    }

    @Test func historyAsksForTheWindowOnceThenOnlyForWhatIsNewer() async throws {
        let nowMs = epochMillis(.now)
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 600_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)

        store.refreshHistory(force: true)
        try await waitUntil("the first history fetch") { !store.readings.isEmpty }
        #expect(store.readings.count == 2)
        #expect(store.lastReading?.sgv == 120)
        #expect(store.previousReading?.sgv == 110)
        let windowStart = try #require(store.historyWindowStart)
        #expect(server.requestLines.count == 1)
        #expect(server.requestLines[0].contains("$gt%5D=\(epochMillis(windowStart))"))

        store.refreshHistory(force: true)
        try await waitUntil("the top-up fetch") { server.requestLines.count == 2 }
        let newest = try #require(store.readings.last?.date)
        #expect(server.requestLines[1].contains("$gt%5D=\(epochMillis(newest))"))
    }

    /// Waits on the recorded window rather than on the request count: the window is set only
    /// once the response lands, so counting requests races the fetch.
    @Test func wideningTheRangeFetchesTheMissingHistory() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 300_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)

        store.refreshHistory(force: true)
        try await waitUntil("the first history fetch") {
            store.coversHistory(from: .now.addingTimeInterval(-6 * 3600))   // the default range
        }
        #expect(!store.coversHistory(from: .now.addingTimeInterval(-24 * 3600)))

        settings.rangeHours = 24
        store.ensureHistoryCoverage()
        try await waitUntil("the widened window") {
            store.coversHistory(from: .now.addingTimeInterval(-24 * 3600))
        }
        #expect(server.requestLines.count >= 2)
    }

    @Test func reconnectForgetsThePreviousSite() async throws {
        let nowMs = epochMillis(.now)
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 600_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)
        store.refreshHistory(force: true)
        try await waitUntil("the history fetch") { store.historyWindowStart != nil }
        store.lastError = "boom"

        settings.baseURL = ""   // keeps the debounced re-fetch off the network
        store.reconnect()
        #expect(store.lastReading == nil)
        #expect(store.previousReading == nil)
        #expect(store.lastError == nil)
        #expect(store.readings.isEmpty)
        #expect(store.historyWindowStart == nil)
        #expect(!store.coversHistory(from: .now.addingTimeInterval(-3600)))
    }

    /// Without these hooks the app would keep polling a stale URL, ignore a new refresh
    /// interval and leave a widened chart range unfilled.
    @Test func startSubscribesToSettingsAndPolls() throws {
        let settings = Self.makeSettings()
        let store = ReadingStore(settings: settings)
        #expect(settings.onConnectionChanged == nil)
        #expect(store.timer == nil)

        store.start()
        defer { store.timer?.invalidate() }
        #expect(settings.onConnectionChanged != nil)
        #expect(settings.onPollIntervalChanged != nil)
        #expect(settings.onRangeHoursChanged != nil)
        #expect(store.timer?.timeInterval == 60)

        // Whitespace keeps the site unconfigured, so the debounced re-fetch stays off the network.
        store.readings = [reading(100)]
        settings.baseURL = "   "
        #expect(store.readings.isEmpty)

        let first = try #require(store.timer)
        settings.pollIntervalSeconds = 30
        #expect(store.timer !== first)
        #expect(store.timer?.timeInterval == 30)
        #expect(!first.isValid)
    }
}
