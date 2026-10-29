import Testing
import Foundation
import SwiftUI
import Synchronization
@testable import Sugarglider

extension SugargliderTests {
    @Test(arguments: [(5, "this minute"), (65, "1 minute ago"), (200, "3 minutes ago"), (3660, "1 hour ago"),
                      (7320, "2 hours ago")])
    func relativeTime(secondsAgo: Int, expected: String) {
        let now = Date.now
        #expect(now.addingTimeInterval(-TimeInterval(secondsAgo)).relative(to: now, locale: Self.enUS) == expected)
    }

    @Test(arguments: [
        (13 * 60, 1, "13m"), (59 * 60 + 59, 1, "59m"), (3600 + 30, 1, "1h"), (50 * 3600, 1, "2d"),
        (5 * 3600 + 12 * 60, 2, "5h 12m"), (49 * 3600 + 60, 2, "2d 1h"),
        (-30, 1, "0m"),   // clock skew
    ] as [(Int, Int, String)])
    func ageRoundsDown(secondsAgo: Int, units: Int, expected: String) {
        let now = Date.now
        #expect(now.addingTimeInterval(-TimeInterval(secondsAgo)).age(at: now, units: units, locale: Self.enUS) == expected)
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
        settings.deltaDisplay = .dropdown
        settings.units = units
        let store = ReadingStore(settings: settings)
        let now = Date.now
        store.lastReading = reading(sgv, from: now)
        store.previousReading = reading(previousSGV, minutesAgo: 5, from: now)
        #expect(store.deltaText(locale: Self.enUS) == expected)
    }

