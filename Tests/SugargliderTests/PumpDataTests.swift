import Testing
import Foundation
import SwiftUI
@testable import Sugarglider

/// A `devicestatus` or `treatments` record as `JSONSerialization` hands it
/// over, numbers as `NSNumber` included, which is what the parsers really see.
func record(_ json: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

/// A full CamAPS FX device status, shaped like what that uploader sends. The
/// values and times are invented, like every fixture in this file.
let camapsRecord = """
    {"created_at":"2030-01-01T12:00:00.250Z","device":"camaps",
     "camaps":{"auto_mode":true,"boost":false,"ease_off":false,"delivery_rate":1.15,
               "glucose_mean_today_mmol":6.9,"glucose_mean_yesterday_mmol":8.1,
               "insulin_today":21.5,"insulin_yesterday":47.3,"target_mmol":6.0},
     "pump":{"battery":{"percent":65},"clock":"2030-01-01T11:55:00.250Z","reservoir":120,
             "iob":{"bolusiob":1.35,"iob":1.35,"timestamp":"2030-01-01T12:00:00.250Z"},
             "status":{"status":"Auto mode","timestamp":"2030-01-01T12:00:00.250Z"}}}
    """

// MARK: - Device status

extension SugargliderTests {
    @Test func pumpStatusReadsACamAPSRecord() throws {
        let status = try #require(PumpStatus(record: record(camapsRecord)))
        #expect(abs(status.date.timeIntervalSince1970 - 1_893_499_200.25) < 0.001)
        #expect(status.insulinOnBoard == 1.35)
        #expect(status.reservoir == 120)
        #expect(status.batteryPercent == 65)
        #expect(status.mode == .auto)
        #expect(status.deliveryRate == 1.15)
        #expect(status.insulinToday == 21.5)
        #expect(status.insulinYesterday == 47.3)
        // Stored in mg/dL like every other glucose value, from the mmol/L sent.
        #expect(abs(try #require(status.averageToday) - 124.2) < 0.001)
        #expect(abs(try #require(status.averageYesterday) - 145.8) < 0.001)
    }

    /// `NSNumber` casts to `Bool` whenever it holds 0 or 1, so a guard against
    /// JSON booleans in the number reader would silently drop these.
    @Test func pumpStatusKeepsZeroAndOne() throws {
        let status = try #require(PumpStatus(record: record("""
            {"created_at":"2030-01-01T12:00:00Z","pump":{"iob":{"iob":0},"reservoir":1,"battery":{"percent":0}}}
            """)))
        #expect(status.insulinOnBoard == 0)
        #expect(status.reservoir == 1)
        #expect(status.batteryPercent == 0)
    }

    /// Loop and the OpenAPS family don't put insulin on board in the pump
    /// block, and OpenAPS sends either an object or an array of forecast
    /// points, the first being now.
    @Test func pumpStatusFindsInsulinOnBoardWhereLoopsPutIt() throws {
        let loop = try #require(PumpStatus(record: record(
            #"{"created_at":"2030-01-01T12:00:00Z","loop":{"iob":{"iob":2.5}}}"#)))
        let object = try #require(PumpStatus(record: record(
            #"{"created_at":"2030-01-01T12:00:00Z","openaps":{"iob":{"iob":1.5}}}"#)))
        let array = try #require(PumpStatus(record: record(
            #"{"created_at":"2030-01-01T12:00:00Z","openaps":{"iob":[{"iob":0.5},{"iob":0.4}]}}"#)))
        #expect(loop.insulinOnBoard == 2.5)
        #expect(object.insulinOnBoard == 1.5)
        #expect(array.insulinOnBoard == 0.5)
    }

    @Test func pumpStatusNeedsADate() {
        #expect(PumpStatus(record: record(#"{"pump":{"reservoir":120}}"#)) == nil)
        #expect(PumpStatus(record: record(#"{"created_at":"yesterday","pump":{"reservoir":120}}"#)) == nil)
        // Epoch milliseconds stand in for a missing `created_at`.
        #expect(PumpStatus(record: record(#"{"mills":1893499200250,"pump":{"reservoir":120}}"#))?.reservoir == 120)
    }

    /// Flags win over the status text, which still supplies the end of a Boost
    /// or Ease-off. Without flags the text is the mode; without either, nil.
    @Test func modeFromFlagsAndStatusText() {
        func mode(_ auto: Bool?, _ boost: Bool?, _ easeOff: Bool?, _ text: String?) -> PumpStatus.Mode? {
            PumpStatus.mode(autoMode: auto, boost: boost, easeOff: easeOff, statusText: text)
        }
        #expect(mode(true, false, false, "Auto mode") == .auto)
        #expect(mode(false, false, false, "Auto mode aus") == .off)
        #expect(mode(true, true, false, "Boost bis 15:04") == .boost(until: "15:04"))
        #expect(mode(true, false, true, "Ease-off bis 8:30") == .easeOff(until: "8:30"))
        #expect(mode(true, true, false, nil) == .boost(until: nil))
        #expect(mode(nil, nil, nil, " normal ") == .other("normal"))
        #expect(mode(nil, nil, nil, "") == nil)
        #expect(mode(nil, nil, nil, nil) == nil)

        #expect(PumpStatus.Mode.boost(until: "15:04").label == "Boost until 15:04")
        #expect(PumpStatus.Mode.easeOff(until: nil).label == "Ease-off")
        #expect(PumpStatus.Mode.off.label == "Auto mode off")
    }

    /// Each field comes from the newest record that has it, but only within
    /// `mergeSpan`: a value from an uploader that went quiet hours ago must not
    /// sit next to fresh ones as if it were current.
    @Test func mergedFillsFieldsFromRecentRecordsOnly() throws {
        let now = Date()
        var newest = PumpStatus(date: now)
        newest.reservoir = 90
        var recent = PumpStatus(date: now.addingTimeInterval(-5 * 60))
        recent.reservoir = 91
        recent.insulinOnBoard = 1.5
        var old = PumpStatus(date: now.addingTimeInterval(-PumpStatus.mergeSpan - 60))
        old.batteryPercent = 50

        let merged = try #require(PumpStatus.merged([old, recent, newest]))
        #expect(merged.date == now)
        #expect(merged.reservoir == 90)         // newest wins
        #expect(merged.insulinOnBoard == 1.5)   // filled in from a recent record
        #expect(merged.batteryPercent == nil)   // too old to fill anything in
    }

    /// A record with nothing the dropdown shows (an uploader reporting only its
    /// phone battery, say) neither counts as the newest nor dates the result.
    @Test func mergedSkipsRecordsWithoutPumpData() throws {
        let now = Date()
        var pump = PumpStatus(date: now.addingTimeInterval(-60))
        pump.reservoir = 120
        let merged = try #require(PumpStatus.merged([PumpStatus(date: now), pump]))
        #expect(merged.date == pump.date)
        #expect(PumpStatus.merged([PumpStatus(date: now)]) == nil)
        #expect(PumpStatus.merged([]) == nil)
    }
}

// MARK: - Treatments

extension SugargliderTests {
    @Test func treatmentKindsTheChartDraws() throws {
        let temp = try #require(Treatment(record: record("""
            {"_id":"a","eventType":"Temp Basal","created_at":"2030-01-01T12:05:00.120Z",
             "absolute":1.2,"rate":1.2,"duration":30,"insulin":null}
            """)))
        #expect(temp.id == "a")
        #expect(temp.kind == .tempBasal(rate: 1.2, minutes: 30))

        let bolus = try #require(Treatment(record: record(
            #"{"_id":"b","eventType":"Correction Bolus","created_at":"2030-01-01T11:40:00Z","insulin":2}"#)))
        #expect(bolus.bolusUnits == 2)
        // Any treatment carrying insulin is a bolus, whatever the uploader calls it.
        let meal = try #require(Treatment(record: record(
            #"{"eventType":"Meal Bolus","created_at":"2030-01-01T11:40:00Z","insulin":4,"carbs":40}"#)))
        #expect(meal.bolusUnits == 4)

        let note = try #require(Treatment(record: record("""
            {"eventType":"Announcement","created_at":"2030-01-01T09:15:00.500Z",
             "notes":" CamAPS: Warnmeldung: Insulin im Reservoir niedrig ","isAnnouncement":true}
            """)))
        #expect(note.noteText == "CamAPS: Warnmeldung: Insulin im Reservoir niedrig")
    }

    @Test func treatmentsTheChartCantDrawAreDropped() {
        // Read separately, for the age next to the reservoir.
        #expect(Treatment(record: record(
            #"{"eventType":"Insulin Change","created_at":"2030-01-01T08:00:00Z","notes":"Reservoir 0 → 150 IE"}"#)) == nil)
        // Relative to a profile that isn't read.
        #expect(Treatment(record: record(
            #"{"eventType":"Temp Basal","created_at":"2030-01-01T08:00:00Z","percent":-50,"duration":30}"#)) == nil)
        #expect(Treatment(record: record(
            #"{"eventType":"Announcement","created_at":"2030-01-01T08:00:00Z","notes":"  "}"#)) == nil)
        #expect(Treatment(record: record(#"{"eventType":"Correction Bolus","insulin":1}"#)) == nil)   // no date
        #expect(Treatment(record: record(
            #"{"eventType":"Correction Bolus","created_at":"2030-01-01T08:00:00Z","insulin":0}"#)) == nil)
    }

    /// How some loops cancel a temp basal: no rate, no duration left.
    @Test func zeroDurationTempBasalIsACancel() throws {
        let cancel = try #require(Treatment(record: record(
            #"{"eventType":"Temp Basal","created_at":"2030-01-01T08:00:00Z","duration":0}"#)))
        #expect(cancel.kind == .tempBasal(rate: 0, minutes: 0))
    }

    @Test func nightscoutTimeReadsEveryFormSitesUse() throws {
        let expected = Date(timeIntervalSince1970: 1_893_499_200)
        #expect(NightscoutTime.date("2030-01-01T12:00:00Z") == expected)
        #expect(NightscoutTime.date("2030-01-01T14:00:00+02:00") == expected)
        let withMillis = try #require(NightscoutTime.date("2030-01-01T12:00:00.161Z"))
        #expect(abs(withMillis.timeIntervalSince(expected) - 0.161) < 0.001)
        #expect(NightscoutTime.date(NSNumber(value: 1_893_499_200_000)) == expected)
        #expect(NightscoutTime.date("garbage") == nil)
        #expect(NightscoutTime.date(nil) == nil)
        // Written the way Nightscout stores `created_at`, so its string
        // comparison in a `find[created_at]` filter lines up.
        #expect(NightscoutTime.string(withMillis) == "2030-01-01T12:00:00.161Z")
    }
}

// MARK: - Fetching

extension SugargliderTests {
    @Test func fetchPumpStatusMergesTheNewestRecords() async throws {
        let server = try LocalHTTPServer(json: """
            [\(camapsRecord),
             {"created_at":"2030-01-01T11:55:00Z","pump":{"reservoir":121}}]
            """)
        defer { server.stop() }
        let status = try #require(try await Nightscout.fetchPumpStatus(baseURL: server.baseURL, token: "t"))
        #expect(status.reservoir == 120)
        #expect(status.mode == .auto)
        let line = try #require(server.requestLines.first)
        #expect(line.contains("/api/v1/devicestatus.json"))
        #expect(line.contains("count=\(Nightscout.deviceStatusCount)"))
        #expect(line.contains("token=t"))
    }

    /// Most sites have only a CGM uploading, so no status is an answer, not an error.
    @Test func fetchPumpStatusOfASiteWithoutOneIsNil() async throws {
        let server = try LocalHTTPServer(json: #"[{"created_at":"2030-01-01T11:55:00Z","uploader":{"battery":80}}]"#)
        defer { server.stop() }
        #expect(try await Nightscout.fetchPumpStatus(baseURL: server.baseURL, token: "") == nil)
    }

    @Test func fetchTreatmentsFiltersByDateAndSortsOldestFirst() async throws {
        let server = try LocalHTTPServer(json: """
            [{"_id":"2","eventType":"Correction Bolus","created_at":"2030-01-01T11:40:00Z","insulin":2},
             {"_id":"x","eventType":"Insulin Change","created_at":"2030-01-01T11:00:00Z"},
             {"_id":"1","eventType":"Temp Basal","created_at":"2030-01-01T11:35:00Z","absolute":1,"duration":30}]
            """)
        defer { server.stop() }
        let since = try #require(NightscoutTime.date("2030-01-01T06:00:00.000Z"))
        let treatments = try await Nightscout.fetchTreatments(since: since, count: 500,
                                                              baseURL: server.baseURL, token: "")
        #expect(treatments.map(\.id) == ["1", "2"])
        let line = try #require(server.requestLines.first)
        #expect(line.contains("/api/v1/treatments.json"))
        #expect(line.contains("created_at%5D%5B$gte%5D=2030-01-01T06:00:00.000Z"))
        #expect(line.contains("count=500"))
    }

    @Test func fetchTreatmentsRejectsAnythingButAnArray() async throws {
        let server = try LocalHTTPServer(json: #"{"status":401}"#)
        defer { server.stop() }
        await #expect(throws: NightscoutError.self) {
            try await Nightscout.fetchTreatments(since: Date(), count: 10, baseURL: server.baseURL, token: "")
        }
    }

    @Test func fetchLatestEventAsksForThatEventOnly() async throws {
        let server = try LocalHTTPServer(json: #"[{"eventType":"Insulin Change","created_at":"2030-01-01T08:00:00.128Z"}]"#)
        defer { server.stop() }
        let date = try await Nightscout.fetchLatestEvent("Insulin Change", since: Date(timeIntervalSince1970: 0),
                                                         baseURL: server.baseURL, token: "")
        #expect(date == NightscoutTime.date("2030-01-01T08:00:00.128Z"))
        let line = try #require(server.requestLines.first)
        #expect(line.contains("eventType%5D=Insulin%20Change"))
        #expect(line.contains("count=1"))

        let empty = try LocalHTTPServer(json: "[]")
        defer { empty.stop() }
        #expect(try await Nightscout.fetchLatestEvent("Insulin Change", since: Date(),
                                                      baseURL: empty.baseURL, token: "") == nil)
    }
}

// MARK: - Delivery steps

extension SugargliderTests {
    private func temp(_ rate: Double, minutes: Double, at offset: Double, from base: Date) -> Treatment {
        Treatment(id: "t\(offset)", date: base.addingTimeInterval(offset * 60),
                  kind: .tempBasal(rate: rate, minutes: minutes))
    }

    /// Each temp basal runs until the next one starts or its duration is up,
    /// and an uncovered stretch stays a gap.
    @Test func deliveryStepsEndAtTheNextOneOrTheirDuration() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let temps = [temp(1, minutes: 30, at: 0, from: base),
                     temp(2, minutes: 30, at: 10, from: base),     // cuts the first short
                     temp(3, minutes: 30, at: 60, from: base)]     // after a 20 minute gap
        let steps = ChartMath.deliverySteps(temps, from: base, to: base.addingTimeInterval(80 * 60))
        #expect(steps.map(\.rate) == [1, 2, 3])
        #expect(steps.map { $0.start.timeIntervalSince(base) / 60 } == [0, 10, 60])
        #expect(steps.map { $0.end.timeIntervalSince(base) / 60 } == [10, 40, 80])   // the last one clipped

        let runs = ChartMath.contiguousRuns(steps)
        #expect(runs.map(\.count) == [2, 1])
        #expect(ChartMath.rate(at: base.addingTimeInterval(15 * 60), in: steps) == 2)
        #expect(ChartMath.rate(at: base.addingTimeInterval(50 * 60), in: steps) == nil)   // the gap
    }

    @Test func deliveryStepsStartAtTheWindow() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let steps = ChartMath.deliverySteps([temp(1, minutes: 30, at: -20, from: base)],
                                            from: base, to: base.addingTimeInterval(3600))
        #expect(steps == [ChartMath.DeliveryStep(start: base, end: base.addingTimeInterval(10 * 60), rate: 1)])
    }

    @Test func zeroDurationTempBasalEndsTheOneBefore() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let steps = ChartMath.deliverySteps([temp(1.5, minutes: 30, at: 0, from: base),
                                             temp(0, minutes: 0, at: 5, from: base)],
                                            from: base, to: base.addingTimeInterval(3600))
        #expect(steps.count == 1)
        #expect(steps.first?.end == base.addingTimeInterval(5 * 60))
    }

    @Test func nearestIndexWorksOnBareDates() {
        let base = Date()
        let dates = [0.0, 300.0].map { base.addingTimeInterval($0) }
        func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(base)) }
        #expect(ChartMath.nearestIndex(to: 290, x: x, dates: dates, maxDistance: 24) == 1)
        #expect(ChartMath.nearestIndex(to: 150, x: x, dates: dates, maxDistance: 24) == nil)
        #expect(ChartMath.nearestIndex(to: 0, x: x, dates: [], maxDistance: 24) == nil)
    }
}

// MARK: - Store

extension SugargliderTests {
    /// The first fetch covers the window plus the lookback for a temp basal
    /// already running at its left edge; later ones reach back an overlap past
    /// the newest cached treatment, because treatments arrive out of order.
    @Test func treatmentsAreFetchedForTheWindowThenWithAnOverlap() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-6 * 3600)
        let full = ReadingStore.treatmentsSince(windowStart: windowStart, covered: false, newestCached: nil)
        #expect(full == windowStart.addingTimeInterval(-ReadingStore.tempBasalLookback))

        let newest = now.addingTimeInterval(-300)
        let topUp = ReadingStore.treatmentsSince(windowStart: windowStart, covered: true, newestCached: newest)
        #expect(topUp == newest.addingTimeInterval(-ReadingStore.treatmentOverlap))

        // Covered but nothing cached: the window again, never an unfiltered request.
        #expect(ReadingStore.treatmentsSince(windowStart: windowStart, covered: true, newestCached: nil) == full)
    }

    @Test func mergedTreatmentsReplaceByIDAndDropTheVeryOld() {
        let now = Date()
        let old = Treatment(id: "old", date: now.addingTimeInterval(-80 * 3600), kind: .bolus(units: 1))
        let first = Treatment(id: "a", date: now.addingTimeInterval(-600), kind: .bolus(units: 1))
        let edited = Treatment(id: "a", date: now.addingTimeInterval(-600), kind: .bolus(units: 1.5))
        let later = Treatment(id: "b", date: now.addingTimeInterval(-60), kind: .note("hello"))
        let merged = ReadingStore.merged([old, first], with: [later, edited], now: now)
        #expect(merged.map(\.id) == ["a", "b"])
        #expect(merged.first?.bolusUnits == 1.5)
    }

    @Test func reconnectClearsPumpData() {
        let store = ReadingStore(settings: Self.makeSettings())
        store.pumpStatus = PumpStatus(date: Date())
        store.treatments = [Treatment(id: "a", date: Date(), kind: .bolus(units: 1))]
        store.reservoirChanged = Date()
        store.batteryChanged = Date()
        store.reconnect()
        #expect(store.pumpStatus == nil)
        #expect(store.treatments.isEmpty)
        #expect(store.reservoirChanged == nil)
        #expect(store.batteryChanged == nil)
        #expect(store.treatmentsWindowStart == nil)
    }

    /// Each part is fetched only while something that shows it is switched
    /// on, so a CGM-only setup that turned it all off pays nothing for it.
    @Test func nothingIsFetchedForSwitchesThatAreOff() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let flags: [ReferenceWritableKeyPath<AppSettings, Bool>] = [
            \.showActiveInsulin, \.showPumpMode, \.showDeliveryRate, \.showReservoir, \.showPumpBattery,
            \.showChangeAge, \.showDailyInsulin, \.showAverageGlucose,
            \.chartShowsBoluses, \.chartShowsDeliveryRate, \.chartShowsAnnouncements,
        ]
        for flag in flags { settings[keyPath: flag] = false }
        ReadingStore(settings: settings).refreshDetails(force: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.requestLines.isEmpty)
    }

    @Test func refreshDetailsFetchesThePumpStatus() async throws {
        let server = try LocalHTTPServer(json: "[\(camapsRecord)]")
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)
        store.refreshDetails(force: true)
        try await waitUntil("the pump status") { store.pumpStatus != nil }
        #expect(store.pumpStatus?.reservoir == 120)
        #expect(server.requestLines.contains { $0.contains("/api/v1/devicestatus.json") })
    }

    @Test func refreshTreatmentsCoversTheWindowAndMerges() async throws {
        let created = NightscoutTime.string(Date().addingTimeInterval(-600))
        let server = try LocalHTTPServer(json: """
            [{"_id":"b1","eventType":"Correction Bolus","created_at":"\(created)","insulin":2.5}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)

        store.refreshTreatments(force: true)
        try await waitUntil("the treatments") { !store.treatments.isEmpty }
        #expect(store.treatments.map(\.id) == ["b1"])
        let windowStart = try #require(store.treatmentsWindowStart)
        let since = NightscoutTime.string(windowStart.addingTimeInterval(-ReadingStore.tempBasalLookback))
        #expect(server.requestLines[0].contains("$gte%5D=\(since)"))

        // Covered now, so the top-up reaches back only an overlap past the
        // newest cached treatment. (Its response is the same record again; the
        // dedupe is `mergedTreatmentsReplaceByIDAndDropTheVeryOld`'s to check.)
        store.refreshTreatments(force: true)
        try await waitUntil("the top-up") { server.requestLines.count == 2 }
        let newest = try #require(store.treatments.last?.date)
        let overlap = NightscoutTime.string(newest.addingTimeInterval(-ReadingStore.treatmentOverlap))
        #expect(server.requestLines[1].contains("$gte%5D=\(overlap)"))
    }
}

// MARK: - What the dropdown shows

extension SugargliderTests {
    private func fullStatus() -> PumpStatus {
        var s = PumpStatus(date: Date())
        s.insulinOnBoard = 1.35
        s.reservoir = 120
        s.batteryPercent = 65
        s.mode = .auto
        s.deliveryRate = 1.15
        s.insulinToday = 21.5
        s.insulinYesterday = 47.3
        s.averageToday = 124.2
        s.averageYesterday = 145.8
        return s
    }

    /// The mode labels the rate when both are on, which saves a row that
    /// would mostly just say "Auto mode".
    @Test func detailRowsByDefault() {
        let rows = PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings())
        #expect(rows.map(\.label) == ["Active insulin", "Auto mode", "Reservoir", "Pump battery"])
        #expect(rows.map(\.value) == ["1.35 U", "1.15 U/h", "120 U", "65%"])
        #expect(rows.allSatisfy { $0.note == nil })
    }

    @Test func detailRowsSplitModeAndRateWhenOnlyOneIsOn() {
        let settings = Self.makeSettings()
        settings.showDeliveryRate = false
        #expect(PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                     settings: settings).contains(.init(label: "Mode", value: "Auto mode")))
        settings.showDeliveryRate = true
        settings.showPumpMode = false
        #expect(PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                     settings: settings).contains(.init(label: "Delivery rate", value: "1.15 U/h")))
    }

    /// An uploader's own status text can say anything, so it never becomes the
    /// label of the rate.
    @Test func statusTextModeKeepsItsOwnRow() {
        var status = fullStatus()
        status.mode = .other("normal")
        let rows = PumpDetailsView.rows(status: status, reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings())
        #expect(rows.contains(.init(label: "Mode", value: "normal")))
        #expect(rows.contains(.init(label: "Delivery rate", value: "1.15 U/h")))
    }

    @Test func detailRowsShowOnlyWhatTheSiteReports() {
        var status = PumpStatus(date: Date())
        status.reservoir = 8.4
        let rows = PumpDetailsView.rows(status: status, reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings())
        #expect(rows == [.init(label: "Reservoir", value: "8.4 U")])
        #expect(PumpDetailsView.rows(status: nil, reservoirChanged: nil, batteryChanged: nil,
                                     settings: Self.makeSettings()).isEmpty)
        #expect(PumpDetailsView.dailyRows(status: status, settings: Self.makeSettings()).isEmpty)
    }

    @Test func changeAgesFollowTheirSwitch() {
        let now = Date()
        let settings = Self.makeSettings()
        let changed = now.addingTimeInterval(-25 * 3600)
        func reservoirRow() -> PumpDetailsView.Row? {
            PumpDetailsView.rows(status: fullStatus(), reservoirChanged: changed, batteryChanged: nil,
                                 settings: settings, now: now).first { $0.label == "Reservoir" }
        }
        #expect(reservoirRow()?.note == nil)        // off by default
        settings.showChangeAge = true
        #expect(reservoirRow()?.note == "1d 1h")
        #expect(reservoirRow()?.help == "Reservoir changed 1d 1h ago")
    }

    @Test func dailyRowsUseTheDisplayUnit() {
        let settings = Self.makeSettings()
        settings.showDailyInsulin = true
        settings.showAverageGlucose = true
        settings.units = .mmol
        #expect(PumpDetailsView.dailyRows(status: fullStatus(), settings: settings) == [
            .init(label: "Total insulin", today: "21.5 U", yesterday: "47.3 U"),
            .init(label: "Average glucose", today: "6.9", yesterday: "8.1"),
        ])
        settings.units = .mgdl
        #expect(PumpDetailsView.dailyRows(status: fullStatus(), settings: settings).last
                == .init(label: "Average glucose", today: "124", yesterday: "146"))
    }

    /// The uploader can stop sending device statuses while glucose still flows,
    /// and nothing else would show it.
    @Test func staleNoteOnlyPastTheStaleDelay() {
        let settings = Self.makeSettings()
        let now = Date()
        #expect(PumpDetailsView.staleNote(status: PumpStatus(date: now.addingTimeInterval(-5 * 60)),
                                          settings: settings, now: now) == nil)
        #expect(PumpDetailsView.staleNote(status: PumpStatus(date: now.addingTimeInterval(-40 * 60)),
                                          settings: settings, now: now) == "Pump data from 40 min ago")
    }

    @Test func pumpFormatsUseADotAndFixedDecimals() {
        #expect(PumpFormat.insulin(0) == "0.00 U")
        #expect(PumpFormat.rate(2.4) == "2.40 U/h")
        #expect(PumpFormat.reservoir(150) == "150 U")
        #expect(PumpFormat.battery(65) == "65%")
        #expect(PumpFormat.dailyInsulin(47.3) == "47.3 U")
        #expect(PumpFormat.bolus(1) == "1.0 U")
        #expect(PumpFormat.bolus(0.05) == "0.05 U")
        let now = Date()
        // Typed explicitly: Swift 6.0 can't infer a literal that mixes 5.0 and 5 * 60.
        let minutesAgo: [TimeInterval] = [5, 60, 5 * 60, 24 * 60, 49 * 60]
        let ages = minutesAgo.map { PumpFormat.age(since: now.addingTimeInterval(-$0 * 60), now: now) }
        #expect(ages == ["5m", "1h", "5h", "1d", "2d 1h"])
        #expect(PumpFormat.age(since: now.addingTimeInterval(60), now: now) == "0m")   // clock skew
    }
}

