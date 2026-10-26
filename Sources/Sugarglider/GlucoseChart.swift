import Charts
import SwiftUI

/// Glucose over the window ending at `windowEnd`, with the pump lane under it when pump data is drawn.
struct GlucoseChart: View {
    let readings: [Reading]
    let rangeHours: Int
    let settings: AppSettings
    let windowEnd: Date
    var treatments: [Treatment] = []

    static let laneHeight: CGFloat = 22

    @State private var hover: Hover?
    @State private var width: CGFloat = 0

    /// Identities rather than a position, so moving within one target doesn't redraw.
    private struct Hover: Equatable {
        var readingDate: Date?
        var bolusID: String?
        var noteID: String?
    }

    /// Decided on every cached treatment, not just the window's, so dragging the range can't
    /// make the chart jump in height.
    static func laneSpace(for treatments: [Treatment], settings: AppSettings) -> CGFloat {
        let bars = settings.chartShowsBoluses && treatments.contains { $0.bolusUnits != nil }
        let rate = settings.chartShowsDeliveryRate && treatments.contains(where: \.isTempBasal)
        return bars || rate ? laneHeight : 0
    }

    private static func bolusText(_ units: Double) -> String { String(localized: "Bolus \(PumpFormat.bolus(units))") }

    private static func timeLabel(_ date: Date, span: TimeInterval) -> String {
        date.formatted(ChartMath.labelsNeedDay(span: span)
                       ? .dateTime.weekday().hour().minute()
                       : .dateTime.hour().minute())
    }

