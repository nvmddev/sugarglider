import SwiftUI

enum ChartMath {
    /// Also where `ReadingStore` stops merging polled entries into the history, so the chart's
    /// line breaks and the cache's seams can't drift apart.
    static let dropoutThreshold: TimeInterval = 15 * 60

    struct Zones {
        var extremeLow: Double
        var targetLow: Double
        var targetHigh: Double
        var extremeHigh: Double
        var extremeLowColor: Color
        var belowColor: Color
        var inRangeColor: Color
        var aboveColor: Color
        var extremeHighColor: Color
    }

    /// `sgv` and the thresholds are both mg/dL, whatever unit is displayed.
    static func color(for sgv: Int, zones: Zones) -> Color {
        let value = Double(sgv)
        if value < zones.extremeLow { return zones.extremeLowColor }
        if value < zones.targetLow { return zones.belowColor }
        if value > zones.extremeHigh { return zones.extremeHighColor }
        if value > zones.targetHigh { return zones.aboveColor }
        return zones.inRangeColor
    }

    static func segments(of readings: [Reading], gapThreshold gap: TimeInterval) -> [[Reading]] {
        var runs: [[Reading]] = []
        for reading in readings {
            if let previous = runs.last?.last, reading.date.timeIntervalSince(previous.date) <= gap {
                runs[runs.count - 1].append(reading)
            } else {
                runs.append([reading])
            }
        }
        return runs
    }

    /// Where a segment runs beyond the sensor's range. Each reading takes the time halfway to its
    /// neighbors, so a lone LOW gets a stretch of its own.
    static func outOfRangeSpans(_ segment: [Reading]) -> [ClosedRange<Date>] {
        var spans: [ClosedRange<Date>] = []
        for (i, reading) in segment.enumerated() where reading.outOfRange != nil {
            func halfway(to j: Int) -> Date {
                guard segment.indices.contains(j) else { return reading.date }
                return reading.date.addingTimeInterval(segment[j].date.timeIntervalSince(reading.date) / 2)
            }
            let span = halfway(to: i - 1)...halfway(to: i + 1)
            if let last = spans.last, last.upperBound >= span.lowerBound {
                spans[spans.count - 1] = last.lowerBound...span.upperBound
            } else {
                spans.append(span)
            }
        }
        return spans
    }

    /// A Catmull-Rom spline through the points.
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count >= 3 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    static func nearestIndex(to targetX: CGFloat, x: (Date) -> CGFloat, in readings: [Reading],
                             maxDistance: CGFloat) -> Int? {
        nearestIndex(to: targetX, x: x, dates: readings.map(\.date), maxDistance: maxDistance)
    }

