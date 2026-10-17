import SwiftUI
import AppKit

/// A small line chart of recent glucose readings, on a transparent background
/// so the menu's material shows through. Hover to read a value and its time.
///
/// Drawing happens in a flipped sub-context (y growing upward, the conventional
/// chart coordinate space); text goes through the unflipped top-level context
/// so glyphs aren't mirrored, with y converted via `Layout.screenY(_:)`.
///
/// Pump data adds two layers, each behind its own switch in Settings: an
/// insulin lane under the plot (boluses as bars, the delivery rate as a step
/// area) and announcement marks along the plot's top edge. Neither has an
/// axis; the hover pill reads the numbers and texts out.
struct ChartCanvas: View {
    var readings: [Reading]
    var rangeHours: Int
    var settings: AppSettings
    /// Where the window ends. The live chart leaves this nil and anchors to the
    /// wall clock, which is what makes a stopped feed show as a growing gap at
    /// the right edge. Settings' preview pins it to its sample data's end
    /// instead: that data is generated when the body runs while `Canvas` redraws
    /// on its own schedule, so on a wall-clock window the samples aged out of
    /// range and the preview went blank until some edit re-ran the body.
    var windowEnd: Date?
    /// Boluses, temp basals and announcements. Which of them get drawn is up to
    /// the chart switches in `settings`; the Settings preview passes none.
    var treatments: [Treatment] = []

    /// What the pointer is over. Identities rather than a position, so moving
    /// within one target doesn't redraw the whole chart.
    private struct Hover: Equatable {
        var reading: Int?    // index into `Layout.visible`
        var bolus: String?   // treatment ids
        var note: String?
    }

