import Testing
import Foundation
import Synchronization
@testable import Sugarglider

extension SugargliderTests {
    @Test(arguments: [(5, "this minute"), (65, "1 minute ago"), (200, "3 minutes ago"), (3660, "1 hour ago"),
                      (7320, "2 hours ago")])
    func relativeTime(secondsAgo: Int, expected: String) {
        let now = Date.now
        #expect(now.addingTimeInterval(-TimeInterval(secondsAgo)).relative(to: now) == expected)
    }

    @Test(arguments: [
        (13 * 60, 1, "13m"), (59 * 60 + 59, 1, "59m"), (3600 + 30, 1, "1h"), (50 * 3600, 1, "2d"),
        (5 * 3600 + 12 * 60, 2, "5h 12m"), (49 * 3600 + 60, 2, "2d 1h"),
        (-30, 1, "0m"),   // clock skew
    ] as [(Int, Int, String)])
    func ageRoundsDown(secondsAgo: Int, units: Int, expected: String) {
        let now = Date.now
        #expect(now.addingTimeInterval(-TimeInterval(secondsAgo)).age(at: now, units: units) == expected)
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

    @Test func titleBeforeTheFirstReading() {
        let settings = Self.makeSettings()
        let store = ReadingStore(settings: settings)
        let label = MenuBarLabel(settings: settings, store: store)
        #expect(label.title == "CGM ⚙")
        settings.baseURL = "https://ns.example"
        #expect(label.title == "CGM …")
        store.lastError = "HTTP 500"
        #expect(label.title == "CGM ⚠")
    }

    @Test(arguments: [
        (.mmol, 120, .flat, "6.7 →"),
        (.mgdl, 120, .doubleDown, "120 ↓↓"),
        (.mmol, 120, nil, "6.7"),
        (.mmol, 39, nil, "LOW"),
        (.mgdl, 401, .doubleUp, "HIGH ↑↑"),
    ] as [(AppSettings.Units, Int, Reading.Direction?, String)])
    func titleShowsTheValueAndArrow(units: AppSettings.Units, sgv: Int, direction: Reading.Direction?,
                                    expected: String) {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        settings.units = units
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(sgv, direction: direction, from: store.now)
        #expect(MenuBarLabel(settings: settings, store: store).title == expected)
    }

    @Test func titleShowsTheDeltaOnlyWhenSetToTheStatusBar() {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(120, from: store.now)
        store.previousReading = reading(118, minutesAgo: 5, from: store.now)
        let label = MenuBarLabel(settings: settings, store: store)
        #expect(label.title == "6.7 →")   // the default shows it in the dropdown only
        settings.deltaDisplay = .menuAndStatusBar
        #expect(label.title == "6.7 →  (+0.1)")
    }

    /// A failed poll leaves the last reading up, so its age is what shows that it's old.
    @Test func titleShowsTheAgeOnceStale() {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        let store = ReadingStore(settings: settings)
        let label = MenuBarLabel(settings: settings, store: store)
        store.lastReading = reading(120, minutesAgo: 10, from: store.now)
        #expect(label.title == "6.7 →")
        store.lastReading = reading(120, minutesAgo: 23, from: store.now)
        #expect(label.title == "6.7 → ⚠ 23m")
        store.lastError = "HTTP 500"
        #expect(label.title == "6.7 → ⚠ 23m")
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
        #expect(!ReadingStore.covers(nil, from: now.addingTimeInterval(-3600)))
        #expect(ReadingStore.covers(requested, from: requested))
        #expect(ReadingStore.covers(requested, from: now.addingTimeInterval(-3600)))
        #expect(!ReadingStore.covers(requested, from: now.addingTimeInterval(-24 * 3600)))
        // An hour later the same window has slid forward, so it stays covered.
        #expect(ReadingStore.covers(requested, from: requested.addingTimeInterval(3600)))
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
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 300_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)
        store.readings = [reading(100, minutesAgo: cachedMinutesAgo)]

        await store.refresh()
        #expect(store.lastReading?.sgv == 120)
        #expect(store.readings.map(\.sgv) == history)
    }