    var body: some View {
        if let plot = Plot(self) {
            VStack(spacing: 0) {
                glucose(plot)
                if plot.hasLane {
                    lane(plot)
                        .frame(height: Self.laneHeight)
                        .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 0.5) }
                }
            }
            .background {
                if settings.chartBackgroundEnabled { Self.frame.fill(settings.chartBackgroundColor) }
            }
            .overlay { Self.frame.strokeBorder(.separator) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): updateHover(at: location.x, in: plot)
                case .ended: hover = nil
                }
            }
        } else {
            Text("No data for this range")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Data

    /// Everything the marks are built from, worked out once per update.
    private struct Plot {
        var start: Date
        var end: Date
        var visible: [Reading]
        var latest: Reading
        var axis: ChartMath.ValueAxis
        var units: AppSettings.Units
        var zones: ChartMath.Zones
        var boluses: [Treatment]
        var notes: [Treatment]
        var steps: [ChartMath.DeliveryStep]
        var hasLane: Bool
        var target: HoverTarget? = nil

        var span: TimeInterval { end.timeIntervalSince(start) }

        init?(_ chart: GlucoseChart) {
            let settings = chart.settings
            let end = chart.windowEnd
            let start = end.addingTimeInterval(-Double(chart.rangeHours) * 3600)
            let visible = chart.readings.filter { $0.date >= start }
            guard visible.count >= 2, let latest = visible.last else { return nil }
            let units = settings.units
            let inWindow = chart.treatments.filter { $0.date >= start && $0.date <= end }

            self.start = start
            self.end = end
            self.visible = visible
            self.latest = latest
            self.units = units
            zones = ChartMath.Zones(
                extremeLow: settings.extremeLow, targetLow: settings.targetLow,
                targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
                extremeLowColor: settings.extremeLowColor, belowColor: settings.belowColor,
                inRangeColor: settings.inRangeColor, aboveColor: settings.aboveColor,
                extremeHighColor: settings.extremeHighColor)
            axis = ChartMath.valueAxis(
                values: visible.map { $0.value(in: units) },
                thresholds: [settings.extremeLow, settings.targetLow, settings.targetHigh, settings.extremeHigh]
                    .map { units.value(fromMgdl: $0) },
                mgdl: units == .mgdl)
            boluses = settings.chartShowsBoluses ? inWindow.filter { $0.bolusUnits != nil } : []
            notes = settings.chartShowsAnnouncements ? inWindow.filter { $0.noteText != nil } : []
            steps = settings.chartShowsDeliveryRate
                ? ChartMath.deliverySteps(chart.treatments, from: start, to: end) : []
            hasLane = GlucoseChart.laneSpace(for: chart.treatments, settings: settings) > 0
            if let hover = chart.hover { target = HoverTarget(hover, in: self) }
        }

        /// LOW and HIGH sit at their markers, kept just inside the plot: the mg/dL axis stops at 40,
        /// which would put LOW's 39 under the frame.
        func plotted(_ reading: Reading) -> Double {
            let value = reading.value(in: units)
            guard reading.outOfRange != nil else { return value }
            let inset = (axis.upper - axis.lower) / 100
            return min(max(value, axis.lower + inset), axis.upper - inset)
        }
    }

    // MARK: - Glucose

    private static let cornerRadius: CGFloat = 10
    private static let frame = RoundedRectangle(cornerRadius: cornerRadius)
    // Axis marks resolve the semantic styles (.separator, .tertiary) against the chart's own colors.
    private static let gridLine = Color(nsColor: .separatorColor)
    private static let axisLabel = Color(nsColor: .tertiaryLabelColor)
    private static let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    /// Round dots, for where the sensor read LOW or HIGH.
    private static let boundStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [0, 4])

    private func glucose(_ p: Plot) -> some View {
        let segments = ChartMath.segments(of: p.visible, gapThreshold: ChartMath.dropoutThreshold)
        let runs = segments.flatMap(ChartMath.runs)
        let low = p.units.value(fromMgdl: settings.targetLow), high = p.units.value(fromMgdl: settings.targetHigh)
        let line = LinearGradient(stops: ChartMath.zoneStops(for: p.zones, axis: p.axis, units: p.units,
                                                             blended: settings.blendLineColors),
                                  startPoint: .bottom, endPoint: .top)
        let shade = settings.lineShadingUsesLineColor ? p.zones.inRangeColor.opacity(0.14) : settings.lineShadingColor

        return Chart {
            if low < high {
                RectangleMark(xStart: .value("Start", p.start), xEnd: .value("End", p.end),
                              yStart: .value("Low", low), yEnd: .value("High", high))
                    .foregroundStyle(settings.bandColor)
                    .accessibilityHidden(true)
                ForEach([low, high], id: \.self) { edge in
                    RuleMark(y: .value("Target", edge))
                        .foregroundStyle(settings.bandColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
            }

            ForEach(p.notes, id: \.id) { note in
                PointMark(x: .value("Time", note.date), y: .value("Glucose", p.axis.upper))
                    .symbol {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(settings.announcementColor)
                    }
                    .offset(y: 3)
                    .accessibilityLabel(Self.timeLabel(note.date, span: p.span))
                    .accessibilityValue(note.noteText ?? "")
            }

            if settings.lineShadingEnabled {
                ForEach(segments.indices, id: \.self) { index in
                    ForEach(segments[index], id: \.date) { reading in
                        AreaMark(x: .value("Time", reading.date), yStart: .value("Base", p.axis.lower),
                                 yEnd: .value("Glucose", p.plotted(reading)), series: .value("Segment", index))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [shade, shade.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .alignsMarkStylesWithPlotArea()
                            .accessibilityHidden(true)
                    }
                }
            }

            ForEach(runs.indices, id: \.self) { index in
                ForEach(runs[index].readings, id: \.date) { reading in
                    LineMark(x: .value("Time", reading.date), y: .value("Glucose", p.plotted(reading)),
                             series: .value("Run", index))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(runs[index].beyondRange ? Self.boundStroke : Self.lineStroke)
                        .foregroundStyle(line)
                        .alignsMarkStylesWithPlotArea()
                        .opacity(0.9)
                        .accessibilityLabel(Self.timeLabel(reading.date, span: p.span))
                        .accessibilityValue(reading.text(in: p.units, withUnit: true))
                }
            }

            ForEach(segments.filter { $0.count == 1 }.flatMap(\.self), id: \.date) { reading in
                PointMark(x: .value("Time", reading.date), y: .value("Glucose", p.plotted(reading)))
                    .symbolSize(CGSize(width: 4, height: 4))
                    .foregroundStyle(ChartMath.color(for: reading.sgv, zones: p.zones))
                    .accessibilityLabel(Self.timeLabel(reading.date, span: p.span))
                    .accessibilityValue(reading.text(in: p.units, withUnit: true))
            }

            if let target = p.target {
                Self.crosshair(at: target.date)
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        pill(for: target, in: p)
                            .padding(.top, 6)
                    }
            }
        }
        .chartXScale(domain: p.start...p.end)
        .chartYScale(domain: p.axis.lower...p.axis.upper)
        .chartXAxis {
            AxisMarks(preset: .inset, values: [p.start, p.latest.date]) { value in
                AxisValueLabel(anchor: value.index == 0 ? .bottomLeading : .bottomTrailing) {
                    if let date = value.as(Date.self) { Text(Self.timeLabel(date, span: p.span)) }
                }
                .font(.caption2)
                .foregroundStyle(Self.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks(values: p.axis.levels) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Self.gridLine)
            }
            // A label sits above its line, so only where it fits below the frame and above the time axis.
            AxisMarks(preset: .inset, position: .leading, values: p.axis.levels.filter {
                $0 - p.axis.lower >= p.axis.step * 0.75 && p.axis.upper - $0 >= p.axis.step * 0.75
            }) {
                AxisValueLabel(anchor: .bottomLeading)
                    .font(.caption2)
                    .foregroundStyle(Self.axisLabel)
            }
        }
        .chartPlotStyle { plot in
            let bottomRadius = p.hasLane ? 0 : Self.cornerRadius
            plot.clipShape(UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, bottomLeadingRadius: bottomRadius,
                                                  bottomTrailingRadius: bottomRadius, topTrailingRadius: Self.cornerRadius))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame.map({ geometry[$0] }) {
                    dots(in: p, proxy: proxy).offset(x: plotFrame.minX, y: plotFrame.minY)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Glucose")
    }

    /// Outside the plot's clip, so the latest reading's halo may reach past the frame.
    private func dots(in p: Plot, proxy: ChartProxy) -> some View {
        func position(of reading: Reading) -> CGPoint? {
            proxy.position(for: (x: reading.date, y: p.plotted(reading)))
        }
        let latestColor = dotColor(for: p.latest, zones: p.zones)
        return ZStack(alignment: .topLeading) {
            if let latest = position(of: p.latest) {
                dot(at: latest, radius: settings.dotHaloRadius, color: latestColor.opacity(0.18))
                dot(at: latest, radius: settings.dotRadius, color: latestColor)
            }
            if let reading = p.target?.reading, let point = position(of: reading) {
                // Floored so the crosshair keeps a visible point when the dot is sized away.
                dot(at: point, radius: max(3, settings.dotRadius), color: dotColor(for: reading, zones: p.zones))
            }
        }
    }

    private func dot(at center: CGPoint, radius: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }

    private func dotColor(for reading: Reading, zones: ChartMath.Zones) -> Color {
        settings.dotUsesZoneColor ? ChartMath.color(for: reading.sgv, zones: zones) : settings.dotColor
    }

    // MARK: - Pump lane

    /// Rate and boluses share no axis, so each scales on its own, with a floor (1 U/h, 2 U) so a
    /// quiet stretch or a lone small bolus doesn't stand full height. The top 4 points stay free.
    private func lane(_ p: Plot) -> some View {
        let topRate = max(p.steps.map(\.rate).max() ?? 0, 1)
        let largestBolus = max(p.boluses.compactMap(\.bolusUnits).max() ?? 0, 2)
        let runs = ChartMath.contiguousRuns(p.steps)

        return Chart {
            ForEach(runs.indices, id: \.self) { index in
                // Each step's start, plus the end of the last, held with .stepEnd.
                let run = runs[index]
                let corners = run.map { ($0.start, $0.rate) } + run.suffix(1).map { ($0.end, $0.rate) }
                ForEach(corners.indices, id: \.self) { corner in
                    let (date, rate) = corners[corner]
                    AreaMark(x: .value("Time", date), yStart: .value("Base", 0.0),
                             yEnd: .value("Rate", rate / topRate), series: .value("Run", index))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(settings.deliveryRateColor.opacity(0.3))
                        .accessibilityHidden(true)
                    LineMark(x: .value("Time", date), y: .value("Rate", rate / topRate), series: .value("Run", index))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(settings.deliveryRateColor)
                        .accessibilityLabel(Self.timeLabel(date, span: p.span))
                        .accessibilityValue(PumpFormat.rate(rate))
                }
            }

            ForEach(p.boluses, id: \.id) { bolus in
                let units = bolus.bolusUnits ?? 0
                BarMark(x: .value("Time", bolus.date), yStart: .value("Base", 0.0),
                        yEnd: .value("Units", max(min(units / largestBolus, 1), 0.15)),
                        width: .fixed(2.5))
                    .foregroundStyle(settings.bolusColor)
                    .clipShape(Capsule())
                    .accessibilityLabel(Self.timeLabel(bolus.date, span: p.span))
                    .accessibilityValue(Self.bolusText(units))
            }

            if let target = p.target {
                Self.crosshair(at: target.date)
            }
        }
        .chartXScale(domain: p.start...p.end)
        .chartYScale(domain: 0...Double(Self.laneHeight / (Self.laneHeight - 4)))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.cornerRadius,
                                                  bottomTrailingRadius: Self.cornerRadius))
        }
        .accessibilityLabel("Pump")
    }

    // MARK: - Hover

    private static func crosshair(at date: Date) -> some ChartContent {
        RuleMark(x: .value("Time", date))
            .foregroundStyle(.primary.opacity(0.25))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .accessibilityHidden(true)
    }

    private struct HoverTarget {
        var reading: Reading?
        var bolus: Treatment?
        var note: Treatment?
        var date: Date

        init?(_ hover: Hover, in p: Plot) {
            reading = hover.readingDate.flatMap { date in p.visible.first { $0.date == date } }
            bolus = hover.bolusID.flatMap { id in p.boluses.first { $0.id == id } }
            note = hover.noteID.flatMap { id in p.notes.first { $0.id == id } }
            // Without a reading nearby, as over a gap where a lost-signal alert sits, the event places it.
            guard let date = reading?.date ?? bolus?.date ?? note?.date else { return nil }
            self.date = date
        }
    }

    /// The plot spans the chart's full width, so a position maps to a date linearly.
    private func updateHover(at x: CGFloat, in p: Plot) {
        guard width > 0 else { return }
        let secondsPerPoint = p.span / width
        let date = p.start.addingTimeInterval(x * secondsPerPoint)
        // Events are narrow marks, so they want the pointer much closer than a reading does.
        func nearest(_ dates: [Date], within points: CGFloat) -> Int? {
            ChartMath.nearestIndex(to: date, in: dates, maxDistance: points * secondsPerPoint)
        }
        let next = Hover(
            readingDate: nearest(p.visible.map(\.date), within: 24).map { p.visible[$0].date },
            bolusID: nearest(p.boluses.map(\.date), within: 6).map { p.boluses[$0].id },
            noteID: nearest(p.notes.map(\.date), within: 6).map { p.notes[$0].id })
        hover = next == Hover() ? nil : next
    }

    private func pill(for target: HoverTarget, in p: Plot) -> some View {
        let time = Self.timeLabel(target.date, span: p.span)
        let insulin = [target.bolus?.bolusUnits.map(Self.bolusText),
                       ChartMath.rate(at: target.date, in: p.steps).map(PumpFormat.rate)].compactMap(\.self)
        return HoverPill(title: target.reading.map { "\($0.text(in: p.units)) · \(time)" } ?? time,
                         insulin: insulin.isEmpty ? nil : insulin.joined(separator: " · "),
                         note: target.note?.noteText)
            .frame(maxWidth: 240)
    }
}

private struct HoverPill: View {
    let title: String
    let insulin: String?
    let note: String?

    var body: some View {
        // Concrete colors: the panel would make semantic styles vibrant, blending them with what's
        // behind the window instead of with this background.
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Group {
                if let insulin { Text(insulin) }
                if let note { Text(note).lineLimit(4) }
            }
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .foregroundStyle(Color(nsColor: .labelColor))
        .font(.caption)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        // Solid, not glass: it annotates content, and a backdrop inside the plot's clip renders garbage.
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}
