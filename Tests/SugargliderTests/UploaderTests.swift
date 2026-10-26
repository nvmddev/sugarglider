import Testing
import Foundation
@testable import Sugarglider

/// The uploaders whose records Sugarglider is pinned against. Each fixture is written from that
/// project's own upload code with invented values, in the form Nightscout returns it (newest first,
/// `created_at` stamped where the uploader sends none). Expectations pin what Sugarglider reads
/// today; a line marked "Misread" is a known gap, so fixing one changes its expectation here.
enum Uploader: String, CaseIterable, CustomTestStringConvertible {
    case loopMedtronic = "Loop, Medtronic"
    case loopOmnipod = "Loop, Omnipod above 50 U"
    case trioOmnipod = "Trio, Omnipod above 50 U"
    case aapsDana = "AAPS, Dana"
    case aapsOmnipod = "AAPS, Omnipod DASH above 50 U"
    case openAPS = "OpenAPS oref0, Medtronic"
    case xDrip = "xDrip+ alone"
    case careLink = "CareLink bridge, 780G"
    case careLinkGuardian = "CareLink bridge, Guardian sensor only"
    case aapsWithXDrip = "AAPS with xDrip+ uploading too"

    var testDescription: String { rawValue }
}

@MainActor
struct UploaderFixture {
    var deviceStatus: String
    var treatments: String
    var pumpStatus: PumpStatus?
    /// Oldest first.
    var kinds: [Treatment.Kind]
}

/// 2030-01-01T12:00:00Z, the time of each fixture's newest device status.
private let noon = Date(timeIntervalSince1970: 1_893_499_200)

