import SwiftUI

/// The share of readings in range over the span the chart shows, as a ring beside the reading.
/// A click on it lists every zone's share, as do its help tag and VoiceOver.
struct TimeInRangeView: View {
    var settings: AppSettings
    var store: ReadingStore
    @State private var showsZones = false

    /// The circular gauge styles keep a fixed size on macOS, which `.frame` and `controlSize` don't
    /// change (measured), so the ring is scaled to the height of the reading's two lines.
    private static let ringScale: CGFloat = 0.7

    struct Summary: Equatable {
        /// The ring's fill, from 0 to 1.
        var inRangeShare: Double
        var inRangeText: String
        /// What the ring stands for, short: the popover's and the help tag's title.
        var title: String
        /// The same with the hours spelled out, for VoiceOver.
        var spokenLabel: String
        /// All five zones, from very low up.
        var zones: [Zone]
        /// The title, then each zone on its own line.
        var help: String
        var spokenValue: String

        struct Zone: Equatable {
            var label: String
            var value: String
        }
    }

    var body: some View {
        if let summary = Self.summary(readings: store.readings, windowEnd: store.now, settings: settings) {
            Button { showsZones.toggle() } label: {
                Gauge(value: summary.inRangeShare) {
                    Text(summary.title)
                } currentValueLabel: {
                    // The style's own label size leaves "100%" no room inside the ring.
                    Text(summary.inRangeText).font(.title3.weight(.medium)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(settings.inRangeColor)
                .scaled(by: Self.ringScale)
            }
            .buttonStyle(.plain)
            .help(summary.help)
            .accessibilityLabel(summary.spokenLabel)
            .accessibilityValue(summary.spokenValue)
            // VoiceOver reads the help tag as the hint, which would repeat the value.
            .accessibilityHint(Text("Shows each zone's share"))
            .popover(isPresented: $showsZones, arrowEdge: .bottom) { ZoneShares(summary: summary) }
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

        // Rounding must not turn a few readings into none, nor all but a few into all.
        func percent(_ zone: ChartMath.Zone) -> String {
            let share = shares[zone, default: 0]
            let style: FloatingPointFormatStyle<Double>.Percent = .percent.precision(.fractionLength(0)).locale(locale)
            if share > 0, share < 0.01 { return String(localized: "<\(0.01.formatted(style))") }
            if share > 0.99, share < 1 { return String(localized: ">\(0.99.formatted(style))") }
            return share.formatted(style)
        }
        let zones = [Summary.Zone(label: String(localized: "Very low"), value: percent(.veryLow)),
                     Summary.Zone(label: String(localized: "Low"), value: percent(.low)),
                     Summary.Zone(label: String(localized: "In range"), value: percent(.inRange)),
                     Summary.Zone(label: String(localized: "High"), value: percent(.high)),
                     Summary.Zone(label: String(localized: "Very high"), value: percent(.veryHigh))]
        let lines = [String(localized: "Very low \(percent(.veryLow))"), String(localized: "Low \(percent(.low))"),
                     String(localized: "In range \(percent(.inRange))"), String(localized: "High \(percent(.high))"),
                     String(localized: "Very high \(percent(.veryHigh))")]
        let hours = Duration.seconds(Double(settings.rangeHours) * 3600)
        func hoursText(_ width: Duration.UnitsFormatStyle.UnitWidth) -> String {
            hours.formatted(.units(allowed: [.hours], width: width).locale(locale))
        }
        let title = String(localized: "Time in range (\(hoursText(.narrow)))")
        return Summary(inRangeShare: inRange, inRangeText: percent(.inRange), title: title,
                       spokenLabel: String(localized: "Time in range over the last \(hoursText(.wide))"),
                       zones: zones, help: ([title] + lines).joined(separator: "\n"),
                       spokenValue: lines.joined(separator: ", "))
    }
}

/// Every zone's share, in the ring's popover.
private struct ZoneShares: View {
    var summary: TimeInRangeView.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.title).font(.subheadline.weight(.semibold))
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 3) {
                ForEach(summary.zones, id: \.label) { zone in
                    GridRow {
                        Text(zone.label)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(zone.value)
                    }
                }
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .padding(12)
    }
}

private extension View {
    /// Draws the view at `scale` and takes only the scaled room, which `scaleEffect` alone doesn't.
    func scaled(by scale: CGFloat) -> some View {
        ScaledLayout(scale: scale) { scaleEffect(scale) }
    }
}

/// Takes the room of its view at `scale`; the view's own `scaleEffect` draws it at that size.
private struct ScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}