// MARK: - Settings

extension SugargliderTests {
    /// The at-a-glance values and boluses are on out of the box; totals and the
    /// busier chart layers are opt-in.
    @Test func pumpSwitchDefaults() {
        let s = Self.makeSettings()
        #expect(s.showActiveInsulin && s.showPumpMode && s.showDeliveryRate && s.showReservoir && s.showPumpBattery)
        #expect(s.chartShowsBoluses)
        #expect(!s.showChangeAge && !s.showDailyInsulin && !s.showAverageGlucose)
        #expect(!s.chartShowsDeliveryRate && !s.chartShowsAnnouncements)
    }

    /// Several of these default to true, which is exactly the case
    /// `bool(forKey:)` gets wrong on reload.
    @Test func pumpSwitchesRoundTrip() {
        let defaults = Self.makeDefaults()
        let s = Self.makeSettings(defaults: defaults)
        let flags: [ReferenceWritableKeyPath<AppSettings, Bool>] = [
            \.showActiveInsulin, \.showPumpMode, \.showDeliveryRate, \.showReservoir, \.showPumpBattery,
            \.showChangeAge, \.showDailyInsulin, \.showAverageGlucose,
            \.chartShowsBoluses, \.chartShowsDeliveryRate, \.chartShowsAnnouncements,
        ]
        for flag in flags { s[keyPath: flag].toggle() }
        let reloaded = Self.makeSettings(defaults: defaults)
        for flag in flags { #expect(reloaded[keyPath: flag] == s[keyPath: flag]) }
    }

    @Test func fetchNeedsFollowTheSwitches() {
        let s = Self.makeSettings()
        #expect(s.needsPumpStatus && s.needsTreatments && !s.needsChangeDates)
        s.showChangeAge = true
        #expect(s.needsChangeDates)
        s.showReservoir = false
        s.showPumpBattery = false
        #expect(!s.needsChangeDates)                 // nothing to put the age next to
        s.chartShowsBoluses = false
        #expect(!s.needsTreatments)
        let rows: [ReferenceWritableKeyPath<AppSettings, Bool>] = [\.showActiveInsulin, \.showPumpMode, \.showDeliveryRate]
        for flag in rows { s[keyPath: flag] = false }
        #expect(!s.needsPumpStatus)
        s.showAverageGlucose = true
        #expect(s.needsPumpStatus)
    }
}

// MARK: - Chart layers

extension SugargliderTests {
    /// The lane is there only with something switched on to draw in it, and
    /// is decided on the whole cache so a range drag can't make the chart jump.
    @Test func insulinLaneNeedsSomethingToDraw() {
        let s = Self.makeSettings()
        let bolus = Treatment(id: "b", date: Date().addingTimeInterval(-50 * 3600), kind: .bolus(units: 1))
        let tempBasal = Treatment(id: "t", date: Date(), kind: .tempBasal(rate: 1, minutes: 30))
        #expect(ChartCanvas.laneSpace(for: [], settings: s) == 0)
        #expect(ChartCanvas.laneSpace(for: [bolus], settings: s) == ChartCanvas.laneHeight)   // outside 6h, still counts
        #expect(ChartCanvas.laneSpace(for: [tempBasal], settings: s) == 0)                    // rate layer is off
        s.chartShowsDeliveryRate = true
        #expect(ChartCanvas.laneSpace(for: [tempBasal], settings: s) == ChartCanvas.laneHeight)
        s.chartShowsBoluses = false
        #expect(ChartCanvas.laneSpace(for: [bolus], settings: s) == 0)
    }

