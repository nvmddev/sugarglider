import SwiftUI

/// Chart math with no SwiftUI view state, so it's directly unit-testable.
enum ChartMath {
    /// How far apart two readings may be and still count as one continuous run.
    /// The chart breaks its line on a wider gap rather than interpolating across
    /// it, and `ReadingStore` merges polled entries into the history only within
    /// it, so the two can't drift apart.
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

    /// Compared in mg/dL, the unit the thresholds are stored in, independent of
    /// what the user is shown.
    static func color(for sgv: Int, zones: Zones) -> Color {
        let v = Double(sgv)
        if v < zones.extremeLow { return zones.extremeLowColor }
        if v < zones.targetLow { return zones.belowColor }
        if v > zones.extremeHigh { return zones.extremeHighColor }
        if v > zones.targetHigh { return zones.aboveColor }
        return zones.inRangeColor
    }

    /// Splits readings into contiguous runs, breaking where a gap exceeds `gap`.
    static func segments(of readings: [Reading], gapThreshold gap: TimeInterval) -> [[Reading]] {
        var result: [[Reading]] = []
        var current: [Reading] = []
        for r in readings {
            if let prev = current.last, r.date.timeIntervalSince(prev.date) > gap {
                result.append(current); current = []
            }
            current.append(r)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Catmull-Rom smoothing into a flowing bezier through the points.
    static func smooth(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// The reading nearest `targetX` by horizontal distance, or nil if none is
    /// within `maxDistance`. The hover hit-test, factored out of the view.
    static func nearestIndex(to targetX: CGFloat, x: (Date) -> CGFloat, in readings: [Reading], maxDistance: CGFloat) -> Int? {
        var best = 0, bestDist = CGFloat.greatestFiniteMagnitude
        for (i, r) in readings.enumerated() {
            let d = abs(x(r.date) - targetX)
            if d < bestDist { bestDist = d; best = i }
        }
        return bestDist < maxDistance ? best : nil
    }

    /// Synthetic readings for the Settings color preview: a curve sweeping all
    /// five zones relative to the given thresholds, so every configurable color
    /// is visible wherever the user has set their ranges. Never real data.
    ///
    /// `cycles` repeats the shape, which begins and ends in range with zero
    /// slope so the repeats join smoothly. The preview scales it with its window
    /// instead of stretching one sweep across it, because a stretched curve
    /// looks identical at every width and only the axis labels move, which makes
    /// the range slider look broken.
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
        // Cosine-eased between keyframes; the chart's Catmull-Rom smoothing
        // then rounds off the sampled points.
        func value(at t: Double) -> Double {
            guard let i = keyframes.lastIndex(where: { $0.t <= t }), i < keyframes.count - 1 else {
                return keyframes.last!.v
            }
            let (t0, v0) = keyframes[i], (t1, v1) = keyframes[i + 1]
            let eased = (1 - cos((t - t0) / (t1 - t0) * .pi)) / 2
            return v0 + (v1 - v0) * eased
        }
        let interval: TimeInterval = 5 * 60
        let cycles = max(cycles, 1)
        return (0..<count).map { i in
            // Position within the current repeat. The last point of a whole
            // cycle lands on 0, which holds the same value as 1 (in range).
            let progress = Double(i) / Double(count - 1) * cycles
            return Reading(sgv: Int(value(at: progress.truncatingRemainder(dividingBy: 1)).rounded()),
                    direction: "",
                    date: end.addingTimeInterval(-Double(count - 1 - i) * interval))
        }
    }

    /// Whether time labels need the weekday as well as the clock time. A window
    /// of a day or more can put the same clock time at both ends of the axis,
    /// which reads as a chart spanning nothing at all.
    static func labelsNeedDay(span: TimeInterval) -> Bool { span >= 24 * 3600 }

    /// A round gridline step (1/2/5 × 10ⁿ) giving roughly five lines across the
    /// span, for mmol/L and mg/dL ranges alike.
    static func niceStep(_ span: Double) -> Double {
        let rough = max(span / 4, 0.0001)
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let nice: Double = norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 7 ? 5 : 10))
        return nice * mag
    }
}
