import AppKit
import SwiftUI

struct ChartCanvas: View {
    let readings: [Reading]
    let rangeHours: Int
    let settings: AppSettings
    /// nil follows the wall clock. Settings' preview pins its sample data's end instead: `Canvas`
    /// redraws on its own schedule, so samples on a wall-clock window aged out of range.
    var windowEnd: Date?
    var treatments: [Treatment] = []

    static let laneHeight: CGFloat = 22

    /// Identities rather than a position, so moving within one target doesn't redraw.
    private struct Hover: Equatable {
        var readingIndex: Int?
        var bolusID: String?
        var noteID: String?
    }

    @State private var hover: Hover?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
            .overlay { hoverPill }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): updateHover(at: location)
                case .ended: hover = nil
                }
            }
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

    private static let clockFormatter = dateFormatter("HH:mm")
    private static let weekdayClockFormatter = dateFormatter("E HH:mm")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }

    private static func timeLabel(_ date: Date, span: TimeInterval) -> String {
        (ChartMath.labelsNeedDay(span: span) ? weekdayClockFormatter : clockFormatter).string(from: date)
    }

    // MARK: - Geometry

    /// Drawing, hit-testing and the hover pill all map through this, so they can't disagree
    /// about where anything sits.
    private struct Layout {
        var visible: [Reading]
        var latest: Reading
        /// Flipped chart space, where `minY` is the bottom edge; `lane` too.
        var plot: CGRect
        var lane: CGRect?
        var size: CGSize
        var start: Date
        var end: Date
        var lo: Double
        var hi: Double
        var units: AppSettings.Units
        var boluses: [Treatment]
        var notes: [Treatment]
        var steps: [ChartMath.DeliveryStep]

        var span: TimeInterval { end.timeIntervalSince(start) }

        func x(_ date: Date) -> CGFloat {
            plot.minX + CGFloat(date.timeIntervalSince(start) / span) * plot.width
        }

        /// Takes display units, unlike `bandY(mgdl:)`.
        func y(_ value: Double) -> CGFloat {
            plot.minY + CGFloat((value - lo) / (hi - lo)) * plot.height
        }

        func y(of reading: Reading) -> CGFloat { y(units.value(fromMgdl: reading.sgv)) }

        /// Clamped into the plot, since zone bands exist even where their threshold is off the axis.
        func bandY(mgdl: Double) -> CGFloat {
            min(max(y(units.display(mgdl)), plot.minY), plot.maxY)
        }

        /// Back to the unflipped context, where text is drawn.
        func screenY(_ chartY: CGFloat) -> CGFloat { size.height - chartY }

        func target(of hover: Hover) -> HoverTarget? {
            let reading = hover.readingIndex.flatMap { visible.indices.contains($0) ? visible[$0] : nil }
            let bolus = hover.bolusID.flatMap { id in boluses.first { $0.id == id } }
            let note = hover.noteID.flatMap { id in notes.first { $0.id == id } }
            guard let date = reading?.date ?? bolus?.date ?? note?.date else { return nil }
            return HoverTarget(reading: reading, bolus: bolus, note: note, date: date)
        }
    }

    private struct HoverTarget {
        var reading: Reading?
        var bolus: Treatment?
        var note: Treatment?
        var date: Date
    }

    private func layout(size: CGSize) -> Layout? {
        let end = windowEnd ?? .now
        let start = end.addingTimeInterval(-Double(rangeHours) * 3600)
        let visible = readings.filter { $0.date >= start }
        guard visible.count >= 2, let latest = visible.last else { return nil }

        let leftInset: CGFloat = 0.5, topInset: CGFloat = 10, bottomInset: CGFloat = 16
        // Room for the latest dot's halo at the right edge, capped so a big halo can't squeeze a
        // narrow chart away.
        let rightInset = min(max(0.5, settings.dotRadius, settings.dotHaloRadius), size.width / 4)
        let laneSpace = Self.laneSpace(for: treatments, settings: settings)
        let plot = CGRect(x: leftInset, y: bottomInset + laneSpace,
                          width: size.width - leftInset - rightInset,
                          height: size.height - topInset - bottomInset - laneSpace)
        let lane = laneSpace > 0
            ? CGRect(x: plot.minX, y: bottomInset, width: plot.width, height: laneSpace)
            : nil

        let inWindow = treatments.filter { $0.date >= start && $0.date <= end }
        let boluses = settings.chartShowsBoluses ? inWindow.filter { $0.bolusUnits != nil } : []
        let notes = settings.chartShowsAnnouncements ? inWindow.filter { $0.noteText != nil } : []
        let steps = settings.chartShowsDeliveryRate
            ? ChartMath.deliverySteps(treatments, from: start, to: end) : []

        let units = settings.units
        let mgdl = units == .mgdl
        let targetLow = units.display(settings.targetLow), targetHigh = units.display(settings.targetHigh)
        let pad = mgdl ? 10.0 : 0.5, minSpan = mgdl ? 40.0 : 2.0
        let clampLow = mgdl ? 40.0 : 2.0, clampHigh = mgdl ? 500.0 : 28.0
        let values = visible.map { units.value(fromMgdl: $0.sgv) }
        let lo = max(clampLow, (min(values.min() ?? targetLow, targetLow) - pad).rounded(.down))
        let hi = max(min(clampHigh, (max(values.max() ?? targetHigh, targetHigh) + pad).rounded(.up)),
                     lo + minSpan)

        return Layout(visible: visible, latest: latest, plot: plot, lane: lane, size: size,
                      start: start, end: end, lo: lo, hi: hi, units: units,
                      boluses: boluses, notes: notes, steps: steps)
    }

    // MARK: - Drawing

    private typealias Band = (bottom: CGFloat, top: CGFloat, color: Color)

    private static let ink = Color(nsColor: .labelColor)
    private static let separator = Color(nsColor: .separatorColor)
    private static let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

    private var zones: ChartMath.Zones {
        ChartMath.Zones(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            extremeLowColor: settings.extremeLowColor, belowColor: settings.belowColor,
            inRangeColor: settings.inRangeColor, aboveColor: settings.aboveColor,
            extremeHighColor: settings.extremeHighColor
        )
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        guard let l = layout(size: size) else {
            context.draw(Text("No data for this range").font(.system(size: 11)).foregroundStyle(.secondary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        // y grows upward in `chart`. Text stays in `context`, or its glyphs would be mirrored.
        var chart = context
        chart.translateBy(x: 0, y: size.height)
        chart.scaleBy(x: 1, y: -1)

        // The lane shares the plot's frame so it reads as part of the chart, not as a control.
        let frame = Path(roundedRect: l.lane.map { l.plot.union($0) } ?? l.plot, cornerRadius: 10)
        if settings.chartBackgroundEnabled {
            chart.fill(frame, with: .color(settings.chartBackgroundColor))
        }
        chart.stroke(frame, with: .color(Self.separator.opacity(0.4)), lineWidth: 1)

        var framed = chart
        framed.clip(to: frame)
        var plot = framed
        if l.lane != nil { plot.clip(to: Path(l.plot)) }

        let timeLabels = timeAxisLabels(context, layout: l)
        drawGridlines(plot, labels: context, layout: l, avoiding: timeLabels.map(\.frame))
        drawTargetBand(plot, layout: l)
        drawAnnouncements(plot, layout: l)
        drawLine(plot, unclipped: chart, layout: l)
        drawLane(framed, layout: l)
        timeLabels.forEach { $0.draw(in: context) }
        drawHover(chart, layout: l)
    }

    private struct PlacedText {
        var text: GraphicsContext.ResolvedText
        var point: CGPoint
        var anchor: UnitPoint

        var frame: CGRect {
            let size = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: .greatestFiniteMagnitude))
            return CGRect(x: point.x - anchor.x * size.width, y: point.y - anchor.y * size.height,
                          width: size.width, height: size.height)
        }

        func draw(in context: GraphicsContext) { context.draw(text, at: point, anchor: anchor) }
    }

    private static func axisText(_ string: String) -> Text {
        Text(string).font(.system(size: 9)).foregroundStyle(.tertiary)
    }

    private static func horizontalLine(at y: CGFloat, across rect: CGRect) -> Path {
        var line = Path()
        line.move(to: CGPoint(x: rect.minX, y: y))
        line.addLine(to: CGPoint(x: rect.maxX, y: y))
        return line
    }

    private func timeAxisLabels(_ context: GraphicsContext, layout l: Layout) -> [PlacedText] {
        let baseline = l.screenY(l.plot.minY) - 2
        let ends: [(date: Date, x: CGFloat, anchor: UnitPoint)] = [
            (l.start, l.plot.minX, .bottomLeading),
            (l.latest.date, l.plot.maxX, .bottomTrailing),
        ]
        return ends.map { end in
            PlacedText(text: context.resolve(Self.axisText(Self.timeLabel(end.date, span: l.span))),
                       point: CGPoint(x: end.x, y: baseline), anchor: end.anchor)
        }
    }

    private func drawGridlines(_ ctx: GraphicsContext, labels: GraphicsContext, layout l: Layout,
                               avoiding taken: [CGRect]) {
        let step = ChartMath.niceStep(l.hi - l.lo)
        for level in stride(from: (l.lo / step).rounded(.up) * step, through: l.hi, by: step) {
            let y = l.y(level)
            ctx.stroke(Self.horizontalLine(at: y, across: l.plot),
                       with: .color(Self.separator.opacity(0.35)), lineWidth: 0.5)

            let labelY = min(max(y + 2, l.plot.minY + 1), l.plot.maxY - 11)
            let label = PlacedText(text: labels.resolve(Self.axisText(String(format: "%g", level))),
                                   point: CGPoint(x: l.plot.minX + 5, y: l.screenY(labelY)),
                                   anchor: .bottomLeading)
            if !taken.contains(where: { $0.intersects(label.frame) }) {
                label.draw(in: labels)
            }
        }
    }

    private func drawTargetBand(_ ctx: GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let yLow = l.y(l.units.display(settings.targetLow))
        let yHigh = l.y(l.units.display(settings.targetHigh))
        let bottom = max(min(yLow, yHigh), plot.minY), top = min(max(yLow, yHigh), plot.maxY)
        guard top > bottom else { return }

        ctx.fill(Path(CGRect(x: plot.minX, y: bottom, width: plot.width, height: top - bottom)),
                 with: .color(settings.bandColor))
        for y in [bottom, top] {
            ctx.stroke(Self.horizontalLine(at: y, across: plot), with: .color(settings.bandColor.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawAnnouncements(_ ctx: GraphicsContext, layout l: Layout) {
        let top = l.plot.maxY
        for note in l.notes {
            let x = l.x(note.date)
            var mark = Path()
            mark.addLines([CGPoint(x: x - 3.5, y: top), CGPoint(x: x + 3.5, y: top), CGPoint(x: x, y: top - 5)])
            mark.closeSubpath()
            ctx.fill(mark, with: .color(Self.ink.opacity(0.45)))
        }
    }

    /// The latest-reading dot goes into `unclipped`, so its halo may bleed past the frame's corners.
    private func drawLine(_ ctx: GraphicsContext, unclipped: GraphicsContext, layout l: Layout) {
        let plot = l.plot, zones = self.zones
        let extremeLowY = l.bandY(mgdl: settings.extremeLow), lowY = l.bandY(mgdl: settings.targetLow)
        let highY = l.bandY(mgdl: settings.targetHigh), extremeHighY = l.bandY(mgdl: settings.extremeHigh)
        let bands: [Band] = [
            (plot.minY, extremeLowY, zones.extremeLowColor),
            (extremeLowY, lowY, zones.belowColor),
            (lowY, highY, zones.inRangeColor),
            (highY, extremeHighY, zones.aboveColor),
            (extremeHighY, plot.maxY, zones.extremeHighColor),
        ]

        for segment in ChartMath.segments(of: l.visible, gapThreshold: ChartMath.dropoutThreshold) {
            let points = segment.map { CGPoint(x: l.x($0.date), y: l.y(of: $0)) }
            guard points.count > 1, let first = points.first, let last = points.last else {
                if let point = points.first, let reading = segment.first {
                    dot(ctx, at: point, radius: 2, color: ChartMath.color(for: reading.sgv, zones: zones))
                }
                continue
            }
            let path = ChartMath.smooth(points)
            if settings.lineShadingEnabled {
                fillUnder(ctx, path: path, from: first.x, to: last.x, plot: plot, zones: zones)
            }
            if settings.blendLineColors {
                strokeBlended(ctx, path: path, bands: bands, plot: plot)
            } else {
                for band in bands where band.top - band.bottom > 0.5 {
                    var clipped = ctx
                    clipped.clip(to: Path(CGRect(x: plot.minX, y: band.bottom,
                                                 width: plot.width, height: band.top - band.bottom)))
                    clipped.stroke(path, with: .color(band.color.opacity(0.9)), style: Self.lineStroke)
                }
            }
        }

        let latest = CGPoint(x: l.x(l.latest.date), y: l.y(of: l.latest))
        let color = dotColor(for: l.latest, zones: zones)
        if settings.dotHaloRadius > 0 {
            dot(unclipped, at: latest, radius: settings.dotHaloRadius, color: color.opacity(0.18))
        }
        if settings.dotRadius > 0 {
            dot(unclipped, at: latest, radius: settings.dotRadius, color: color)
        }
    }

    private func fillUnder(_ ctx: GraphicsContext, path: Path, from minX: CGFloat, to maxX: CGFloat,
                           plot: CGRect, zones: ChartMath.Zones) {
        let shade = settings.lineShadingUsesLineColor
            ? zones.inRangeColor.opacity(0.14)
            : settings.lineShadingColor
        var area = path
        area.addLine(to: CGPoint(x: maxX, y: plot.minY))
        area.addLine(to: CGPoint(x: minX, y: plot.minY))
        area.closeSubpath()
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [shade, shade.opacity(0)]),
            startPoint: CGPoint(x: plot.midX, y: plot.maxY), endPoint: CGPoint(x: plot.midX, y: plot.minY)))
    }

    private func strokeBlended(_ ctx: GraphicsContext, path: Path, bands: [Band], plot: CGRect) {
        let stops = bands.filter { $0.top - $0.bottom > 0.5 }.map { band in
            Gradient.Stop(color: band.color.opacity(0.9),
                          location: min(max(((band.bottom + band.top) / 2 - plot.minY) / plot.height, 0), 1))
        }
        guard !stops.isEmpty else { return }
        ctx.stroke(path, with: .linearGradient(
            Gradient(stops: stops.sorted { $0.location < $1.location }),
            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)),
            style: Self.lineStroke)
    }

    /// Rate and boluses share no axis, so each scales on its own, with a floor (1 U/h, 2 U) so a
    /// quiet stretch or a lone small bolus doesn't stand full height.
    private func drawLane(_ ctx: GraphicsContext, layout l: Layout) {
        guard let lane = l.lane else { return }
        ctx.stroke(Self.horizontalLine(at: lane.maxY, across: lane),
                   with: .color(Self.separator.opacity(0.6)), lineWidth: 0.5)
        let headroom: CGFloat = 4
        let usable = lane.height - headroom

        let topRate = max(l.steps.map(\.rate).max() ?? 0, 1)
        for run in ChartMath.contiguousRuns(l.steps) {
            guard let first = run.first, let last = run.last else { continue }
            var edge = Path()
            for step in run {
                let y = lane.minY + usable * CGFloat(step.rate / topRate)
                let from = CGPoint(x: l.x(step.start), y: y)
                if edge.isEmpty { edge.move(to: from) } else { edge.addLine(to: from) }
                edge.addLine(to: CGPoint(x: l.x(step.end), y: y))
            }
            var area = edge
            area.addLine(to: CGPoint(x: l.x(last.end), y: lane.minY))
            area.addLine(to: CGPoint(x: l.x(first.start), y: lane.minY))
            area.closeSubpath()
            ctx.fill(area, with: .color(Self.ink.opacity(0.12)))
            ctx.stroke(edge, with: .color(Self.ink.opacity(0.4)), lineWidth: 1)
        }

        let largest = max(l.boluses.compactMap(\.bolusUnits).max() ?? 0, 2)
        for bolus in l.boluses {
            guard let units = bolus.bolusUnits else { continue }
            let height = max(3, usable * CGFloat(min(units / largest, 1)))
            let bar = CGRect(x: l.x(bolus.date) - 1.25, y: lane.minY, width: 2.5, height: height)
            ctx.fill(Path(roundedRect: bar, cornerRadius: 1.25), with: .color(Self.ink.opacity(0.6)))
        }
    }

    private func drawHover(_ chart: GraphicsContext, layout l: Layout) {
        guard let hover, let target = l.target(of: hover) else { return }
        let x = l.x(target.date)
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: x, y: l.lane?.minY ?? l.plot.minY))
        crosshair.addLine(to: CGPoint(x: x, y: l.plot.maxY))
        chart.stroke(crosshair, with: .color(Self.ink.opacity(0.25)), lineWidth: 1)

        if let reading = target.reading {
            // Floored so the crosshair keeps a visible point when the dot is sized away.
            dot(chart, at: CGPoint(x: x, y: l.y(of: reading)),
                radius: max(3, settings.dotRadius), color: dotColor(for: reading, zones: zones))
        }
    }

    private func dotColor(for reading: Reading, zones: ChartMath.Zones) -> Color {
        settings.dotUsesZoneColor ? ChartMath.color(for: reading.sgv, zones: zones) : settings.dotColor
    }

    private func dot(_ ctx: GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: bounds), with: .color(color))
    }

    // MARK: - Hover

    @ViewBuilder private var hoverPill: some View {
        if let hover, let l = layout(size: canvasSize), let target = l.target(of: hover) {
            let time = Self.timeLabel(target.date, span: l.span)
            let insulin = [target.bolus?.bolusUnits.map { "Bolus " + PumpFormat.bolus($0) },
                           ChartMath.rate(at: target.date, in: l.steps).map(PumpFormat.rate)].compactMap { $0 }
            PillPlacement(centerX: l.x(target.date), minX: l.plot.minX + 4, maxX: l.plot.maxX - 4,
                          top: l.screenY(l.plot.maxY) + 6) {
                HoverPill(title: target.reading.map { "\($0.text(in: l.units)) · \(time)" } ?? time,
                          insulin: insulin.isEmpty ? nil : insulin.joined(separator: " · "),
                          note: target.note?.noteText.map { Self.clipped($0) })
            }
            .allowsHitTesting(false)
        }
    }

    private func updateHover(at location: CGPoint) {
        guard let l = layout(size: canvasSize) else { return }
        // Events are narrow marks, so they want the pointer much closer than a reading does.
        func nearestID(in events: [Treatment]) -> String? {
            ChartMath.nearestIndex(to: location.x, x: l.x, dates: events.map(\.date), maxDistance: 6)
                .map { events[$0].id }
        }
        let target = Hover(
            readingIndex: ChartMath.nearestIndex(to: location.x, x: l.x, in: l.visible, maxDistance: 24),
            bolusID: nearestID(in: l.boluses), noteID: nearestID(in: l.notes))
        let next = target == Hover() ? nil : target
        if next != hover { hover = next }
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
        .font(.system(size: 10))
        .monospacedDigit()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }
}

/// Centers the pill on the crosshair, kept between `minX` and `maxX`, and wraps its text at
/// that width.
private struct PillPlacement: SwiftUI.Layout {
    let centerX: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let top: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let pill = subviews.first else { return }
        let size = pill.sizeThatFits(ProposedViewSize(width: max(maxX - minX, 0), height: nil))
        let x = max(minX, min(centerX - size.width / 2, maxX - size.width))
        pill.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + top), proposal: ProposedViewSize(size))
    }
}