extension Uploader {
    @MainActor var fixture: UploaderFixture {
        switch self {
        // LoopKit NightscoutService (StoredDosingDecision, DoseEntry, PersistedPumpEvent) with MinimedKit.
        case .loopMedtronic: UploaderFixture(
            deviceStatus: """
                [{"device":"loop://iPhone","created_at":"2030-01-01T12:00:00.000Z","utcOffset":0,
                  "pump":{"clock":"2030-01-01T12:00:00Z","manufacturer":"Medtronic","model":"723",
                          "suspended":false,"bolusing":false,"reservoir":112.5,"battery":{"percent":74},
                          "secondsFromGMT":3600},
                  "uploader":{"name":"iPhone","timestamp":"2030-01-01T12:00:00Z","battery":85,"isCharging":false},
                  "loop":{"name":"Loop","version":"3.14.9.57","timestamp":"2030-01-01T12:00:00Z",
                          "iob":{"timestamp":"2030-01-01T12:00:00Z","iob":-0.2345678},
                          "cob":{"timestamp":"2030-01-01T12:00:00Z","cob":0},
                          "predicted":{"startDate":"2030-01-01T11:58:00Z","values":[123.45,121.1,119.87]},
                          "enacted":{"rate":0,"duration":30,"timestamp":"2030-01-01T11:59:55Z",
                                     "received":true,"bolusVolume":0}},
                  "override":{"timestamp":"2030-01-01T12:00:00Z","active":false}},
                 {"device":"loop://iPhone","created_at":"2030-01-01T11:55:00.000Z","utcOffset":0,
                  "pump":{"clock":"2030-01-01T11:55:00Z","manufacturer":"Medtronic","model":"723",
                          "suspended":false,"bolusing":false,"reservoir":112.7,"battery":{"percent":74},
                          "secondsFromGMT":3600},
                  "loop":{"name":"Loop","iob":{"timestamp":"2030-01-01T11:55:00Z","iob":0.1}}}]
                """,
            treatments: """
                [{"eventType":"Note","created_at":"2030-01-01T11:58:00.000Z","enteredBy":"loop://iPhone",
                  "notes":"Battery Out Limit"},
                 {"eventType":"Temp Basal","created_at":"2030-01-01T11:55:00.000Z","enteredBy":"loop://iPhone",
                  "temp":"absolute","rate":0,"absolute":0,"duration":0,"automatic":true,"reason":"suspend"},
                 {"eventType":"Temporary Override","created_at":"2030-01-01T11:50:00.000Z","enteredBy":"Loop",
                  "_id":"0E9C2B7A-5D41-4F3B-9C6E-2A8B7D1E4F30","reason":"Custom Override","duration":60,
                  "correctionRange":[140,160],"insulinNeedsScaleFactor":0.8},
                 {"eventType":"Carb Correction","created_at":"2030-01-01T11:45:00.000Z","enteredBy":"loop://iPhone",
                  "carbs":45,"absorptionTime":180},
                 {"eventType":"Correction Bolus","created_at":"2030-01-01T11:40:00.000Z","enteredBy":"loop://iPhone",
                  "type":"normal","insulin":2,"programmed":2,"unabsorbed":0,"duration":0.5,"automatic":false},
                 {"eventType":"Temp Basal","created_at":"2030-01-01T11:30:00.000Z","enteredBy":"loop://iPhone",
                  "temp":"absolute","rate":1.2,"absolute":1.2,"duration":30,"amount":0.6,"automatic":true},
                 {"eventType":"Correction Bolus","created_at":"2030-01-01T10:00:00.000Z","enteredBy":"loop://iPhone",
                  "type":"square","insulin":3,"programmed":3,"unabsorbed":0,"duration":60,"automatic":false},
                 {"eventType":"Site Change","created_at":"2030-01-01T08:00:00.000Z","enteredBy":"loop://iPhone",
                  "notes":"Set Change (fixed prime)"}]
                """,
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: -0.2345678, reservoir: 112.5, batteryPercent: 74),
            // Misread: a suspend still running has duration 0, so it is drawn as a cancel.
            kinds: [.bolus(units: 3), .tempBasal(rate: 1.2, minutes: 30), .bolus(units: 2),
                    .tempBasal(rate: 0, minutes: 0), .note("Battery Out Limit")])

        // LoopKit NightscoutService with OmnipodKit: a pod sends no battery and no level above 50 U.
        case .loopOmnipod: UploaderFixture(
            deviceStatus: """
                [{"device":"loop://iPhone","created_at":"2030-01-01T12:00:00.000Z",
                  "pump":{"clock":"2030-01-01T12:00:00Z","manufacturer":"Insulet",
                          "model":"Omnipod DASH","suspended":false,"bolusing":false,"secondsFromGMT":3600},
                  "uploader":{"name":"iPhone","timestamp":"2030-01-01T12:00:00Z","battery":85,"isCharging":false},
                  "loop":{"name":"Loop","timestamp":"2030-01-01T12:00:00Z",
                          "iob":{"timestamp":"2030-01-01T12:00:00Z","iob":1.2345678}},
                  "override":{"timestamp":"2030-01-01T12:00:00Z","active":false}}]
                """,
            treatments: """
                [{"eventType":"Correction Bolus","created_at":"2030-01-01T11:45:00.000Z","enteredBy":"loop://iPhone",
                  "type":"normal","insulin":0.05,"programmed":0.05,"unabsorbed":0,"duration":0.03,"automatic":true},
                 {"eventType":"Temp Basal","created_at":"2030-01-01T11:30:00.000Z","enteredBy":"loop://iPhone",
                  "temp":"absolute","rate":0.85,"absolute":0.85,"duration":30,"automatic":true},
                 {"eventType":"Site Change","created_at":"2030-01-01T07:00:00.000Z","enteredBy":"loop://iPhone",
                  "notes":"Pod Change (Omnipod DASH)"}]
                """,
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 1.2345678),
            kinds: [.tempBasal(rate: 0.85, minutes: 30), .bolus(units: 0.05)])