    @Test func longAnnouncementsAreClippedForThePill() {
        #expect(ChartCanvas.clipped("short") == "short")
        let long = String(repeating: "a", count: 200)
        #expect(ChartCanvas.clipped(long).count == 160)
        #expect(ChartCanvas.clipped(long).hasSuffix("…"))
    }

    @Test func rendersEveryPumpLayerWithoutCrash() {
        let s = Self.makeSettings()
        s.chartShowsDeliveryRate = true
        s.chartShowsAnnouncements = true
        s.chartBackgroundEnabled = true
        let now = Date()
        let readings = (0..<60).map { reading(100 + $0, minutesAgo: Double(59 - $0) * 5, from: now) }
        let treatments = [
            Treatment(id: "t1", date: now.addingTimeInterval(-4 * 3600), kind: .tempBasal(rate: 0.5, minutes: 30)),
            Treatment(id: "t2", date: now.addingTimeInterval(-3.8 * 3600), kind: .tempBasal(rate: 2.5, minutes: 30)),
            Treatment(id: "t3", date: now.addingTimeInterval(-3600), kind: .tempBasal(rate: 0, minutes: 30)),
            Treatment(id: "b1", date: now.addingTimeInterval(-2 * 3600), kind: .bolus(units: 3.5)),
            Treatment(id: "n1", date: now.addingTimeInterval(-1.5 * 3600), kind: .note("CamAPS: Hoher Wert")),
        ]
        let chart = ChartCanvas(readings: readings, rangeHours: 6, settings: s, treatments: treatments)
        let height = 160 + ChartCanvas.laneSpace(for: treatments, settings: s)
        let renderer = ImageRenderer(content: chart.frame(width: 280, height: height))
        renderer.scale = 1
        #expect(renderer.cgImage != nil)
    }
}
