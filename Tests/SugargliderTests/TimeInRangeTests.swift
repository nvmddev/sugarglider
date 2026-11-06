import Foundation
import Testing
@testable import Sugarglider

private let thresholds = ChartMath.Thresholds(extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250)
private let english = Locale(identifier: "en_US")

/// One reading per value, 5 minutes apart, the newest at `end`.
private func readings(_ values: [Int], endingAt end: Date) -> [Reading] {
    values.enumerated().map { i, sgv in
        Reading(sgv: sgv, direction: nil, date: end.addingTimeInterval(-Double(values.count - 1 - i) * 300))
    }
}

extension SugargliderTests {
    @Test func timeInRangeCountsEachZone() {
        let now = Date.now
        // A threshold itself belongs to the zone nearer the target range.
        let shares = ChartMath.timeInRange(of: readings([40, 54, 60, 70, 180, 181, 250, 251], endingAt: now),
                                           thresholds: thresholds)
        #expect(shares == [.veryLow: 0.125, .low: 0.25, .inRange: 0.25, .high: 0.25, .veryHigh: 0.125])
    }

    @Test func timeInRangeListsEmptyZonesAndNothingWithoutReadings() {
        let shares = ChartMath.timeInRange(of: readings([100, 120], endingAt: .now), thresholds: thresholds)
        #expect(shares == [.veryLow: 0, .low: 0, .inRange: 1, .high: 0, .veryHigh: 0])
        #expect(ChartMath.timeInRange(of: [], thresholds: thresholds).isEmpty)
    }

    /// The sensor only says which side it ran out on, so a very low threshold set under LOW's 39
    /// doesn't make LOW count as merely low.
    @Test func lowAndHighMarkersCountAsVeryLowAndVeryHigh() {
        let odd = ChartMath.Thresholds(extremeLow: 30, targetLow: 70, targetHigh: 180, extremeHigh: 450)
        let shares = ChartMath.timeInRange(of: readings([39, 401], endingAt: .now), thresholds: odd)
        #expect(shares[.veryLow] == 0.5)
        #expect(shares[.veryHigh] == 0.5)
    }

    @Test func timeInRangeSummaryCoversTheChartWindow() throws {
        let settings = Self.makeSettings()
        settings.rangeHours = 2
        let now = Date.now
        // The first reading lies 3 hours back, outside the 2-hour window.
        let old = Reading(sgv: 300, direction: nil, date: now.addingTimeInterval(-3 * 3600))
        let summary = try #require(TimeInRangeView.summary(
            readings: [old] + readings([40, 60, 100, 100, 200, 300], endingAt: now), windowEnd: now,
            settings: settings, locale: english))

        #expect(abs(summary.inRangeShare - 1.0 / 3) < 1e-9)
        #expect(summary.inRangeText == "33%")
        #expect(summary.help == """
            Time in range (2h)
            Very low 17%
            Low 17%
            In range 33%
            High 17%
            Very high 17%
            """)
        #expect(summary.title == "Time in range (2h)")
        #expect(summary.spokenLabel == "Time in range over the last 2 hours")
        #expect(summary.zones == [.init(label: "Very low", value: "17%"), .init(label: "Low", value: "17%"),
                                  .init(label: "In range", value: "33%"), .init(label: "High", value: "17%"),
                                  .init(label: "Very high", value: "17%")])
        #expect(summary.spokenValue == "Very low 17%, Low 17%, In range 33%, High 17%, Very high 17%")
    }

    @Test func timeInRangeSummaryFollowsTheRegion() throws {
        let now = Date.now
        let summary = try #require(TimeInRangeView.summary(
            readings: readings([60, 100, 100, 200], endingAt: now), windowEnd: now,
            settings: Self.makeSettings(), locale: Locale(identifier: "de_DE")))
        // German puts a no-break space before the percent sign.
        #expect(summary.inRangeText == "50\u{A0}%")
    }

    @Test func timeInRangeSummaryHidesWhenOffOrMeaningless() {
        let now = Date.now
        let values = readings([60, 100, 200], endingAt: now)

        let off = Self.makeSettings()
        off.showTimeInRange = false
        #expect(TimeInRangeView.summary(readings: values, windowEnd: now, settings: off) == nil)

        // Out of order, the zones overlap and the shares would mean nothing.
        let disordered = Self.makeSettings()
        disordered.targetLow = 200
        #expect(disordered.thresholdOrderWarning != nil)
        #expect(TimeInRangeView.summary(readings: values, windowEnd: now, settings: disordered) == nil)

        let settings = Self.makeSettings()
        #expect(TimeInRangeView.summary(readings: [], windowEnd: now, settings: settings) == nil)
        let stale = readings([100], endingAt: now.addingTimeInterval(-7 * 3600))
        #expect(TimeInRangeView.summary(readings: stale, windowEnd: now, settings: settings) == nil)
    }
}