        // Trio NightscoutStatus and NightscoutTreatment; Trio sends no created_at, Nightscout stamps it.
        case .trioOmnipod: UploaderFixture(
            deviceStatus: """
                [{"device":"Trio","created_at":"2030-01-01T12:00:00.000Z",
                  "openaps":{"iob":{"iob":1.23,"activity":0.01,"basaliob":0.2,"bolusiob":1.03,
                                    "netbasalinsulin":0.1,"bolusinsulin":1.1,"time":"2030-01-01T11:59:58.120Z"},
                             "suggested":{"reason":"invented","units":0.1,"eventualBG":120,"rate":0.5,"duration":30,
                                          "IOB":1.23,"COB":10,"bg":110,"timestamp":"2030-01-01T11:59:58.120Z"},
                             "version":"0.5.1","recommendedBolus":0.4},
                  "pump":{"clock":"2030-01-01T12:00:00.480Z",
                          "battery":{"percent":100,"string":"normal","display":false},
                          "status":{"status":"normal","bolusing":false,"suspended":false,
                                    "timestamp":"2030-01-01T11:59:00.000Z"},
                          "bolusIncrement":0.05},
                  "uploader":{"battery":85,"isCharging":false}}]
                """,
            treatments: """
                [{"eventType":"Note","created_at":"2030-01-01T11:56:00.000Z","enteredBy":"Trio","notes":"PumpResume"},
                 {"eventType":"Note","created_at":"2030-01-01T11:52:00.000Z","enteredBy":"Trio","notes":"PumpSuspend"},
                 {"eventType":"Temp Basal","created_at":"2030-01-01T11:50:00.000Z","enteredBy":"Trio",
                  "id":"7C3E0A51-0D2B-4E7A-9F61-3B5A8C2D1E04","duration":0,"absolute":0,"rate":0},
                 {"eventType":"SMB","created_at":"2030-01-01T11:45:00.000Z","enteredBy":"Trio",
                  "id":"5A9D2F10-6B3C-4D8E-A1F2-7E4B9C0D3A65","insulin":0.3},
                 {"eventType":"Bolus","created_at":"2030-01-01T11:40:00.000Z","enteredBy":"Trio",
                  "id":"2B8E4C61-9A0D-4F3B-8C27-1D6E5A4B3F92","insulin":2.5},
                 {"eventType":"Carb Correction","created_at":"2030-01-01T11:39:00.000Z","enteredBy":"Trio",
                  "id":"9F1A3B5C-7D2E-4A6B-8C0D-E1F2A3B4C5D6","carbs":40,"fat":0,"protein":0,
                  "notes":"pasta","foodType":"pasta"},
                 {"eventType":"Temp Basal","created_at":"2030-01-01T11:30:00.000Z","enteredBy":"Trio",
                  "id":"4E6F8A0B-2C3D-4E5F-9A1B-C2D3E4F5A6B7","duration":30,"absolute":0.8,"rate":0.8},
                 {"eventType":"Announcement","created_at":"2030-01-01T10:00:00.000Z","enteredBy":"Trio",
                  "duration":30,"notes":"Alarm Optional(\\"Occlusion\\") PumpAlarm"},
                 {"eventType":"Exercise","created_at":"2030-01-01T09:00:00.000Z","enteredBy":"Trio",
                  "duration":60,"notes":"Custom Override"},
                 {"eventType":"Insulin Change","created_at":"2030-01-01T07:00:00.000Z","enteredBy":"Trio"}]
                """,
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 1.23),
            kinds: [.note(#"Alarm Optional("Occlusion") PumpAlarm"#), .tempBasal(rate: 0.8, minutes: 30),
                    .bolus(units: 2.5), .bolus(units: 0.3), .tempBasal(rate: 0, minutes: 0),
                    .note("PumpSuspend"), .note("PumpResume")])

