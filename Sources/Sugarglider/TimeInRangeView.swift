import SwiftUI

/// The share of readings in range over the span the chart shows, as a ring beside the reading.
/// Every zone's share is in its help tag and in what VoiceOver reads.
struct TimeInRangeView: View {
    var settings: AppSettings
    var store: ReadingStore

    struct Summary: Equatable {
        /// The ring's fill, from 0 to 1.
        var inRangeShare: Double
        var inRangeText: String
        /// What the ring stands for, then all five zones, one per line.
        var help: String
        var spokenLabel: String
        var spokenValue: String
    }

    var body: some View {
        if let summary = Self.summary(readings: store.readings, windowEnd: store.now, settings: settings) {
            VStack(spacing: 2) {
                Gauge(value: summary.inRangeShare) {
                    Text("In range")
                } currentValueLabel: {
                    // The style's own label size leaves "100%" no room inside the ring.
                    Text(summary.inRangeText).font(.body.weight(.medium)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(settings.inRangeColor)
                Text("In range").font(.caption2).foregroundStyle(.secondary)
            }
            .help(summary.help)
            // Without the trait the element has no role (measured).
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
        guard let inRange = shares[.inRange] else { return nil }

        func percent(_ zone: ChartMath.Zone) -> String {
            shares[zone, default: 0].formatted(.percent.precision(.fractionLength(0)).locale(locale))
        }
        let zones = [String(localized: "Very low \(percent(.veryLow))"), String(localized: "Low \(percent(.low))"),
                     String(localized: "In range \(percent(.inRange))"), String(localized: "High \(percent(.high))"),
                     String(localized: "Very high \(percent(.veryHigh))")]
        let hours = Duration.seconds(Double(settings.rangeHours) * 3600)
            .formatted(.units(allowed: [.hours], width: .wide).locale(locale))
        let title = String(localized: "Time in range over the last \(hours)")
        return Summary(inRangeShare: inRange, inRangeText: percent(.inRange),
                       help: ([title] + zones).joined(separator: "\n"),
                       spokenLabel: title, spokenValue: zones.joined(separator: ", "))
    }
}