    @State private var hover: Hover?
    /// `.onContinuousHover` doesn't hand us the view's size, hence the
    /// GeometryReader in the background.
    @State private var lastSize: CGSize = .zero

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Used on wide windows, see `ChartMath.labelsNeedDay`. Fixed 24h like
    /// `timeFmt` so both variants read alike; the weekday still localizes.
    private static let dayTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E HH:mm"
        return f
    }()

    private static func timeLabel(_ date: Date, span: TimeInterval) -> String {
        (ChartMath.labelsNeedDay(span: span) ? dayTimeFmt : timeFmt).string(from: date)
    }

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                updateHover(at: location, size: lastSize)
            case .ended:
                hover = nil
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, new in lastSize = new }
        })
    }

    // MARK: - Geometry (shared between draw and hover)

    /// Everything the drawing and the hover hit-test need to map a reading to a
    /// point. Both go through `x(_:)`/`y(_:)`, so they can't disagree.
    private struct Layout {
        var visible: [Reading]
        var plot: CGRect       // in flipped chart space: minY = bottom, maxY = top
        var lane: CGRect?      // the insulin lane under the plot, same space
        var size: CGSize       // the whole canvas, for converting back to screen space
        var start: Date
        var end: Date
        var lo: Double
        var hi: Double
        var units: AppSettings.Units
        // The window's treatments, for the layers that are switched on.
        var boluses: [Treatment]
        var notes: [Treatment]
        var steps: [ChartMath.DeliveryStep]

        func x(_ date: Date) -> CGFloat {
            plot.minX + CGFloat(date.timeIntervalSince(start) / end.timeIntervalSince(start)) * plot.width
        }

        /// Chart space, y up. Takes a value in display units.
        func y(_ value: Double) -> CGFloat {
            plot.minY + CGFloat((value - lo) / (hi - lo)) * plot.height
        }

        /// `y(_:)` for an mg/dL value, clamped into the plot: threshold lines
        /// and zone bands exist even when they fall off the axis.
        func bandY(mgdl: Double) -> CGFloat {
            min(max(y(units.display(mgdl)), plot.minY), plot.maxY)
        }

        func y(of reading: Reading) -> CGFloat { y(units.value(fromMgdl: reading.sgv)) }

        /// Back to the unflipped context's coordinates, for text.
        func screenY(_ chartY: CGFloat) -> CGFloat { size.height - chartY }

        var span: TimeInterval { end.timeIntervalSince(start) }
    }

    private func layout(size: CGSize) -> Layout? {
        let leftInset: CGFloat = 0.5
        // The newest reading sits on the plot's right edge, so its dot and halo
        // need room there or the frame clips them in half. Capped so a big halo
        // can't squeeze a narrow chart out of existence.
        let rightInset = min(max(0.5, settings.dotRadius, settings.dotHaloRadius), size.width / 4)
        let topInset: CGFloat = 10, bottomInset: CGFloat = 16
        let laneSpace = Self.laneSpace(for: treatments, settings: settings)
        let plot = CGRect(
            x: leftInset, y: bottomInset + laneSpace,
            width: size.width - leftInset - rightInset,
            height: size.height - topInset - bottomInset - laneSpace
        )
        let lane = laneSpace > 0
            ? CGRect(x: plot.minX, y: bottomInset, width: plot.width, height: laneSpace)
            : nil

        let now = windowEnd ?? Date()
        let start = now.addingTimeInterval(-Double(rangeHours) * 3600)
        let visible = readings.filter { $0.date >= start }
        guard visible.count >= 2 else { return nil }

        let inWindow = treatments.filter { $0.date >= start && $0.date <= now }
        let boluses = settings.chartShowsBoluses ? inWindow.filter { $0.bolusUnits != nil } : []
        let notes = settings.chartShowsAnnouncements ? inWindow.filter { $0.noteText != nil } : []
        let steps = settings.chartShowsDeliveryRate
            ? ChartMath.deliverySteps(treatments, from: start, to: now) : []

        let units = settings.units
        let mgdl = units == .mgdl
        let targetLow = units.display(settings.targetLow), targetHigh = units.display(settings.targetHigh)

        let pad = mgdl ? 10.0 : 0.5
        let clampLow = mgdl ? 40.0 : 2.0, clampHigh = mgdl ? 500.0 : 28.0
        let minSpan = mgdl ? 40.0 : 2.0
        let values = visible.map { units.value(fromMgdl: $0.sgv) }
        var lo = min(values.min() ?? targetLow, targetLow) - pad
        var hi = max(values.max() ?? targetHigh, targetHigh) + pad
        lo = max(clampLow, lo.rounded(.down))
        hi = min(clampHigh, hi.rounded(.up))
        if hi - lo < minSpan { hi = lo + minSpan }

        return Layout(visible: visible, plot: plot, lane: lane, size: size,
                      start: start, end: now, lo: lo, hi: hi, units: units,
                      boluses: boluses, notes: notes, steps: steps)
    }

    static let laneHeight: CGFloat = 22

    /// What the insulin lane adds to the canvas, or 0 when there's none: it's
    /// there while boluses or the delivery rate are switched on and the site
    /// reported any. Static because the dropdown has to size the canvas by the
    /// same answer. The canvas grows by this rather than the lane squeezing
    /// the plot. Decided on the cached treatments rather than the window's, so
    /// dragging the range slider can't make the chart jump in height.
    static func laneSpace(for treatments: [Treatment], settings: AppSettings) -> CGFloat {
        let bars = settings.chartShowsBoluses && treatments.contains { $0.bolusUnits != nil }
        let rate = settings.chartShowsDeliveryRate && treatments.contains(where: \.isTempBasal)
        return bars || rate ? laneHeight : 0
    }

    // MARK: - Draw

    private func draw(context ctx0: GraphicsContext, size: CGSize) {
        guard let l = layout(size: size) else {
            ctx0.draw(Text("No data for this range").font(.system(size: 11)).foregroundStyle(.secondary),
                      at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        // Flipped context: y grows upward, so `Layout`'s math reads like a
        // conventional bottom-up chart. `ctx0` stays unflipped, for text.
        var chart = ctx0
        chart.translateBy(x: 0, y: size.height)
        chart.scaleBy(x: 1, y: -1)

        // One frame around the plot and the insulin lane, so the lane reads as
        // part of the chart rather than as a control of its own.
        let clipPath = Path(roundedRect: l.lane.map { l.plot.union($0) } ?? l.plot, cornerRadius: 10)

        if settings.chartBackgroundEnabled {
            chart.fill(clipPath, with: .color(settings.chartBackgroundColor))
        }

        // Drawn before the clip, so the stroke itself isn't clipped.
        chart.stroke(clipPath, with: .color(Color(nsColor: .separatorColor).opacity(0.4)), lineWidth: 1)

        var framed = chart
        framed.clip(to: clipPath)
        // The glucose layers stop where the lane begins. Without a lane the
        // frame is the plot already.
        var inner = framed
        if l.lane != nil { inner.clip(to: Path(l.plot)) }

        drawGridlines(inner, text: ctx0, layout: l)
        drawTargetBand(inner, layout: l)
        drawAnnouncements(inner, layout: l)
        drawLine(inner, chart: &chart, layout: l)
        drawLane(framed, layout: l)
        drawTimeAxis(ctx0, layout: l)
        drawHover(ctx0, chart: &chart, layout: l)
    }

    /// Small marks hanging from the plot's top edge, one per announcement. The
    /// text is long, often a whole alarm message, so it's left to the hover.
    private func drawAnnouncements(_ ctx: GraphicsContext, layout l: Layout) {
        for note in l.notes {
            let x = l.x(note.date), top = l.plot.maxY
            var mark = Path()
            mark.move(to: CGPoint(x: x - 3.5, y: top))
            mark.addLine(to: CGPoint(x: x + 3.5, y: top))
            mark.addLine(to: CGPoint(x: x, y: top - 5))
            mark.closeSubpath()
            ctx.fill(mark, with: .color(Self.ink.opacity(0.45)))
        }
    }

    /// The insulin lane, inside the chart's frame under a hairline: the
    /// delivery rate as a step area, boluses as bars on top of it. Each scales
    /// on its own, since units and units per hour share no axis, and neither to
    /// less than a floor, so a quiet stretch doesn't look like full tilt and a
    /// lone 1 U bolus doesn't stand as tall as an 8 U one would: rates to the
    /// window's highest but at least 1 U/h, boluses to the largest but 2 U.
    private func drawLane(_ inner: GraphicsContext, layout l: Layout) {
        guard let lane = l.lane else { return }
        var rule = Path()
        rule.move(to: CGPoint(x: lane.minX, y: lane.maxY))
        rule.addLine(to: CGPoint(x: lane.maxX, y: lane.maxY))
        inner.stroke(rule, with: .color(Color(nsColor: .separatorColor).opacity(0.6)), lineWidth: 0.5)
        // Headroom so the tallest bar and step stay clear of the hairline.
        let usable = lane.height - 4

        let topRate = max(l.steps.map(\.rate).max() ?? 0, 1)
        for run in ChartMath.contiguousRuns(l.steps) {
            var edge = Path()
            for (i, step) in run.enumerated() {
                let y = lane.minY + usable * CGFloat(step.rate / topRate)
                let from = CGPoint(x: l.x(step.start), y: y)
                if i == 0 { edge.move(to: from) } else { edge.addLine(to: from) }
                edge.addLine(to: CGPoint(x: l.x(step.end), y: y))
            }
            var area = edge
            area.addLine(to: CGPoint(x: l.x(run.last!.end), y: lane.minY))
            area.addLine(to: CGPoint(x: l.x(run.first!.start), y: lane.minY))
            area.closeSubpath()
            inner.fill(area, with: .color(Self.ink.opacity(0.12)))
            inner.stroke(edge, with: .color(Self.ink.opacity(0.4)), lineWidth: 1)
        }

        let largest = max(l.boluses.compactMap(\.bolusUnits).max() ?? 0, 2)
        for bolus in l.boluses {
            guard let units = bolus.bolusUnits else { continue }
            let height = max(3, usable * CGFloat(min(units / largest, 1)))
            let bar = CGRect(x: l.x(bolus.date) - 1.25, y: lane.minY, width: 2.5, height: height)
            inner.fill(Path(roundedRect: bar, cornerRadius: 1.25), with: .color(Self.ink.opacity(0.6)))
        }
    }

    /// The adaptive label color everything without a color setting is drawn in.
    private static let ink = Color(nsColor: .labelColor)

    /// Horizontal gridlines with value labels, at round intervals.
    private func drawGridlines(_ ctx: GraphicsContext, text ctx0: GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let step = ChartMath.niceStep(l.hi - l.lo)
        var level = (l.lo / step).rounded(.up) * step
        while level <= l.hi {
            let gy = l.y(level)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: gy))
            grid.addLine(to: CGPoint(x: plot.maxX, y: gy))
            ctx.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.35)), lineWidth: 0.5)

            let label = Text(String(format: "%g", level)).font(.system(size: 9)).foregroundStyle(.tertiary)
            let ly = min(max(gy + 2, plot.minY + 1), plot.maxY - 11)
            ctx0.draw(label, at: CGPoint(x: plot.minX + 5, y: l.screenY(ly)), anchor: .bottomLeading)
            level += step
        }
    }

    /// The optimal-range band, with dashed bounds.
    private func drawTargetBand(_ ctx: GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let yLow = l.y(l.units.display(settings.targetLow))
        let yHigh = l.y(l.units.display(settings.targetHigh))
        let bandBottom = max(min(yLow, yHigh), plot.minY), bandTop = min(max(yLow, yHigh), plot.maxY)
        guard bandTop > bandBottom else { return }

        ctx.fill(Path(CGRect(x: plot.minX, y: bandBottom, width: plot.width, height: bandTop - bandBottom)),
                 with: .color(settings.bandColor))
        let boundColor = settings.bandColor.opacity(0.35)
        for gy in [bandBottom, bandTop] {
            var bound = Path()
            bound.move(to: CGPoint(x: plot.minX, y: gy))
            bound.addLine(to: CGPoint(x: plot.maxX, y: gy))
            ctx.stroke(bound, with: .color(boundColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    /// The reading line (split across dropouts, smoothed, optionally shaded)
    /// plus the dot marking the latest reading. The dot goes into the unclipped
    /// `chart`, so its halo may bleed past the rounded corners.
    private func drawLine(_ inner: GraphicsContext, chart: inout GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let zones = zones()
        // Zone bands, bottom to top in chart space.
        let exLowY = l.bandY(mgdl: settings.extremeLow)
        let lowY = l.bandY(mgdl: settings.targetLow)
        let highY = l.bandY(mgdl: settings.targetHigh)
        let exHighY = l.bandY(mgdl: settings.extremeHigh)
        let bands: [(CGFloat, CGFloat, Color)] = [
            (plot.minY, exLowY, zones.extremeLowColor),
            (exLowY, lowY, zones.belowColor),
            (lowY, highY, zones.inRangeColor),
            (highY, exHighY, zones.aboveColor),
            (exHighY, plot.maxY, zones.extremeHighColor),
        ]

        for segment in ChartMath.segments(of: l.visible, gapThreshold: ChartMath.dropoutThreshold) {
            let pts = segment.map { CGPoint(x: l.x($0.date), y: l.y(of: $0)) }
            guard pts.count >= 2 else {
                if let p = pts.first, let r = segment.first {
                    dot(inner, at: p, radius: 2, color: ChartMath.color(for: r.sgv, zones: zones))
                }
                continue
            }
            let path = ChartMath.smooth(pts)
            if settings.lineShadingEnabled { fillUnder(inner, path: path, points: pts, plot: plot, zones: zones) }

            if settings.blendLineColors {
                strokeBlended(inner, path: path, bands: bands, plot: plot)
            } else {
                for (minY, maxY, color) in bands where maxY - minY > 0.5 {
                    var bandCtx = inner
                    bandCtx.clip(to: Path(CGRect(x: plot.minX, y: minY, width: plot.width, height: maxY - minY)))
                    bandCtx.stroke(path, with: .color(color.opacity(0.9)), style: Self.lineStroke)
                }
            }
        }

        // Latest reading: halo plus solid dot, either sized to 0 to hide it.
        if let last = l.visible.last {
            let p = CGPoint(x: l.x(last.date), y: l.y(of: last))
            let color = dotColor(for: last, zones: zones)
            if settings.dotHaloRadius > 0 {
                dot(chart, at: p, radius: settings.dotHaloRadius, color: color.opacity(0.18))
            }
            if settings.dotRadius > 0 {
                dot(chart, at: p, radius: settings.dotRadius, color: color)
            }
        }
    }

    /// The fading area between the line and the bottom of the plot.
    private func fillUnder(_ ctx: GraphicsContext, path: Path, points pts: [CGPoint],
                           plot: CGRect, zones: ChartMath.Zones) {
        let shade = settings.lineShadingUsesLineColor
            ? zones.inRangeColor.opacity(0.14)
            : settings.lineShadingColor
        var area = path
        area.addLine(to: CGPoint(x: pts.last!.x, y: plot.minY))
        area.addLine(to: CGPoint(x: pts.first!.x, y: plot.minY))
        area.closeSubpath()
        var areaCtx = ctx
        areaCtx.clip(to: area)
        areaCtx.fill(Path(plot), with: .linearGradient(
            Gradient(colors: [shade, shade.opacity(0)]),
            startPoint: CGPoint(x: plot.midX, y: plot.maxY), endPoint: CGPoint(x: plot.midX, y: plot.minY)))
    }

    private func drawTimeAxis(_ ctx0: GraphicsContext, layout l: Layout) {
        let baseline = l.screenY(l.plot.minY) - 2
        for (date, x, anchor) in [(l.start, l.plot.minX, UnitPoint.bottomLeading),
                                  (l.visible.last!.date, l.plot.maxX, .bottomTrailing)] {
            let text = Text(Self.timeLabel(date, span: l.span)).font(.system(size: 9)).foregroundStyle(.tertiary)
            ctx0.draw(text, at: CGPoint(x: x, y: baseline), anchor: anchor)
        }
    }

    private func zones() -> ChartMath.Zones {
        ChartMath.Zones(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            extremeLowColor: settings.extremeLowColor, belowColor: settings.belowColor,
            inRangeColor: settings.inRangeColor, aboveColor: settings.aboveColor,
            extremeHighColor: settings.extremeHighColor
        )
    }

    private static let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

    /// Strokes `path` with a vertical gradient blending the zone colors into
    /// one another, so the line shifts smoothly across thresholds.
    private func strokeBlended(_ ctx: GraphicsContext, path: Path, bands: [(CGFloat, CGFloat, Color)], plot: CGRect) {
        var stops: [Gradient.Stop] = []
        for (minY, maxY, color) in bands where maxY - minY > 0.5 {
            let center = ((minY + maxY) / 2 - plot.minY) / plot.height
            stops.append(.init(color: color.opacity(0.9), location: min(max(center, 0), 1)))
        }
        guard !stops.isEmpty else { return }
        ctx.stroke(path, with: .linearGradient(
            Gradient(stops: stops.sorted { $0.location < $1.location }),
            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)),
            style: Self.lineStroke)
    }

    /// Crosshair plus a pill at the hovered reading, listing a bolus, the rate
    /// in effect and an announcement under it when those layers are on and
    /// one is close by. Over a gap in the readings (where a lost-signal alert
    /// tends to be) the crosshair goes to the event itself instead.
    private func drawHover(_ ctx0: GraphicsContext, chart: inout GraphicsContext, layout l: Layout) {
        guard let hover else { return }
        let plot = l.plot
        let reading = hover.reading.flatMap { l.visible.indices.contains($0) ? l.visible[$0] : nil }
        let bolus = hover.bolus.flatMap { id in l.boluses.first { $0.id == id } }
        let note = hover.note.flatMap { id in l.notes.first { $0.id == id } }
        guard let anchor = reading?.date ?? bolus?.date ?? note?.date else { return }
        let px = l.x(anchor)

        var vline = Path()
        vline.move(to: CGPoint(x: px, y: l.lane?.minY ?? plot.minY))
        vline.addLine(to: CGPoint(x: px, y: plot.maxY))
        chart.stroke(vline, with: .color(Self.ink.opacity(0.25)), lineWidth: 1)

        if let r = reading {
            // Keeps a radius floor, so the crosshair still has a visible point
            // when the latest-reading dot is sized away.
            dot(chart, at: CGPoint(x: px, y: l.y(of: r)),
                radius: max(3, settings.dotRadius), color: dotColor(for: r, zones: zones()))
        }

        let time = Self.timeLabel(anchor, span: l.span)
        var text = Text(reading.map { "\($0.text(in: l.units)) · \(time)" } ?? time)
            .foregroundStyle(Self.ink)
        let insulin = [bolus?.bolusUnits.map { "Bolus " + PumpFormat.bolus($0) },
                       ChartMath.rate(at: anchor, in: l.steps).map(PumpFormat.rate)].compactMap { $0 }
        if !insulin.isEmpty {
            text = Text("\(text)\n\(Text(insulin.joined(separator: " · ")).foregroundStyle(.secondary))")
        }
        if let message = note?.noteText {
            text = Text("\(text)\n\(Text(Self.clipped(message)).foregroundStyle(.secondary))")
        }
        // Resolve once so measurement and drawing share the same layout. The
        // width cap makes a long announcement wrap instead of running off.
        let resolved = ctx0.resolve(text.font(.system(size: 10)))
        let pad: CGFloat = 5
        let size = resolved.measure(in: CGSize(width: plot.width - pad * 2 - 8, height: plot.height))
        var bx = px - (size.width + pad * 2) / 2
        bx = max(plot.minX, min(bx, plot.maxX - size.width - pad * 2))
        let box = CGRect(x: bx, y: plot.maxY - size.height - pad * 2 - 2,
                         width: size.width + pad * 2, height: size.height + pad)
        let bg = Path(roundedRect: box, cornerRadius: 5)
        chart.fill(bg, with: .color(Color(nsColor: .controlBackgroundColor).opacity(0.95)))
        chart.stroke(bg, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)
        let textTop = l.screenY(box.minY + pad / 2 + size.height)
        ctx0.draw(resolved, in: CGRect(x: box.minX + pad, y: textTop,
                                       width: size.width.rounded(.up) + 1, height: size.height))
    }

    /// Announcements can run to a paragraph; the pill shows the gist.
    static func clipped(_ message: String, limit: Int = 160) -> String {
        message.count <= limit ? message : String(message.prefix(limit - 1)) + "…"
    }

    private func dotColor(for r: Reading, zones: ChartMath.Zones) -> Color {
        settings.dotUsesZoneColor ? ChartMath.color(for: r.sgv, zones: zones) : settings.dotColor
    }

    private func dot(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    // MARK: - Hover tracking

    private func updateHover(at location: CGPoint, size: CGSize) {
        guard let l = layout(size: size) else { return }
        // Events are narrow marks, so they want the pointer much closer than
        // a reading does.
        func nearest(_ events: [Treatment]) -> String? {
            ChartMath.nearestIndex(to: location.x, x: l.x, dates: events.map(\.date), maxDistance: 6)
                .map { events[$0].id }
        }
        let target = Hover(reading: ChartMath.nearestIndex(to: location.x, x: l.x, in: l.visible, maxDistance: 24),
                           bolus: nearest(l.boluses), note: nearest(l.notes))
        hover = target == Hover() ? nil : target
    }
}
