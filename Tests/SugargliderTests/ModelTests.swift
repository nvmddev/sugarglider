import Testing
import Foundation
@testable import Sugarglider

extension SugargliderTests {
    @Test("Trend arrows map every Nightscout direction",
          arguments: [
            ("DoubleUp", "↑↑"), ("SingleUp", "↑"), ("FortyFiveUp", "↗"),
            ("Flat", "→"),
            ("FortyFiveDown", "↘"), ("SingleDown", "↓"), ("DoubleDown", "↓↓"),
          ])
    func trendArrow(direction: String, expected: String) {
        #expect(Reading.Direction(rawValue: direction)?.arrow == expected)
    }

    @Test func directionsWithoutATrendHaveNoArrow() {
        for name in ["NONE", "NOT COMPUTABLE", "RATE OUT OF RANGE", ""] {
            #expect(Reading.Direction(rawValue: name) == nil)
        }
    }

    @Test(arguments: [(AppSettings.Units.mgdl, 90.0), (.mmol, 5.0)])
    func glucoseConvertsBetweenUnits(units: AppSettings.Units, valueOf90: Double) {
        #expect(abs(units.value(fromMgdl: 90) - valueOf90) < 1e-9)
        #expect(abs(reading(90).value(in: units) - valueOf90) < 1e-9)
        #expect(abs(units.mgdl(from: valueOf90) - 90) < 1e-9)
    }

    @Test(arguments: [(AppSettings.Units.mgdl, 90, "90"), (.mmol, 90, "5.0"), (.mmol, 100, "5.6")])
    func glucoseTextHasOneDecimalInMmol(units: AppSettings.Units, mgdl: Int, expected: String) {
        #expect(units.text(fromMgdl: mgdl, locale: Self.enUS) == expected)
        #expect(reading(mgdl).text(in: units, locale: Self.enUS) == expected)
    }

    @Test(arguments: [AppSettings.Units.mmol, .mgdl])
    func outOfRangeMarkersReadLowAndHighInEitherUnit(units: AppSettings.Units) {
        #expect(reading(39, direction: .doubleDown).outOfRange == .low)
        #expect(reading(39, direction: .doubleDown).text(in: units) == "LOW")
        #expect(reading(401, direction: .doubleUp).outOfRange == .high)
        #expect(reading(401, direction: .doubleUp).text(in: units) == "HIGH")
        // The sensor's own bounds are real readings.
        for sgv in [38, 40, 400, 402] {
            let bound = reading(sgv)
            #expect(bound.outOfRange == nil)
            #expect(bound.text(in: units) == units.text(fromMgdl: sgv))
        }
    }

    @Test func unitLabels() {
        #expect(AppSettings.Units.mmol.label == "mmol/L")
        #expect(AppSettings.Units.mgdl.label == "mg/dL")
    }

    @Test func unitRawValuesRoundTrip() {
        #expect(AppSettings.Units(rawValue: "mmol") == .mmol)
        #expect(AppSettings.Units(rawValue: "mgdl") == .mgdl)
        #expect(AppSettings.Units(rawValue: "nonsense") == nil)
    }

    @Test(arguments: [
        (NightscoutError.notConfigured, "Not configured"), (.badURL, "Invalid URL"),
        (.http(404), "HTTP 404"), (.http(500), "HTTP 500"),
        (.empty, "No readings"), (.decode, "Bad response"),
    ])
    func errorDescription(error: NightscoutError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    @Test func versionTextFallsBackWhenBundleKeysAreMissing() {
        #expect(AppInfo.versionText(short: "0.2.0", build: "73") == "Version 0.2.0 (73)")
        #expect(AppInfo.versionText(short: "0.2.0", build: nil) == "Version 0.2.0")
        #expect(AppInfo.versionText(short: "0.2.0", build: "") == "Version 0.2.0")
        #expect(AppInfo.versionText(short: nil, build: "73") == "Development build")
        #expect(AppInfo.versionText(short: "", build: "73") == "Development build")
    }

    @Test func repositoryLinksPointAtTheProject() {
        #expect(AppInfo.issuesURL.absoluteString == "https://github.com/nvmddev/sugarglider/issues")
        #expect(AppInfo.licenseURL.absoluteString
                == "https://github.com/nvmddev/sugarglider/blob/main/LICENSE")
    }

    @Test(arguments: [
        ("https://ns.example", false),
        ("https://ns.example/api", false),
        ("http://tower.local", true),
        ("http://192.168.0.5", true),
        ("tower", true),               // no scheme: ATS speaks plain http to it
        ("nightscout.local", true),
        ("", false),
        ("   ", false),
    ])
    func insecureSchemeDetection(url: String, insecure: Bool) {
        #expect(GeneralTab.usesInsecureScheme(url) == insecure)
    }
}