    @Test(arguments: [
        (.off, 5),
        (.dropdown, nil),
        (.dropdown, 12),    // too far apart to count as consecutive
        (.dropdown, 20),
        (.dropdown, -5),    // the previous reading is the newer one
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
        settings.deltaDisplay = .dropdown
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
        #expect(MenuBarLabel(settings: settings, store: store).title(locale: Self.enUS) == expected)
    }

    @Test func spokenTitleNamesTheTrend() {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(120, direction: .fortyFiveUp, from: store.now)
        #expect(MenuBarLabel(settings: settings, store: store).spokenTitle(locale: Self.enUS) == "6.7, rising slowly")
    }

    @Test func titleShowsTheDeltaOnlyWhenSetToTheStatusBar() {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(120, from: store.now)
        store.previousReading = reading(118, minutesAgo: 5, from: store.now)
        let label = MenuBarLabel(settings: settings, store: store)
        #expect(label.title(locale: Self.enUS) == "6.7 →")   // the default shows it in the dropdown only
        settings.deltaDisplay = .dropdownAndStatusBar
        #expect(label.title(locale: Self.enUS) == "6.7 →  (+0.1)")
    }

    /// A failed poll leaves the last reading up, so its age is what shows that it's old.
    @Test func titleShowsTheAgeOnceStale() {
        let settings = Self.makeSettings()
        settings.baseURL = "https://ns.example"
        let store = ReadingStore(settings: settings)
        let label = MenuBarLabel(settings: settings, store: store)
        store.lastReading = reading(120, minutesAgo: 10, from: store.now)
        #expect(label.title(locale: Self.enUS) == "6.7 →")
        store.lastReading = reading(120, minutesAgo: 23, from: store.now)
        #expect(label.title(locale: Self.enUS) == "6.7 → ⚠ 23m")
        store.lastError = "HTTP 500"
        #expect(label.title(locale: Self.enUS) == "6.7 → ⚠ 23m")
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

    // MARK: - T2: future-dated entries

    @Test func entriesDatedAheadAreDroppedFromThePoll() {
        let now = Date.now
        let fresh = reading(120, from: now)
        let skew = reading(130, minutesAgo: -120, from: now)   // two hours ahead of the Mac's clock
        #expect(ReadingStore.keepingPlausible([fresh, skew], now: now) == [fresh])
        // Inside the tolerance the entry still counts: a few minutes of skew are ordinary.
        #expect(ReadingStore.keepingPlausible([reading(120, minutesAgo: -4, from: now)], now: now).count == 1)
    }

    /// A site whose uploader posts an entry dated ahead used to pin the menu bar to it forever:
    /// every poll returned it as the newest, and its negative age could never go stale.
    @Test func pollWithOnlyFutureDatedEntriesKeepsThePreviousReading() async throws {
        let server = StubbedSite(json: """
            [{"sgv":130,"direction":"Flat","date":\(epochMillis(.now.addingTimeInterval(2 * 3600)))}]
            """)
        let store = server.store(Self.makeSettings())
        store.lastReading = reading(110, minutesAgo: 30)
        store.previousReading = reading(105, minutesAgo: 35)

        await store.refresh()
        #expect(store.lastReading?.sgv == 110)
        #expect(store.previousReading?.sgv == 105)
        #expect(store.lastError == nil)
        #expect(store.readings.isEmpty)
        #expect(store.isStale)   // the kept reading ages into the stale warning
    }

    @Test func historyDropsFutureDatedEntries() async throws {
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 600_000)},
             {"sgv":130,"direction":"Flat","date":\(epochMillis(.now.addingTimeInterval(2 * 3600)))}]
            """)
        let store = server.store(Self.makeSettings())

        await store.refreshHistory(force: true)
        #expect(store.readings.map(\.sgv) == [120])
        #expect(store.lastReading?.sgv == 120)
        #expect(store.previousReading == nil)
    }

    // MARK: - T2: notifications without a value change

    /// Observation skips equal assignments only for Equatable members; `Reading` is Equatable now,
    /// so a poll that changes nothing must not notify the menu bar label or an open dropdown.
    @Test func anUnchangedPollWritesNothingObservable() async throws {
        let nowMs = epochMillis(.now)
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 300_000)}]
            """)
        let store = server.store(Self.makeSettings())
        await store.refresh()
        #expect(store.lastReading?.sgv == 120)
        #expect(store.previousReading?.sgv == 110)
        #expect(store.readings.isEmpty)   // a poll only merges into an existing, contiguous history

        let notified = Atomic(false)
        withObservationTracking { _ = (store.lastReading, store.previousReading, store.readings, store.now) }
            onChange: { notified.store(true, ordering: .relaxed) }
        await store.refresh()
        // The access-tracking callback fires during the mutation, so by now a buggy
        // notification would already be recorded; nothing runs later that could set it.
        let didNotify = notified.load(ordering: .relaxed)
        #expect(!didNotify)
    }

    // MARK: - T2: debounce and refresh paths

    /// A drag out and back within the debounce covered the range again: the scheduled task must
    /// re-check and fetch nothing, or every quick drag wasted a force fetch.
    @Test func wideningCanceledByRestoringTheRangeFetchesNothing() async throws {
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 300_000)}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)
        await store.refreshHistory(force: true)
        let requestsBefore = server.requests.count

        settings.rangeHours = 24
        store.ensureHistoryCoverage()
        settings.rangeHours = 6
        store.ensureHistoryCoverage()
        try await Task.sleep(for: .milliseconds(600))   // past the 400 ms debounce
        #expect(server.requests.count == requestsBefore)
    }

    /// The Refresh button's one call: everything, once, in one task.
    @Test func refreshAllFetchesThePollTheHistoryAndTheDetails() async throws {
        let server = StubbedSite(json: "[]")
        let store = server.store(Self.makeSettings())

        await store.refreshAll(force: true)
        #expect(server.requests.count == 4)   // the poll's two entries, history, device status, treatments
    }

    /// The unconfigured clock ticks slowly to save wakeups; the first reading restarts it, or the
    /// residual long sleep would freeze the age and the stale check for up to five minutes. The
    /// interval is injected, so the restart proves itself in milliseconds instead of 30 seconds.
    @Test func theFirstReadingRestartsTheClockToItsSteadyInterval() async throws {
        let server = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(epochMillis(.now) - 300_000)}]
            """)
        let settings = Self.makeSettings()
        settings.pollIntervalSeconds = 300   // keep the poll itself out of the way
        let store = server.store(settings)
        store.tickInterval = .milliseconds(50)
        store.start()
        try await waitUntil("the first poll") { store.lastReading != nil }
        let before = store.now

        // The tick plus its 5 s tolerance: well before the 300 s sleep the clock was on.
        let deadline = Date.now.addingTimeInterval(8)
        var ticked = false
        while Date.now < deadline, !ticked {
            ticked = store.now > before
            if !ticked { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(ticked)
    }

    // MARK: - T6: races and seams

    /// The generation guard is the whole protection against a slow answer from a replaced site
    /// repopulating the store. Without it, the old site's glucose would show with the new
    /// site's settings.
    @Test func aSlowAnswerFromAReplacedSiteIsDropped() async throws {
        let nowMs = epochMillis(.now)
        let old = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs)}]
            """)
        old.delay = 0.2
        let settings = Self.makeSettings()
        let store = old.store(settings)
        let refresh = Task { await store.refresh() }
        try await waitUntil("the slow request started") { !old.requests.isEmpty }
        settings.baseURL = ""   // keeps the debounced re-fetch off the network
        store.reconnect()
        await refresh.value
        #expect(store.lastReading == nil)
        #expect(store.readings.isEmpty)
    }

    /// Changing the URL must show the new site's data after the 500 ms debounce: the generation
    /// bump lets the new answers through and the cleared throttle makes history fetchable.
    @Test func reconnectFetchesFromTheNewSite() async throws {
        let nowMs = epochMillis(.now)
        let first = StubbedSite(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs)}]
            """)
        let second = StubbedSite(json: """
            [{"sgv":130,"direction":"Flat","date":\(nowMs)}]
            """)
        let settings = Self.makeSettings()
        let store = first.store(settings)
        await store.refresh()
        #expect(store.lastReading?.sgv == 120)

        settings.baseURL = second.baseURL
        store.reconnect()
        // The reading lands with the poll, the history one round trip later in the same
        // task, so wait for both together.
        try await waitUntil("the new site's reading") {
            store.lastReading?.sgv == 130 && store.readings.map(\.sgv) == [130]
        }
        #expect(store.lastReading?.sgv == 130)
        #expect(store.readings.map(\.sgv) == [130])
    }

    /// A dead host throws a transport error through the same path as an HTTP status: the error
    /// reaches the menu bar's ⚠ and the last reading stays up. The stub plays the dead host:
    /// every request is intercepted before a socket is opened, and an unknown host fails
    /// with a synthesized transport error.
    @Test func aTransportErrorReportsAndKeepsTheReading() async {
        let settings = Self.makeSettings()
        settings.baseURL = "https://unregistered-host.example"
        let store = ReadingStore(settings: settings, session: StubbedSite.session)
        store.lastReading = reading(110, minutesAgo: 5)

        await store.refresh()
        #expect(store.lastError == URLError(.cannotFindHost).localizedDescription)
        #expect(store.lastReading?.sgv == 110)
    }

    /// A user who opened the dropdown at 6 h and drags to 72 h depends on this branch to
    /// back-fill treatments for the whole widened window.
    @Test func wideningTheRangeFetchesTheMissingTreatments() async throws {
        let server = StubbedSite(json: """
            [{"_id":"t1","eventType":"Temp Basal","created_at":"2030-01-01T08:00:00.000Z",
              "duration":30,"rate":1,"absolute":1}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)

        await store.refreshTreatments(force: true)
        #expect(store.treatments.count == 1)

        settings.rangeHours = 24
        store.ensureHistoryCoverage()
        try await waitUntil("the widened treatments") {
            ReadingStore.covers(store.treatmentsWindowStart, from: .now.addingTimeInterval(-24 * 3600))
        }
    }

    /// The Pump tab asks the site even with every switch off; a nil answer (no pump on the site)
    /// must clear a stale status, not leave the previous site's rows up.
    @Test func aSiteWithoutPumpDataClearsAStaleStatus() async {
        let server = StubbedSite(json: """
            [{"created_at":"2030-01-01T11:55:00.000Z","uploader":{"battery":80}}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)
        store.pumpStatus = PumpStatus(date: .now, reservoir: 120)
        #expect(store.reportedPumpExtras.isEmpty)

        await store.refreshPumpStatus(force: true, evenIfSwitchedOff: true)
        #expect(store.pumpStatus == nil)
        #expect(store.reportedPumpExtras.isEmpty)
    }

    /// Both range sliders round through this binding; a switch to a stepped slider would draw
    /// tick marks and change macOS' rendering.
    @Test func sliderValueRoundsHalfUpAndSnapsToAnInt() {
        var hours = 6
        let slider = Binding<Int>(get: { hours }, set: { hours = $0 }).sliderValue
        #expect(slider.wrappedValue == 6)
        slider.wrappedValue = 24.4
        #expect(hours == 24)
        slider.wrappedValue = 24.6
        #expect(hours == 25)
    }

    /// The day form the stale note and the dropdown's age line rely on, pinned to English
    /// the way the other locale-following formats are pinned here.
    @Test func relativeNamesThePreviousDay() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var style = Date.AnchoredRelativeFormatStyle(anchor: yesterday, presentation: .named, unitsStyle: .wide)
        style.allowedFields = [.minute, .hour, .day]
        style.locale = Locale(identifier: "en_US")
        #expect(style.format(now) == "yesterday")
    }
}