    /// The error is what turns the title into "CGM ⚠" and fills the dropdown's error line. The last
    /// reading stays, so the title keeps showing it and its growing age.
    @Test(arguments: [
        (500, "{}", NightscoutError.http(500)),
        (401, #"{"status":401}"#, .http(401)),
        (200, "<html></html>", .decode),
        (200, "[]", .empty),
    ] as [(Int, String, NightscoutError)])
    func failedPollReportsWhyUntilOneSucceeds(status: Int, json: String, error: NightscoutError) async throws {
        let failing = StubbedSite(status: status, json: json)
        let settings = Self.makeSettings()
        let store = failing.store(settings)
        store.lastReading = reading(110, minutesAgo: 5)

        await store.refresh()
        #expect(store.lastError == error.localizedDescription)
        #expect(store.lastReading?.sgv == 110)

        let working = StubbedSite(json: #"[{"sgv":120,"direction":"Flat","date":\#(epochMillis(.now))}]"#)
        settings.baseURL = working.baseURL
        await store.refresh()
        #expect(store.lastError == nil)
        #expect(store.lastReading?.sgv == 120)
    }

    @Test func historyAsksForTheWindowOnceThenOnlyForWhatIsNewer() async throws {
        let nowMs = epochMillis(.now)
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 600_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)

        await store.refreshHistory(force: true)
        #expect(store.readings.count == 2)
        #expect(store.lastReading?.sgv == 120)
        #expect(store.previousReading?.sgv == 110)
        let windowStart = try #require(store.historyWindowStart)
        #expect(server.requests.count == 1)
        #expect(server.requests[0].contains("$gt%5D=\(epochMillis(windowStart))"))

        await store.refreshHistory(force: true)
        #expect(server.requests.count == 2)
        let newest = try #require(store.readings.last?.date)
        #expect(server.requests[1].contains("$gt%5D=\(epochMillis(newest))"))
    }

    /// The dropdown refreshes on every open. The throttle is per part, so a switch just turned on
    /// is fetched on the next open while the rest waits out its minute.
    @Test func eachPartIsFetchedAtMostOnceAMinute() async throws {
        let server = StubbedSite(json: "[]")
        let settings = Self.makeSettings()
        let store = server.store(settings)

        await store.refreshHistory(force: false)
        await store.refreshDetails(force: false)
        #expect(server.requests.count == 3)   // readings, device status, treatments

        await store.refreshHistory(force: false)
        await store.refreshDetails(force: false)
        #expect(server.requests.count == 3)

        settings.showChangeAge = true
        await store.refreshDetails(force: false)
        #expect(server.requests.count == 5)
        #expect(server.requests.dropFirst(3).allSatisfy { $0.contains("eventType") })

        await store.refreshDetails(force: true)
        #expect(server.requests.count == 9)
    }

    /// A failed request leaves what's shown and isn't throttled, so the next open asks again.
    @Test func aFailedFetchKeepsTheValuesAndIsRetried() async throws {
        let server = StubbedSite(status: 500, json: "{}")
        let settings = Self.makeSettings()
        settings.showChangeAge = true
        let store = server.store(settings)
        let status = PumpStatus(date: .now, reservoir: 120)
        let bolus = Treatment(id: "b", date: .now, kind: .bolus(units: 1))
        let changed = Date.now.addingTimeInterval(-86_400)
        store.readings = [reading(110)]
        store.pumpStatus = status
        store.treatments = [bolus]
        store.reservoirChanged = changed

        for _ in 0..<2 {
            await store.refreshHistory(force: false)
            await store.refreshDetails(force: false)
        }
        #expect(server.requests.count == 2 * 5)   // readings, device status, treatments, two changes
        #expect(store.readings.map(\.sgv) == [110])
        #expect(store.pumpStatus == status)
        #expect(store.treatments == [bolus])
        #expect(store.reservoirChanged == changed)
    }

    @Test func wideningTheRangeFetchesTheMissingHistory() async throws {
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 300_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)

        await store.refreshHistory(force: true)
        #expect(ReadingStore.covers(store.historyWindowStart, from: .now.addingTimeInterval(-6 * 3600)))
        #expect(!ReadingStore.covers(store.historyWindowStart, from: .now.addingTimeInterval(-24 * 3600)))

        settings.rangeHours = 24
        store.ensureHistoryCoverage()
        try await waitUntil("the debounced fetch of the widened window") {
            ReadingStore.covers(store.historyWindowStart, from: .now.addingTimeInterval(-24 * 3600))
        }
        #expect(server.requests.count >= 2)
    }

    @Test func reconnectForgetsThePreviousSite() async throws {
        let nowMs = epochMillis(.now)
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 600_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)
        await store.refreshHistory(force: true)
        #expect(store.historyWindowStart != nil)
        store.lastError = "boom"

        settings.baseURL = ""   // keeps the debounced re-fetch off the network
        store.reconnect()
        #expect(store.lastReading == nil)
        #expect(store.previousReading == nil)
        #expect(store.lastError == nil)
        #expect(store.readings.isEmpty)
        #expect(store.historyWindowStart == nil)
        #expect(!ReadingStore.covers(store.historyWindowStart, from: .now.addingTimeInterval(-3600)))
    }

    /// Without this the app would keep polling a site that was replaced, ignore a new refresh
    /// interval and leave a widened chart range unfilled.
    @Test func startPollsAndFollowsTheSettings() async throws {
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 300_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)

        store.start()
        try await waitUntil("the first poll") { store.lastReading != nil }
        let polls = server.requests.count
        settings.pollIntervalSeconds = 30
        try await waitUntil("polling restarted at the new interval") { server.requests.count > polls }

        settings.rangeHours = 24
        try await waitUntil("the widened history") {
            ReadingStore.covers(store.historyWindowStart, from: .now.addingTimeInterval(-24 * 3600))
        }

        // Whitespace leaves the site unconfigured, so the debounced re-fetch stays off the network.
        settings.baseURL = "   "
        try await waitUntil("the reconnect") { store.lastReading == nil && store.readings.isEmpty }
    }
}
