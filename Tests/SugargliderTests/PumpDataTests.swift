import Testing
import Foundation
import SwiftUI
@testable import Sugarglider

/// Parsed through `JSONSerialization` so numbers arrive as `NSNumber`, as they do from a server.
private func record(_ json: String) -> [String: Any] {
    guard let record = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        Issue.record("Not a JSON object: \(json)")
        return [:]
    }
    return record
}

private let camapsRecord = """
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
        #expect(abs(try #require(status.averageToday) - 6.9 * 18) < 0.001)
        #expect(abs(try #require(status.averageYesterday) - 8.1 * 18) < 0.001)
    }

    /// A NaN average would trap in the dropdown's `Int(mgdl.rounded())`.
    @Test func pumpStatusReadsNumbersInStringsButNoNonFiniteOnes() throws {
        let status = try #require(PumpStatus(record: record("""
            {"created_at":"2030-01-01T12:00:00Z",
             "camaps":{"glucose_mean_today_mmol":"nan","delivery_rate":"inf","insulin_today":" 21.5 "}}
            """)))
        #expect(status.averageToday == nil)
        #expect(status.deliveryRate == nil)
        #expect(status.insulinToday == 21.5)
    }

    /// `NSNumber` casts to `Bool` when it holds 0 or 1, so an `is Bool` guard would drop these.
    @Test func pumpStatusKeepsZeroAndOne() throws {
        let status = try #require(PumpStatus(record: record("""
            {"created_at":"2030-01-01T12:00:00Z","pump":{"iob":{"iob":0},"reservoir":1,"battery":{"percent":0}}}
            """)))
        #expect(status.insulinOnBoard == 0)
        #expect(status.reservoir == 1)
        #expect(status.batteryPercent == 0)
    }

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

    @Test func pumpStatusIsDatedByCreatedAtOrMills() {
        #expect(PumpStatus(record: record(#"{"pump":{"reservoir":120}}"#)) == nil)
        #expect(PumpStatus(record: record(#"{"created_at":"yesterday","pump":{"reservoir":120}}"#)) == nil)
        #expect(PumpStatus(record: record(#"{"mills":1893499200250,"pump":{"reservoir":120}}"#))?.reservoir == 120)
    }

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
    }

    @Test(arguments: [
        (PumpStatus.Mode.auto, "Auto mode"), (.off, "Auto mode off"),
        (.boost(until: "15:04"), "Boost until 15:04"), (.easeOff(until: nil), "Ease-off"),
        (.other("normal"), "normal"),
    ])
    func modeLabel(mode: PumpStatus.Mode, label: String) {
        #expect(mode.label == label)
    }

    @Test func mergedFillsFieldsFromRecentRecordsOnly() throws {
        let now = Date.now
        let newest = PumpStatus(date: now, reservoir: 90)
        let recent = PumpStatus(date: now.addingTimeInterval(-5 * 60), insulinOnBoard: 1.5, reservoir: 91)
        let old = PumpStatus(date: now.addingTimeInterval(-PumpStatus.mergeSpan - 60), batteryPercent: 50)

        let merged = try #require(PumpStatus.merged([old, recent, newest]))
        #expect(merged.date == now)
        #expect(merged.reservoir == 90)
        #expect(merged.insulinOnBoard == 1.5)
        #expect(merged.batteryPercent == nil)
    }

    @Test func mergedSkipsRecordsWithoutPumpData() throws {
        let now = Date.now
        let pump = PumpStatus(date: now.addingTimeInterval(-60), reservoir: 120)
        let merged = try #require(PumpStatus.merged([PumpStatus(date: now), pump]))
        #expect(merged.date == pump.date)
        #expect(PumpStatus.merged([PumpStatus(date: now)]) == nil)
        #expect(PumpStatus.merged([]) == nil)
    }

    @Test func extrasAreTheValuesOnlySomeUploadersSend() throws {
        #expect(try #require(PumpStatus(record: record(camapsRecord))).extras == Set(PumpStatus.Extra.allCases))
        let standard = try #require(PumpStatus(record: record("""
            {"created_at":"2030-01-01T12:00:00Z","pump":{"iob":{"iob":1},"reservoir":120,"battery":{"percent":65}}}
            """)))
        #expect(standard.extras.isEmpty)
        let statusText = try #require(PumpStatus(record: record(
            #"{"created_at":"2030-01-01T12:00:00Z","pump":{"status":{"status":"normal"}}}"#)))
        #expect(statusText.extras == [.mode])
        #expect(PumpStatus(date: .now, insulinYesterday: 47.3, averageToday: 124).extras == [.dailyInsulin, .averageGlucose])
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
        // Any treatment carrying insulin is a bolus, whatever its event type.
        let meal = try #require(Treatment(record: record(
            #"{"eventType":"Meal Bolus","created_at":"2030-01-01T11:40:00Z","insulin":4,"carbs":40}"#)))
        #expect(meal.bolusUnits == 4)

        let note = try #require(Treatment(record: record("""
            {"eventType":"Announcement","created_at":"2030-01-01T09:15:00.500Z",
             "notes":" CamAPS: Warnmeldung: Insulin im Reservoir niedrig ","isAnnouncement":true}
            """)))
        #expect(note.noteText == "CamAPS: Warnmeldung: Insulin im Reservoir niedrig")
    }

    @Test(arguments: [
        #"{"eventType":"Insulin Change","created_at":"2030-01-01T08:00:00Z","notes":"Reservoir 0 → 150 IE"}"#,
        #"{"eventType":"Temp Basal","created_at":"2030-01-01T08:00:00Z","percent":-50,"duration":30}"#,
        #"{"eventType":"Announcement","created_at":"2030-01-01T08:00:00Z","notes":"  "}"#,
        #"{"eventType":"Correction Bolus","insulin":1}"#,
        #"{"eventType":"Correction Bolus","created_at":"2030-01-01T08:00:00Z","insulin":0}"#,
    ])
    func treatmentsTheChartCantDrawAreDropped(json: String) {
        #expect(Treatment(record: record(json)) == nil)
    }

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
    }

    @Test func nightscoutTimeWritesTheFormCreatedAtIsStoredIn() throws {
        let withMillis = try #require(NightscoutTime.date("2030-01-01T12:00:00.161Z"))
        #expect(NightscoutTime.string(withMillis) == "2030-01-01T12:00:00.161Z")
        #expect(NightscoutTime.string(Date(timeIntervalSince1970: 1_893_499_200)) == "2030-01-01T12:00:00.000Z")
    }
}

// MARK: - Fetching

extension SugargliderTests {
    @Test func fetchPumpStatusMergesTheNewestRecords() async throws {
        let server = StubbedSite(json: """
            [\(camapsRecord),
             {"created_at":"2030-01-01T11:55:00Z","pump":{"reservoir":121}}]
            """)
        let status = try #require(try await server.nightscout(token: "t").pumpStatus())
        #expect(status.reservoir == 120)
        #expect(status.mode == .auto)
        let line = try #require(server.requests.first)
        #expect(line.contains("/api/v1/devicestatus.json"))
        #expect(line.contains("count=\(Nightscout.deviceStatusCount)"))
        #expect(line.contains("token=t"))
    }

    @Test func fetchPumpStatusOfASiteWithoutOneIsNil() async throws {
        let server = StubbedSite(json: #"[{"created_at":"2030-01-01T11:55:00Z","uploader":{"battery":80}}]"#)
        #expect(try await server.nightscout().pumpStatus() == nil)
    }

    @Test func fetchTreatmentsFiltersByDateAndSortsOldestFirst() async throws {
        let server = StubbedSite(json: """
            [{"_id":"2","eventType":"Correction Bolus","created_at":"2030-01-01T11:40:00Z","insulin":2},
             {"_id":"x","eventType":"Insulin Change","created_at":"2030-01-01T11:00:00Z"},
             {"_id":"1","eventType":"Temp Basal","created_at":"2030-01-01T11:35:00Z","absolute":1,"duration":30}]
            """)
        let since = try #require(NightscoutTime.date("2030-01-01T06:00:00.000Z"))
        let treatments = try await server.nightscout().treatments(count: 500, since: since)
        #expect(treatments.map(\.id) == ["1", "2"])
        let line = try #require(server.requests.first)
        #expect(line.contains("/api/v1/treatments.json"))
        #expect(line.contains("created_at%5D%5B$gte%5D=2030-01-01T06:00:00.000Z"))
        #expect(line.contains("count=500"))
    }

    @Test func fetchTreatmentsRejectsAnythingButAnArray() async throws {
        let server = StubbedSite(json: #"{"status":401}"#)
        await #expect(throws: NightscoutError.self) {
            try await server.nightscout().treatments(count: 10, since: .now)
        }
    }

    @Test func fetchLatestEventAsksForThatEventOnly() async throws {
        let server = StubbedSite(json: #"[{"eventType":"Insulin Change","created_at":"2030-01-01T08:00:00.128Z"}]"#)
        let date = try await server.nightscout().latestEvent("Insulin Change", since: Date(timeIntervalSince1970: 0))
        #expect(date == NightscoutTime.date("2030-01-01T08:00:00.128Z"))
        let line = try #require(server.requests.first)
        #expect(line.contains("eventType%5D=Insulin%20Change"))
        // Without a date filter Nightscout searches only the last two days.
        #expect(line.contains("created_at%5D%5B$gte%5D=1970-01-01T00:00:00.000Z"))
        #expect(line.contains("count=1"))

        let empty = StubbedSite(json: "[]")
        #expect(try await empty.nightscout().latestEvent("Insulin Change", since: .now) == nil)
    }
}

// MARK: - Delivery steps

extension SugargliderTests {
    private func temp(_ rate: Double, minutes: Double, at offset: Double, from base: Date) -> Treatment {
        Treatment(id: "t\(offset)", date: base.addingTimeInterval(offset * 60),
                  kind: .tempBasal(rate: rate, minutes: minutes))
    }

    @Test func deliveryStepsEndAtTheNextOneOrTheirDuration() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let temps = [temp(1, minutes: 30, at: 0, from: base),
                     temp(2, minutes: 30, at: 10, from: base),
                     temp(3, minutes: 30, at: 60, from: base)]
        let steps = ChartMath.deliverySteps(temps, from: base, to: base.addingTimeInterval(80 * 60))
        #expect(steps.map(\.rate) == [1, 2, 3])
        #expect(steps.map { $0.start.timeIntervalSince(base) / 60 } == [0, 10, 60])
        #expect(steps.map { $0.end.timeIntervalSince(base) / 60 } == [10, 40, 80])

        let runs = ChartMath.contiguousRuns(steps)
        #expect(runs.map(\.count) == [2, 1])
        #expect(ChartMath.rate(at: base.addingTimeInterval(15 * 60), in: steps) == 2)
        #expect(ChartMath.rate(at: base.addingTimeInterval(50 * 60), in: steps) == nil)
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
}

// MARK: - Store

extension SugargliderTests {
    private static var pumpSwitches: [ReferenceWritableKeyPath<AppSettings, Bool>] {
        [\.showActiveInsulin, \.showPumpMode, \.showDeliveryRate, \.showReservoir, \.showPumpBattery,
         \.showChangeAge, \.showDailyInsulin, \.showAverageGlucose,
         \.chartShowsBoluses, \.chartShowsDeliveryRate, \.chartShowsAnnouncements]
    }

    @Test func treatmentsAreFetchedForTheWindowThenWithAnOverlap() {
        let now = Date.now
        let windowStart = now.addingTimeInterval(-6 * 3600)
        let full = ReadingStore.treatmentsSince(windowStart: windowStart, covered: false, newestCached: nil)
        #expect(full == windowStart.addingTimeInterval(-ReadingStore.tempBasalLookback))

        let newest = now.addingTimeInterval(-300)
        let topUp = ReadingStore.treatmentsSince(windowStart: windowStart, covered: true, newestCached: newest)
        #expect(topUp == newest.addingTimeInterval(-ReadingStore.treatmentOverlap))

        // Covered but empty: the window again, never an unfiltered request.
        #expect(ReadingStore.treatmentsSince(windowStart: windowStart, covered: true, newestCached: nil) == full)
    }

    @Test func mergedTreatmentsReplaceByIDAndDropTheVeryOld() {
        let now = Date.now
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
        store.pumpStatus = PumpStatus(date: .now, mode: .auto)
        store.treatments = [Treatment(id: "a", date: .now, kind: .bolus(units: 1))]
        store.reservoirChanged = .now
        store.batteryChanged = .now
        store.reconnect()
        #expect(store.pumpStatus == nil)
        #expect(store.reportedPumpExtras.isEmpty)
        #expect(store.treatments.isEmpty)
        #expect(store.reservoirChanged == nil)
        #expect(store.batteryChanged == nil)
        #expect(store.treatmentsWindowStart == nil)
    }

    @Test func nothingIsFetchedForSwitchesThatAreOff() async throws {
        let server = StubbedSite(json: "[]")
        let settings = Self.makeSettings()
                for flag in Self.pumpSwitches { settings[keyPath: flag] = false }
        await server.store(settings).refreshDetails(force: true)
        #expect(server.requests.isEmpty)
    }

    @Test func reportedExtrasOutlastAStatusWithoutThem() {
        let store = ReadingStore(settings: Self.makeSettings())
        store.pumpStatus = PumpStatus(date: .now, mode: .auto, insulinToday: 21.5)
        store.pumpStatus = PumpStatus(date: .now, reservoir: 120)
        store.pumpStatus = nil
        #expect(store.reportedPumpExtras == [.mode, .dailyInsulin])
    }

    @Test func thePumpTabAsksTheSiteEvenWithEverySwitchOff() async throws {
        let server = StubbedSite(json: "[\(camapsRecord)]")
        let settings = Self.makeSettings()
        for flag in Self.pumpSwitches { settings[keyPath: flag] = false }
        let store = server.store(settings)
        await store.refreshPumpStatus(force: false)
        #expect(server.requests.isEmpty)
        await store.refreshPumpStatus(force: false, evenIfSwitchedOff: true)
        #expect(store.reportedPumpExtras == Set(PumpStatus.Extra.allCases))
    }

    @Test func refreshDetailsFetchesThePumpStatus() async throws {
        let server = StubbedSite(json: "[\(camapsRecord)]")
        let settings = Self.makeSettings()
        let store = server.store(settings)
        await store.refreshDetails(force: true)
        #expect(store.pumpStatus?.reservoir == 120)
        #expect(server.requests.contains { $0.contains("/api/v1/devicestatus.json") })
    }

    @Test func refreshTreatmentsFetchesTheWindowThenTopsUp() async throws {
        let created = NightscoutTime.string(Date.now.addingTimeInterval(-600))
        let server = StubbedSite(json: """
            [{"_id":"b1","eventType":"Correction Bolus","created_at":"\(created)","insulin":2.5}]
            """)
        let settings = Self.makeSettings()
        let store = server.store(settings)

        await store.refreshTreatments(force: true)
        #expect(store.treatments.map(\.id) == ["b1"])
        let windowStart = try #require(store.treatmentsWindowStart)
        let since = NightscoutTime.string(windowStart.addingTimeInterval(-ReadingStore.tempBasalLookback))
        #expect(server.requests[0].contains("$gte%5D=\(since)"))

        await store.refreshTreatments(force: true)
        #expect(server.requests.count == 2)
        let newest = try #require(store.treatments.last?.date)
        let overlap = NightscoutTime.string(newest.addingTimeInterval(-ReadingStore.treatmentOverlap))
        #expect(server.requests[1].contains("$gte%5D=\(overlap)"))
    }
}

// MARK: - What the dropdown shows

extension SugargliderTests {
    private func fullStatus() -> PumpStatus {
        PumpStatus(date: .now, insulinOnBoard: 1.35, reservoir: 120, batteryPercent: 65, mode: .auto,
                   deliveryRate: 1.15, insulinToday: 21.5, insulinYesterday: 47.3,
                   averageToday: 124.2, averageYesterday: 145.8)
    }

    @Test func defaultDetailRowsLabelTheRateWithTheMode() {
        let rows = PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings(), now: .now)
        #expect(rows.map(\.label) == ["Active insulin", "Auto mode", "Reservoir", "Pump battery"])
        #expect(rows.map(\.value) == ["1.35 U", "1.15 U/h", "120 U", "65%"])
        #expect(rows.allSatisfy { $0.note == nil })
    }

    @Test func detailRowsSplitModeAndRateWhenOnlyOneIsOn() {
        let settings = Self.makeSettings()
        settings.showDeliveryRate = false
        #expect(PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                     settings: settings, now: .now).contains(.init(label: "Mode", value: "Auto mode")))
        settings.showDeliveryRate = true
        settings.showPumpMode = false
        #expect(PumpDetailsView.rows(status: fullStatus(), reservoirChanged: nil, batteryChanged: nil,
                                     settings: settings, now: .now).contains(.init(label: "Delivery rate", value: "1.15 U/h")))
    }

    @Test func statusTextModeKeepsItsOwnRow() {
        var status = fullStatus()
        status.mode = .other("normal")
        let rows = PumpDetailsView.rows(status: status, reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings(), now: .now)
        #expect(rows.contains(.init(label: "Mode", value: "normal")))
        #expect(rows.contains(.init(label: "Delivery rate", value: "1.15 U/h")))
    }

    @Test func detailRowsShowOnlyWhatTheSiteReports() {
        let status = PumpStatus(date: .now, reservoir: 8.4)
        let rows = PumpDetailsView.rows(status: status, reservoirChanged: nil, batteryChanged: nil,
                                        settings: Self.makeSettings(), now: .now)
        #expect(rows == [.init(label: "Reservoir", value: "8.4 U")])
        #expect(PumpDetailsView.rows(status: nil, reservoirChanged: nil, batteryChanged: nil,
                                     settings: Self.makeSettings(), now: .now).isEmpty)
        #expect(PumpDetailsView.dailyRows(status: status, settings: Self.makeSettings()).isEmpty)
    }

    @Test func changeAgesFollowTheirSwitch() {
        let now = Date.now
        let settings = Self.makeSettings()
        let changed = now.addingTimeInterval(-25 * 3600)
        func reservoirRow() -> PumpDetailsView.Row? {
            PumpDetailsView.rows(status: fullStatus(), reservoirChanged: changed, batteryChanged: nil,
                                 settings: settings, now: now).first { $0.label == "Reservoir" }
        }
        #expect(reservoirRow()?.note == nil)
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

    @Test func staleNoteOnlyPastTheStaleDelay() {
        let settings = Self.makeSettings()
        let now = Date.now
        #expect(PumpDetailsView.staleNote(status: PumpStatus(date: now.addingTimeInterval(-5 * 60)),
                                          settings: settings, now: now) == nil)
        #expect(PumpDetailsView.staleNote(status: PumpStatus(date: now.addingTimeInterval(-40 * 60)),
                                          settings: settings, now: now) == "Pump data from 40 minutes ago")
    }

    @Test func pumpFormatsUseFixedDecimals() {
        #expect(PumpFormat.insulin(0) == "0.00 U")
        #expect(PumpFormat.rate(2.4) == "2.40 U/h")
        #expect(PumpFormat.reservoir(150) == "150 U")
        #expect(PumpFormat.battery(65) == "65%")
        #expect(PumpFormat.dailyInsulin(47.3) == "47.3 U")
        #expect(PumpFormat.bolus(1) == "1.0 U")
        #expect(PumpFormat.bolus(0.05) == "0.05 U")
    }
}

// MARK: - Settings

extension SugargliderTests {
    @Test func pumpSwitchDefaults() {
        let s = Self.makeSettings()
        #expect(s.showActiveInsulin && s.showPumpMode && s.showDeliveryRate && s.showReservoir && s.showPumpBattery)
        #expect(s.chartShowsBoluses)
        #expect(!s.showChangeAge && !s.showDailyInsulin && !s.showAverageGlucose)
        #expect(!s.chartShowsDeliveryRate && !s.chartShowsAnnouncements)
    }

    /// Most default to true, the case `bool(forKey:)` gets wrong on reload.
    @Test func pumpSwitchesRoundTrip() {
        let defaults = Self.makeDefaults()
        let s = Self.makeSettings(defaults: defaults)
        for flag in Self.pumpSwitches { s[keyPath: flag].toggle() }
        let reloaded = Self.makeSettings(defaults: defaults)
        for flag in Self.pumpSwitches { #expect(reloaded[keyPath: flag] == s[keyPath: flag]) }
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
    @Test func insulinLaneNeedsSomethingToDraw() {
        let s = Self.makeSettings()
        let bolus = Treatment(id: "b", date: Date.now.addingTimeInterval(-50 * 3600), kind: .bolus(units: 1))
        let tempBasal = Treatment(id: "t", date: .now, kind: .tempBasal(rate: 1, minutes: 30))
        #expect(GlucoseChart.laneSpace(for: [], settings: s) == 0)
        // Decided on the whole cache, so a range drag can't make the chart jump.
        #expect(GlucoseChart.laneSpace(for: [bolus], settings: s) == GlucoseChart.laneHeight)
        #expect(GlucoseChart.laneSpace(for: [tempBasal], settings: s) == 0)
        s.chartShowsDeliveryRate = true
        #expect(GlucoseChart.laneSpace(for: [tempBasal], settings: s) == GlucoseChart.laneHeight)
        s.chartShowsBoluses = false
        #expect(GlucoseChart.laneSpace(for: [bolus], settings: s) == 0)
    }

    @Test func rendersEveryPumpLayerWithoutCrash() {
        let s = Self.makeSettings()
        s.chartShowsDeliveryRate = true
        s.chartShowsAnnouncements = true
        s.chartBackgroundEnabled = true
        let now = Date.now
        let readings = (0..<60).map { reading(100 + $0, minutesAgo: Double(59 - $0) * 5, from: now) }
        let treatments = [
            Treatment(id: "t1", date: now.addingTimeInterval(-4 * 3600), kind: .tempBasal(rate: 0.5, minutes: 30)),
            Treatment(id: "t2", date: now.addingTimeInterval(-3.8 * 3600), kind: .tempBasal(rate: 2.5, minutes: 30)),
            Treatment(id: "t3", date: now.addingTimeInterval(-3600), kind: .tempBasal(rate: 0, minutes: 30)),
            Treatment(id: "b1", date: now.addingTimeInterval(-2 * 3600), kind: .bolus(units: 3.5)),
            Treatment(id: "n1", date: now.addingTimeInterval(-1.5 * 3600), kind: .note("CamAPS: Hoher Wert")),
        ]
        let chart = GlucoseChart(readings: readings, rangeHours: 6, settings: s, windowEnd: .now, treatments: treatments)
        let height = 160 + GlucoseChart.laneSpace(for: treatments, settings: s)
        let renderer = ImageRenderer(content: chart.frame(width: 280, height: height))
        renderer.scale = 1
        #expect(renderer.cgImage != nil)
    }
}
