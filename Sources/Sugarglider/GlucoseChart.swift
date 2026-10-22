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

    static func clipped(_ message: String, limit: Int = 160) -> String {
        message.count <= limit ? message : String(message.prefix(limit - 1)) + "…"
    }

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
        }

        /// LOW and HIGH sit at their markers, kept just inside the plot: the mg/dL axis stops at 40,
        /// which would put LOW's 39 under the frame.
        func plotted(_ reading: Reading) -> Double {
            let value = reading.value(in: units)
            guard reading.outOfRange != nil else { return value }
            let inset = (axis.hi - axis.lo) / 100
            return min(max(value, axis.lo + inset), axis.hi - inset)
        }
    }

    // MARK: - Glucose

    private static let frame = RoundedRectangle(cornerRadius: 10)
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
        let target = hoverTarget(in: p)

        return Chart {
            if low < high {
                RectangleMark(xStart: .value("Start", p.start), xEnd: .value("End", p.end),
                              yStart: .value("Low", low), yEnd: .value("High", high))
                    .foregroundStyle(settings.bandColor)
                ForEach([low, high], id: \.self) { edge in
                    RuleMark(y: .value("Target", edge))
                        .foregroundStyle(settings.bandColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }

            ForEach(p.notes, id: \.id) { note in
                PointMark(x: .value("Time", note.date), y: .value("Glucose", p.axis.hi))
                    .symbol {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(settings.announcementColor)
                    }
                    .offset(y: 3)
            }

            if settings.lineShadingEnabled {
                ForEach(segments.indices, id: \.self) { index in
                    ForEach(segments[index], id: \.date) { reading in
                        AreaMark(x: .value("Time", reading.date), yStart: .value("Base", p.axis.lo),
                                 yEnd: .value("Glucose", p.plotted(reading)), series: .value("Segment", index))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [shade, shade.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .alignsMarkStylesWithPlotArea()
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
                }
            }

            ForEach(segments.filter { $0.count == 1 }.flatMap(\.self), id: \.date) { reading in
                PointMark(x: .value("Time", reading.date), y: .value("Glucose", p.plotted(reading)))
                    .symbolSize(CGSize(width: 4, height: 4))
                    .foregroundStyle(ChartMath.color(for: reading.sgv, zones: p.zones))
            }

            if let target {
                RuleMark(x: .value("Time", target.date))
                    .foregroundStyle(.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        pill(for: target, in: p)
                            .padding(.top, 6)
                    }
            }
        }
        .chartXScale(domain: p.start...p.end)
        .chartYScale(domain: p.axis.lo...p.axis.hi)
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
                $0 - p.axis.lo >= p.axis.step * 0.75 && p.axis.hi - $0 >= p.axis.step * 0.75
            }) {
                AxisValueLabel(anchor: .bottomLeading)
                    .font(.caption2)
                    .foregroundStyle(Self.axisLabel)
            }
        }
        .chartPlotStyle { plot in
            plot.clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: p.hasLane ? 0 : 10,
                                                  bottomTrailingRadius: p.hasLane ? 0 : 10, topTrailingRadius: 10))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame.map({ geometry[$0] }) {
                    dots(target: target, in: p, proxy: proxy).offset(x: plotFrame.minX, y: plotFrame.minY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Outside the plot's clip, so the latest reading's halo may reach past the frame.
    private func dots(target: HoverTarget?, in p: Plot, proxy: ChartProxy) -> some View {
        func position(of reading: Reading) -> CGPoint? {
            proxy.position(for: (x: reading.date, y: p.plotted(reading)))
        }
        let latestColor = dotColor(for: p.latest, zones: p.zones)
        return ZStack(alignment: .topLeading) {
            if let latest = position(of: p.latest) {
                dot(at: latest, radius: settings.dotHaloRadius, color: latestColor.opacity(0.18))
                dot(at: latest, radius: settings.dotRadius, color: latestColor)
            }
            if let reading = target?.reading, let point = position(of: reading) {
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
        let target = hoverTarget(in: p)

        return Chart {
            ForEach(runs.indices, id: \.self) { index in
                // Each step's start, plus the end of the last, held with .stepEnd.
                let corners = runs[index].map { ($0.start, $0.rate) } + [(runs[index].last!.end, runs[index].last!.rate)]
                ForEach(corners.indices, id: \.self) { corner in
                    let (date, rate) = corners[corner]
                    AreaMark(x: .value("Time", date), yStart: .value("Base", 0.0),
                             yEnd: .value("Rate", rate / topRate), series: .value("Run", index))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(settings.deliveryRateColor.opacity(0.3))
                    LineMark(x: .value("Time", date), y: .value("Rate", rate / topRate), series: .value("Run", index))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(settings.deliveryRateColor)
                }
            }

            ForEach(p.boluses, id: \.id) { bolus in
                BarMark(x: .value("Time", bolus.date), yStart: .value("Base", 0.0),
                        yEnd: .value("Units", max(min((bolus.bolusUnits ?? 0) / largestBolus, 1), 0.15)),
                        width: .fixed(2.5))
                    .foregroundStyle(settings.bolusColor)
                    .clipShape(Capsule())
            }

            if let target {
                RuleMark(x: .value("Time", target.date))
                    .foregroundStyle(.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: p.start...p.end)
        .chartYScale(domain: 0...(Self.laneHeight / (Self.laneHeight - 4)))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
        }
    }

    // MARK: - Hover

    private struct HoverTarget {
        var reading: Reading?
        var bolus: Treatment?
        var note: Treatment?
        var date: Date
    }

    private func hoverTarget(in p: Plot) -> HoverTarget? {
        guard let hover else { return nil }
        let reading = hover.readingDate.flatMap { date in p.visible.first { $0.date == date } }
        let bolus = hover.bolusID.flatMap { id in p.boluses.first { $0.id == id } }
        let note = hover.noteID.flatMap { id in p.notes.first { $0.id == id } }
        // Without a reading nearby, as over a gap where a lost-signal alert sits, the event places it.
        guard let date = reading?.date ?? bolus?.date ?? note?.date else { return nil }
        return HoverTarget(reading: reading, bolus: bolus, note: note, date: date)
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
        let insulin = [target.bolus?.bolusUnits.map { String(localized: "Bolus \(PumpFormat.bolus($0))") },
                       ChartMath.rate(at: target.date, in: p.steps).map(PumpFormat.rate)].compactMap(\.self)
        return HoverPill(title: target.reading.map { "\($0.text(in: p.units)) · \(time)" } ?? time,
                         insulin: insulin.isEmpty ? nil : insulin.joined(separator: " · "),
                         note: target.note?.noteText.map { Self.clipped($0) })
            .frame(maxWidth: 240)
    }
}

private struct HoverPill: View {
    let title: String
    let insulin: String?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Group {
                if let insulin { Text(insulin) }
                if let note { Text(note) }
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }
}