    static func nearestIndex(to targetX: CGFloat, x: (Date) -> CGFloat, dates: [Date],
                             maxDistance: CGFloat) -> Int? {
        var best = 0, bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, date) in dates.enumerated() {
            let distance = abs(x(date) - targetX)
            if distance < bestDistance { bestDistance = distance; best = i }
        }
        return bestDistance < maxDistance ? best : nil
    }

    struct DeliveryStep: Equatable {
        var start: Date
        var end: Date
        var rate: Double
    }

    /// Each temp basal runs until its duration is up or the next one starts, clipped to
    /// `from...to`. Uncovered time stays a gap: the profile basal that would fill it isn't read.
    static func deliverySteps(_ treatments: [Treatment], from: Date, to: Date) -> [DeliveryStep] {
        let temps: [(date: Date, rate: Double, minutes: Double)] = treatments.compactMap {
            guard case .tempBasal(let rate, let minutes) = $0.kind else { return nil }
            return ($0.date, rate, minutes)
        }.sorted { $0.date < $1.date }

        var steps: [DeliveryStep] = []
        for (i, temp) in temps.enumerated() {
            var end = temp.date.addingTimeInterval(temp.minutes * 60)
            if i + 1 < temps.count { end = min(end, temps[i + 1].date) }
            let start = max(temp.date, from)
            end = min(end, to)
            if end > start { steps.append(DeliveryStep(start: start, end: end, rate: temp.rate)) }
        }
        return steps
    }

    static func contiguousRuns(_ steps: [DeliveryStep]) -> [[DeliveryStep]] {
        var runs: [[DeliveryStep]] = []
        for step in steps {
            if let last = runs.last?.last, step.start.timeIntervalSince(last.end) < 1 {
                runs[runs.count - 1].append(step)
            } else {
                runs.append([step])
            }
        }
        return runs
    }

    static func rate(at date: Date, in steps: [DeliveryStep]) -> Double? {
        steps.last { $0.start <= date && date < $0.end }?.rate
    }

    /// A curve sweeping all five zones, for the Settings preview. `cycles` repeats the sweep
    /// rather than stretching it, which would look the same at every window width.
    static func sampleReadings(extremeLow: Double, targetLow: Double,
                               targetHigh: Double, extremeHigh: Double,
                               endingAt end: Date, count: Int = 35,
                               cycles: Double = 1) -> [Reading] {
        let mid = (targetLow + targetHigh) / 2
        let below = (extremeLow + targetLow) / 2
        let veryLow = max(40, extremeLow - (targetLow - extremeLow) / 2)
        let above = (targetHigh + extremeHigh) / 2
        let veryHigh = min(400, extremeHigh + (extremeHigh - targetHigh) / 2)
        let keyframes: [(t: Double, v: Double)] = [
            (0.00, mid), (0.12, below), (0.25, veryLow), (0.45, mid),
            (0.60, above), (0.75, veryHigh), (1.00, mid),
        ]
        func value(at t: Double) -> Double {
            guard let i = keyframes.lastIndex(where: { $0.t <= t }), i + 1 < keyframes.count else { return mid }
            let (t0, v0) = keyframes[i], (t1, v1) = keyframes[i + 1]
            let eased = (1 - cos((t - t0) / (t1 - t0) * .pi)) / 2
            return v0 + (v1 - v0) * eased
        }
        let interval: TimeInterval = 5 * 60
        let cycles = max(cycles, 1)
        return (0..<count).map { i in
            // A whole cycle's last point wraps to 0, which is fine: the sweep starts and ends at `mid`.
            let progress = (Double(i) / Double(count - 1) * cycles).truncatingRemainder(dividingBy: 1)
            return Reading(sgv: Int(value(at: progress).rounded()), direction: nil,
                           date: end.addingTimeInterval(-Double(count - 1 - i) * interval))
        }
    }

    /// Pump data for the Settings preview, on the sweeps `sampleReadings` draws over the same
    /// `span` and `cycles`: the rate drops into each low and climbs with each rise, an alert marks
    /// the low, a meal bolus comes just before the rise and a correction near its peak.
    static func sampleTreatments(endingAt end: Date, span: TimeInterval, cycles: Double = 1) -> [Treatment] {
        let cycles = max(cycles, 1)
        let sweep = span / cycles
        // The next temp basal ends each one, so lasting a whole sweep is always long enough.
        func basal(_ rate: Double) -> Treatment.Kind { .tempBasal(rate: rate, minutes: sweep / 60) }
        let events: [(t: Double, kind: Treatment.Kind)] = [
            (0.00, basal(0.8)), (0.08, basal(0.45)), (0.17, basal(0.15)), (0.25, .note("Low glucose")),
            (0.33, basal(0.5)), (0.43, .bolus(units: 5.5)), (0.45, basal(1.0)), (0.55, basal(1.8)),
            (0.68, basal(2.4)), (0.72, .bolus(units: 1.5)), (0.80, basal(1.4)), (0.90, basal(0.9)),
        ]
        let start = end.addingTimeInterval(-span)
        return (0..<Int(cycles.rounded(.up))).flatMap { cycle in
            events.enumerated().compactMap { index, event -> Treatment? in
                let date = start.addingTimeInterval((Double(cycle) + event.t) * sweep)
                return date <= end ? Treatment(id: "sample-\(cycle)-\(index)", date: date, kind: event.kind) : nil
            }
        }
    }

    /// From a day on, both ends of the axis can show the same clock time.
    static func labelsNeedDay(span: TimeInterval) -> Bool { span >= 24 * 3600 }

    /// A round step (1, 2 or 5 × 10ⁿ) giving about five gridlines, in either unit.
    static func niceStep(_ span: Double) -> Double {
        let rough = max(span / 4, 0.0001)
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let nice: Double = normalized < 1.5 ? 1 : (normalized < 3 ? 2 : (normalized < 7 ? 5 : 10))
        return nice * magnitude
    }

    /// The glucose axis, in display units.
    struct ValueAxis: Equatable {
        var lo: Double
        var hi: Double
        var step: Double
    }

    /// Always reaches every threshold, so a quiet day keeps the scale of a wild one rather than
    /// being stretched to fill the chart. Each end lies half a step past a gridline, so the
    /// outermost lines don't vanish into the frame. Only the readings get a margin of their own,
    /// for the line's stroke.
    static func valueAxis(values: [Double], thresholds: [Double], mgdl: Bool) -> ValueAxis {
        let pad = mgdl ? 10.0 : 0.5, minSpan = mgdl ? 40.0 : 2.0
        let clampLow = mgdl ? 40.0 : 2.0, clampHigh = mgdl ? 500.0 : 28.0
        let ends = values.flatMap { [$0 - pad, $0 + pad] } + thresholds
        let low = max(clampLow, ends.min() ?? clampLow)
        let high = max(min(clampHigh, ends.max() ?? clampHigh), low + minSpan)
        let step = niceStep(high - low)
        let lo = max(clampLow, (low / step).rounded(.down) * step - step / 2)
        let hi = min(clampHigh, (high / step).rounded(.up) * step + step / 2)
        return ValueAxis(lo: lo, hi: max(hi, lo + minSpan), step: step)
    }
}
