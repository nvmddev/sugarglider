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
            return Reading(sgv: Int(value(at: progress).rounded()), direction: "",
                           date: end.addingTimeInterval(-Double(count - 1 - i) * interval))
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
}