        // AAPS NSClientV3 (DeviceStatusExtension, PumpStatusProviderImpl, TreatmentMapper); Nightscout
        // adds created_at from date.
        case .aapsDana: UploaderFixture(
            deviceStatus: """
                [{"date":1893499200000,"created_at":"2030-01-01T12:00:00.000Z","utcOffset":60,
                  "device":"openaps://phone","uploaderBattery":87,"isCharging":false,"uploader":{},
                  "pump":{"reservoir":128,"clock":"2030-01-01T11:59:59.900Z","battery":{"percent":74},
                          "status":{"status":"Closed Loop","timestamp":"2030-01-01T11:59:40.000Z"},
                          "extended":{"Version":"3.4.0.0","BaseBasalRate":0.85,"ActiveProfile":"Default"}},
                  "openaps":{"iob":{"iob":1.234,"basaliob":0.321,"activity":0.0123,
                                    "time":"2030-01-01T11:59:55.000Z"}}}]
                """,
            treatments: """
                [{"date":1893498600000,"created_at":"2030-01-01T11:50:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Correction Bolus","insulin":0.3,"type":"SMB","isBasalInsulin":false},
                 {"date":1893498000000,"created_at":"2030-01-01T11:40:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Meal Bolus","insulin":3.5,"type":"NORMAL","isBasalInsulin":false},
                 {"date":1893497700000,"created_at":"2030-01-01T11:35:00.000Z","utcOffset":60,"isValid":false,
                  "eventType":"Meal Bolus","insulin":1,"type":"NORMAL","isBasalInsulin":false},
                 {"date":1893497400000,"created_at":"2030-01-01T11:30:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Temp Basal","duration":60,"durationInMilliseconds":3600000,"rate":0.425,
                  "percent":-50,"type":"NORMAL"},
                 {"date":1893495600000,"created_at":"2030-01-01T11:00:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Combo Bolus","duration":120,"durationInMilliseconds":7200000,"splitNow":0,
                  "splitExt":100,"enteredinsulin":2,"relative":1,"isEmulatingTempBasal":false},
                 {"date":1893495000000,"created_at":"2030-01-01T10:50:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Temp Basal","duration":30,"durationInMilliseconds":1800000,"rate":0.45,
                  "absolute":0.45,"type":"NORMAL"},
                 {"date":1893492000000,"created_at":"2030-01-01T10:00:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Announcement","notes":"Pump unreachable","isAnnouncement":true},
                 {"date":1893484860000,"created_at":"2030-01-01T08:01:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Meal Bolus","insulin":0.7,"type":"PRIMING","isBasalInsulin":false},
                 {"date":1893484800000,"created_at":"2030-01-01T08:00:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Insulin Change","notes":"new cartridge"}]
                """,
            // Misread: "Closed Loop" is the loop's mode in the app's language, not the pump's.
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 1.234, reservoir: 128, batteryPercent: 74,
                                   mode: .other("Closed Loop")),
            // Not read: the extended bolus (Combo Bolus, no insulin key).
            kinds: [.note("Pump unreachable"), .tempBasal(rate: 0.45, minutes: 30),
                    .tempBasal(rate: 0.425, minutes: 60), .bolus(units: 3.5), .bolus(units: 0.3)])

        // AAPS OmnipodDashPumpPlugin: 75 U stands for "above 50 U", the battery object stays empty.
        case .aapsOmnipod: UploaderFixture(
            deviceStatus: """
                [{"date":1893499200000,"created_at":"2030-01-01T12:00:00.000Z","utcOffset":60,
                  "device":"openaps://phone","uploader":{},
                  "pump":{"reservoir":75,"clock":"2030-01-01T11:59:59.900Z","battery":{},
                          "status":{"status":"Closed Loop","timestamp":"2030-01-01T11:59:40.000Z"},
                          "extended":{"Version":"3.4.0.0","ActiveProfile":"Default"}},
                  "openaps":{"iob":{"iob":0.5,"basaliob":-0.1,"activity":0.004,
                                    "time":"2030-01-01T11:59:55.000Z"}}}]
                """,
            treatments: """
                [{"date":1893498600000,"created_at":"2030-01-01T11:50:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Correction Bolus","insulin":0.15,"type":"SMB","isBasalInsulin":false},
                 {"date":1893477600000,"created_at":"2030-01-01T06:00:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Site Change"}]
                """,
            // Misread: the reservoir shows 75 U, a placeholder rather than a measurement.
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 0.5, reservoir: 75, mode: .other("Closed Loop")),
            kinds: [.bolus(units: 0.15)])

        // oref0 bin/ns-status.js and lib/temps.js, lib/bolus.js, mm-format-ns-treatments.sh; treatments as
        // uploaded, with numbers in strings and the pump's offset (a current Nightscout turns it into UTC).
        case .openAPS: UploaderFixture(
            deviceStatus: """
                [{"device":"openaps://rig","created_at":"2030-01-01T12:00:00.000Z",
                  "openaps":{"iob":{"iob":0.85,"activity":0.0123,"basaliob":-0.2,"bolusiob":1.05,
                                    "timestamp":"2030-01-01T12:59:50+01:00","mills":1893499190000},
                             "suggested":{"bg":120,"timestamp":"2030-01-01T11:59:00.000Z","mills":1893499140000},
                             "enacted":{"rate":0.8,"duration":30,"timestamp":"2030-01-01T11:59:00.000Z",
                                        "mills":1893499140000},
                             "version":"0.7.1"},
                  "pump":{"clock":"2030-01-01T12:59:30+01:00","battery":{"status":"normal","voltage":1.35},
                          "reservoir":85.3,
                          "status":{"status":"normal","bolusing":false,"suspended":false,
                                    "timestamp":"2030-01-01T11:59:31.000Z"}},
                  "uploader":{"batteryVoltage":3680,"battery":50}}]
                """,
            treatments: """
                [{"eventType":"Note","created_at":"2030-01-01T12:50:00+01:00","enteredBy":"openaps://medtronic/723",
                  "notes":"PumpResume model 723"},
                 {"eventType":"Temp Basal","duration":"0","absolute":"0","rate":0,
                  "created_at":"2030-01-01T12:45:00+01:00","enteredBy":"openaps://medtronic/723"},
                 {"eventType":"Temp Basal","duration":"30","percent":"150","rate":150,
                  "created_at":"2030-01-01T12:40:00+01:00","enteredBy":"openaps://medtronic/723"},
                 {"eventType":"Correction Bolus","insulin":"1.5","duration":"0",
                  "created_at":"2030-01-01T12:20:00+01:00","enteredBy":"openaps://medtronic/723"},
                 {"eventType":"Temp Basal","duration":"30","absolute":"0.8","rate":0.8,
                  "timestamp":"2030-01-01T12:10:00+01:00","created_at":"2030-01-01T12:10:00+01:00",
                  "enteredBy":"openaps://medtronic/723"},
                 {"eventType":"Meal Bolus","insulin":"4.2","carbs":40,"duration":"60","bg":"110","glucose":"110",
                  "created_at":"2030-01-01T11:30:00+01:00",
                  "enteredBy":"openaps://medtronic/723"},
                 {"eventType":"BG Check","glucose":105,"glucoseType":"Finger",
                  "created_at":"2030-01-01T11:25:00+01:00","enteredBy":"openaps://medtronic/723"},
                 {"eventType":"Insulin Change","notes":"Rewind model 723",
                  "created_at":"2030-01-01T09:00:00+01:00","enteredBy":"openaps://medtronic/723"}]
                """,
            // Not read: the battery comes as a voltage only.
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 0.85, reservoir: 85.3),
            kinds: [.bolus(units: 4.2), .tempBasal(rate: 0.8, minutes: 30), .bolus(units: 1.5),
                    .tempBasal(rate: 0, minutes: 0),
                    .note("PumpResume model 723")])

        // xDrip+ NightscoutUploader and NightscoutBatteryDevice: devicestatus is battery only.
        case .xDrip: UploaderFixture(
            deviceStatus: """
                [{"device":"phone","uploader":{"battery":64,"type":"PHONE"},"created_at":"2030-01-01T12:00:00.000Z"},
                 {"device":"G6 Transmitter","created_at":"2030-01-01T11:55:00.000Z",
                  "uploader":{"battery":"50 days (voltage: 285/275)","type":"DEXCOM_TRANSMITTER","days":50,
                              "status":"OK","voltagea":285,"voltageb":275}}]
                """,
            treatments: """
                [{"timestamp":1893498000000,"eventType":"<none>","enteredBy":"xdrip","notes":"dinner",
                  "uuid":"b9a7c3e1-0d2f-4a6b-8c1e-3f5a7b9d1c2e","carbs":45,"insulin":4,
                  "created_at":"2030-01-01T11:40:00.000Z","sysTime":"2030-01-01T12:40:00.000+0100"},
                 {"timestamp":1893496200000,"eventType":"<none>","enteredBy":"xdrip pos:12.34",
                  "uuid":"c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f","carbs":20,"insulin":0,
                  "created_at":"2030-01-01T11:10:00.000Z"},
                 {"timestamp":1893477600000,"eventType":"Sensor Start","enteredBy":"xdrip",
                  "uuid":"d4e5f6a7-b8c9-4d0e-9f1a-2b3c4d5e6f70","carbs":0,"insulin":0,
                  "created_at":"2030-01-01T06:00:00.000Z"}]
                """,
            pumpStatus: nil,
            kinds: [.bolus(units: 4)])

        // nightscout-connect minimedcarelink (deviceStatusEntry, markers_to_treatment).
        case .careLink: UploaderFixture(
            deviceStatus: """
                [{"created_at":"2030-01-01T12:00:00.000Z","lastMedicalDeviceDataUpdateServerTime":1893499200000,
                  "device":"nightscout-connect://minimedcarelink/NGP","uploader":{"battery":80},
                  "connect":{"sensorState":"NORMAL","calibStatus":"NO_ACTION_REQUIRED","sensorDurationHours":96,
                             "conduitInRange":true,"conduitMedicalDeviceInRange":true,"conduitSensorInRange":true,
                             "medicalDeviceBatteryLevelPercent":75,"medicalDeviceFamily":"NGP"},
                  "pump":{"battery":{"percent":75},"reservoir":143.2,
                          "iob":{"timestamp":"2030-01-01T12:00:00.000Z","bolusiob":0},
                          "clock":"2030-01-01T12:58:00.000+01:00","bolusiob":0}},
                 {"created_at":"2030-01-01T11:55:00.000Z","device":"nightscout-connect://minimedcarelink/NGP",
                  "pump":{"battery":{"percent":75},"reservoir":143.4,
                          "iob":{"timestamp":"2030-01-01T11:55:00.000Z","bolusiob":0.4},"bolusiob":0.4}}]
                """,
            treatments: """
                [{"eventType":"BG CHECK","created_at":"2030-01-01T12:55:00.000+01:00","glucose":104,
                  "glucoseType":"Finger"},
                 {"eventType":"Correction Bolus","created_at":"2030-01-01T12:50:00.000+01:00","insulin":0,
                  "carelink":{"type":"INSULIN","index":11}},
                 {"eventType":"Correction Bolus","created_at":"2030-01-01T12:40:00.000+01:00","insulin":0.6,
                  "carelink":{"type":"INSULIN","index":9,"deliveredFastAmount":0.6}},
                 {"eventType":"Meal Bolus","created_at":"2030-01-01T12:00:00.000+01:00","carbs":30,
                  "_meal":{"type":"MEAL","index":8,"amount":30},
                  "_dose":{"type":"INSULIN","index":8,"bolusType":"SQUARE"}},
                 {"eventType":"Meal Bolus","created_at":"2030-01-01T11:15:00.000+01:00","carbs":45,"duration":0,
                  "type":"normal","insulin":4.5,"programmed":4.5,
                  "_meal":{"type":"MEAL","index":7,"amount":45},
                  "_dose":{"type":"INSULIN","index":7,"bolusType":"FAST","deliveredFastAmount":4.5}}]
                """,
            pumpStatus: PumpStatus(date: noon, insulinOnBoard: 0, reservoir: 143.2, batteryPercent: 75),
            // Misread: the square bolus comes without insulin and is missing.
            kinds: [.bolus(units: 4.5), .bolus(units: 0.6)])

        // nightscout-connect minimedcarelink writes no pump block for a Guardian sensor.
        case .careLinkGuardian: UploaderFixture(
            deviceStatus: """
                [{"created_at":"2030-01-01T12:00:00.000Z","device":"nightscout-connect://minimedcarelink/GUARDIAN",
                  "uploader":{"battery":60},
                  "connect":{"sensorState":"NORMAL","medicalDeviceBatteryLevelPercent":60,
                             "medicalDeviceFamily":"GUARDIAN"}}]
                """,
            treatments: """
                [{"eventType":"BG CHECK","created_at":"2030-01-01T12:30:00.000+01:00","glucose":98,
                  "glucoseType":"Finger"}]
                """,
            pumpStatus: nil,
            kinds: [])

        // AAPS with xDrip+ as its CGM source: the phone battery records are the newest.
        case .aapsWithXDrip: UploaderFixture(
            deviceStatus: """
                [{"device":"phone","uploader":{"battery":64,"type":"PHONE"},"created_at":"2030-01-01T12:00:00.000Z"},
                 {"device":"phone","uploader":{"battery":65,"type":"PHONE"},"created_at":"2030-01-01T11:58:00.000Z"},
                 {"date":1893498900000,"created_at":"2030-01-01T11:55:00.000Z","device":"openaps://phone",
                  "uploader":{},
                  "pump":{"reservoir":96,"clock":"2030-01-01T11:54:59.900Z","battery":{"percent":40},
                          "status":{"status":"Open Loop","timestamp":"2030-01-01T11:54:40.000Z"}},
                  "openaps":{"iob":{"iob":2.1,"basaliob":0.1,"time":"2030-01-01T11:54:55.000Z"}}}]
                """,
            treatments: """
                [{"timestamp":1893498720000,"eventType":"<none>","enteredBy":"xdrip","carbs":0,"insulin":1,
                  "uuid":"e5f6a7b8-c9d0-4e1f-8a2b-3c4d5e6f7a8b","created_at":"2030-01-01T11:52:00.000Z"},
                 {"date":1893498600000,"created_at":"2030-01-01T11:50:00.000Z","utcOffset":60,"isValid":true,
                  "eventType":"Correction Bolus","insulin":0.2,"type":"SMB","isBasalInsulin":false}]
                """,
            pumpStatus: PumpStatus(date: noon.addingTimeInterval(-5 * 60), insulinOnBoard: 2.1, reservoir: 96,
                                   batteryPercent: 40, mode: .other("Open Loop")),
            kinds: [.bolus(units: 0.2), .bolus(units: 1)])
        }
    }
}

extension SugargliderTests {
    @Test(arguments: Uploader.allCases)
    func uploaderRecordsAreReadAsPinned(_ uploader: Uploader) async throws {
        let fixture = uploader.fixture
        let deviceStatus = StubbedSite(json: fixture.deviceStatus)
        #expect(try await deviceStatus.nightscout().pumpStatus() == fixture.pumpStatus)
        let treatments = StubbedSite(json: fixture.treatments)
        let kinds = try await treatments.nightscout().treatments(count: 100, since: .distantPast).map(\.kind)
        #expect(kinds == fixture.kinds)
    }
}
