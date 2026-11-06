import SwiftUI

/// The time in range over the span the chart shows, under the reading. The label sits above the
/// values because both side by side don't fit the dropdown's width.
struct TimeInRangeView: View {
    var settings: AppSettings
    var store: ReadingStore

    struct Summary: Equatable {
        var label: String
        /// Very low folds into low and very high into high, so the values fit on one line.
        var value: String
        /// All five zones, one per line.
        var help: String
        var spokenLabel: String
        var spokenValue: String
    }

    var body: some View {
        if let summary = Self.summary(readings: store.readings, windowEnd: store.now, settings: settings) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.label).foregroundStyle(.secondary)
                Text(summary.value)
            }
            .font(.subheadline)
            .monospacedDigit()
            .help(summary.help)
            // Not .combine: that merges the help of both lines, so VoiceOver would read the zones three
            // times. Without the trait the element has no role (measured).
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(summary.spokenLabel)
            .accessibilityValue(summary.spokenValue)
        }
    }

    /// Nil while the thresholds are out of order, because the zones then overlap.
    static func summary(readings: [Reading], windowEnd: Date, settings: AppSettings,
                        locale: Locale = .autoupdatingCurrent) -> Summary? {
        guard settings.showTimeInRange, settings.thresholdOrderWarning == nil else { return nil }
        let window = ChartMath.window(hours: settings.rangeHours, endingAt: windowEnd, readings: readings)
        let shares = ChartMath.timeInRange(of: readings.filter { $0.date >= window.lowerBound },
                                           thresholds: settings.thresholds)
        guard !shares.isEmpty else { return nil }

        func percent(_ zones: ChartMath.Zone...) -> String {
            zones.reduce(0) { $0 + shares[$1, default: 0] }
                .formatted(.percent.precision(.fractionLength(0)).locale(locale))
        }
        let zones = [String(localized: "Very low \(percent(.veryLow))"), String(localized: "Low \(percent(.low))"),
                     String(localized: "In range \(percent(.inRange))"), String(localized: "High \(percent(.high))"),
                     String(localized: "Very high \(percent(.veryHigh))")]
        let short = [String(localized: "Low \(percent(.veryLow, .low))"), String(localized: "In range \(percent(.inRange))"),
                     String(localized: "High \(percent(.high, .veryHigh))")]
        let hours = Duration.seconds(Double(settings.rangeHours) * 3600)
        func hoursText(_ width: Duration.UnitsFormatStyle.UnitWidth) -> String {
            hours.formatted(.units(allowed: [.hours], width: width).locale(locale))
        }
        return Summary(label: String(localized: "Time in range (\(hoursText(.narrow)))"),
                       value: short.joined(separator: " · "),
                       help: zones.joined(separator: "\n"),
                       spokenLabel: String(localized: "Time in range over the last \(hoursText(.wide))"),
                       spokenValue: zones.joined(separator: ", "))
    }
}
