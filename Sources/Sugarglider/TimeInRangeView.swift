import SwiftUI

/// The time in range over the span the chart shows, under the reading: a row per zone, with the
/// span as the column header, as the daily table names its days.
struct TimeInRangeView: View {
    var settings: AppSettings
    var store: ReadingStore

    struct Summary: Equatable {
        /// The column header, e.g. "8h".
        var span: String
        /// Low, in range and high. Very low folds into low and very high into high.
        var rows: [Row]
        /// All five zones, one per line.
        var help: String
        var spokenLabel: String
        var spokenValue: String

        struct Row: Equatable {
            var label: String
            var value: String
        }
    }

    var body: some View {
        if let summary = Self.summary(readings: store.readings, windowEnd: store.now, settings: settings) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("Time in range").frame(maxWidth: .infinity, alignment: .leading)
                    Text(summary.span)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                ForEach(summary.rows, id: \.label) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                    }
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .help(summary.help)
            // Not .combine: that merges the help of every cell into what VoiceOver reads. Without
            // the trait the element has no role (measured).
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
        let hours = Duration.seconds(Double(settings.rangeHours) * 3600)
        func hoursText(_ width: Duration.UnitsFormatStyle.UnitWidth) -> String {
            hours.formatted(.units(allowed: [.hours], width: width).locale(locale))
        }
        return Summary(span: hoursText(.narrow),
                       rows: [Summary.Row(label: String(localized: "Low"), value: percent(.veryLow, .low)),
                              Summary.Row(label: String(localized: "In range"), value: percent(.inRange)),
                              Summary.Row(label: String(localized: "High"), value: percent(.high, .veryHigh))],
                       help: zones.joined(separator: "\n"),
                       spokenLabel: String(localized: "Time in range over the last \(hoursText(.wide))"),
                       spokenValue: zones.joined(separator: ", "))
    }
}
