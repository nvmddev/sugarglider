import AppKit
import SwiftUI
import Testing
@testable import Sugarglider

private func defaultZones() -> ChartMath.Zones {
    .init(extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250,
          extremeLowColor: .red, belowColor: .orange, inRangeColor: .green,
          aboveColor: .blue, extremeHighColor: .purple)
}

extension SugargliderTests {
    @Test func niceStepPicksRoundIntervals() {
        #expect(abs(ChartMath.niceStep(4) - 1) < 1e-9)
        #expect(abs(ChartMath.niceStep(8) - 2) < 1e-9)
        #expect(abs(ChartMath.niceStep(20) - 5) < 1e-9)
        #expect(abs(ChartMath.niceStep(40) - 10) < 1e-9)
        #expect(abs(ChartMath.niceStep(100) - 20) < 1e-9)
        #expect(abs(ChartMath.niceStep(2) - 0.5) < 1e-9)
    }

    @Test func valueAxisKeepsTheThresholdsInViewOnAQuietDay() {
        let axis = ChartMath.valueAxis(values: [5.6, 7.4, 6.1], thresholds: [3.0, 3.9, 10.0, 13.9], mgdl: false)
        // Gridlines 2…14, half a step past the top one; the bottom stops at the 2 mmol/L clamp.
        #expect(axis == .init(lower: 2, upper: 15, step: 2))
    }

    @Test func valueAxisWidensForReadingsBeyondTheThresholds() {
        let axis = ChartMath.valueAxis(values: [80, 320], thresholds: [54, 70, 180, 250], mgdl: true)
        #expect(axis == .init(lower: 40, upper: 375, step: 50))
    }

    @Test func valueAxisStaysWithinTheClampsAndAMinimumSpan() {
        let clamped = ChartMath.valueAxis(values: [39, 600], thresholds: [70, 180], mgdl: true)
        #expect(clamped == .init(lower: 40, upper: 500, step: 100))

        let flat = ChartMath.valueAxis(values: [6, 6], thresholds: [6, 6], mgdl: false)
        #expect(flat.upper - flat.lower >= 2)
    }

    @Test func labelsNeedDayOnceAWindowCanRepeatAClockTime() {
        #expect(ChartMath.labelsNeedDay(span: 6 * 3600) == false)
        #expect(ChartMath.labelsNeedDay(span: 23.5 * 3600) == false)
        #expect(ChartMath.labelsNeedDay(span: 24 * 3600))
        #expect(ChartMath.labelsNeedDay(span: 72 * 3600))
    }

    @Test func segmentsSplitOnDropouts() {
        let base = Date.now
        func oldestFirst(minutesAgo: [Double]) -> [Reading] {
            minutesAgo.sorted(by: >).map { reading(100, minutesAgo: $0, from: base) }
        }
        #expect(ChartMath.segments(of: [], gapThreshold: 900).isEmpty)
        #expect(ChartMath.segments(of: oldestFirst(minutesAgo: [0]), gapThreshold: 900).map(\.count) == [1])
        #expect(ChartMath.segments(of: oldestFirst(minutesAgo: [10, 5, 0]), gapThreshold: 900).map(\.count) == [3])
        // A 30-minute gap between 40 and 10.
        let split = ChartMath.segments(of: oldestFirst(minutesAgo: [45, 40, 10, 5, 0]), gapThreshold: 900)
        #expect(split.map(\.count) == [2, 3])
    }

    @Test func runsBeyondTheSensorRangeReachTheirMeasuredNeighbors() {
        func runs(_ values: [Int]) -> [(Bool, [Int])] {
            ChartMath.runs(of: values.map { reading($0) }).map { ($0.beyondRange, $0.readings.map(\.sgv)) }
        }
        #expect(runs([100, 60, 40, 60]).elementsEqual([(false, [100, 60, 40, 60])], by: ==))
        #expect(runs([60, 39, 39, 60]).elementsEqual([(false, [60]), (true, [60, 39, 39, 60]), (false, [60])], by: ==))
        #expect(runs([401, 300, 401]).elementsEqual([(true, [401, 300]), (false, [300]), (true, [300, 401])], by: ==))
    }

    @Test func zoneStopsHaveHardEdgesAtTheThresholds() {
        let zones = defaultZones()
        let axis = ChartMath.ValueAxis(lower: 40, upper: 340, step: 50)
        let stops = ChartMath.zoneStops(for: zones, axis: axis, units: .mgdl, blended: false)
        // Thresholds 54, 70, 180 and 250 lie 14, 30, 140 and 210 into the 300 mg/dL axis.
        let edges: [Double] = [0, 14, 14, 30, 30, 140, 140, 210, 210, 300]
        #expect(zip(stops.map(\.location), edges).allSatisfy { abs($0 - $1 / 300) < 1e-9 })
        #expect(stops.count == edges.count)
        let blended = ChartMath.zoneStops(for: zones, axis: axis, units: .mgdl, blended: true)
        #expect(blended.count == 5)
        #expect(AppSettings.colorsMatch(blended[2].color, zones.inRangeColor))
    }

    /// With Low above High the in-range zone has no height, which leaves it out rather than inverting it.
    @Test func zoneStopsSkipZonesWithoutHeight() {
        var zones = defaultZones()
        zones.targetLow = 200
        let stops = ChartMath.zoneStops(for: zones, axis: ChartMath.ValueAxis(lower: 40, upper: 340, step: 50),
                                        units: .mgdl, blended: true)
        #expect(!stops.contains { AppSettings.colorsMatch($0.color, zones.inRangeColor) })
    }

    @Test func gridlineLevelsAreMultiplesOfTheStep() {
        #expect(ChartMath.ValueAxis(lower: 1.5, upper: 14.5, step: 2).levels == [2, 4, 6, 8, 10, 12, 14])
        #expect(ChartMath.ValueAxis(lower: 40, upper: 340, step: 50).levels == [50, 100, 150, 200, 250, 300])
    }

    @Test func colorForZone() {
        let zones = defaultZones()
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 50, zones: zones), zones.extremeLowColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 60, zones: zones), zones.belowColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 100, zones: zones), zones.inRangeColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 200, zones: zones), zones.aboveColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 300, zones: zones), zones.extremeHighColor))
        // A threshold itself belongs to the zone nearer the target range.
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 54, zones: zones), zones.belowColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 70, zones: zones), zones.inRangeColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 180, zones: zones), zones.inRangeColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 250, zones: zones), zones.aboveColor))
    }

    @Test func sampleReadingsSweepAllZones() throws {
        let end = Date.now
        let readings = ChartMath.sampleReadings(
            extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250, endingAt: end)

        #expect(readings.count == 35)
        #expect(readings.last?.date == end)
        #expect(zip(readings, readings.dropFirst()).allSatisfy { $0.date < $1.date })
        // 5-minute spacing fits the whole curve into a 3-hour window.
        #expect(try #require(readings.first).date >= end.addingTimeInterval(-3 * 3600))

        let values = readings.map { Double($0.sgv) }
        #expect(values.contains { $0 < 54 })
        #expect(values.contains { (54..<70).contains($0) })
        #expect(values.contains { (70...180).contains($0) })
        #expect(values.contains { (180...250).contains($0) })
        #expect(values.contains { $0 > 250 })
        #expect(values.allSatisfy { (40...400).contains($0) })
    }

    @Test func sampleTreatmentsFollowTheSampleSweeps() throws {
        let end = Date.now, span: TimeInterval = 6 * 3600
        let start = end.addingTimeInterval(-span)
        let treatments = ChartMath.sampleTreatments(endingAt: end, span: span, cycles: 2)

        #expect(treatments.allSatisfy { (start...end).contains($0.date) })
        #expect(zip(treatments, treatments.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(Set(treatments.map(\.id)).count == treatments.count)
        #expect(treatments.filter { $0.bolusUnits != nil }.count == 4)

        // The rate covers the whole window in one run.
        let steps = ChartMath.deliverySteps(treatments, from: start, to: end)
        #expect(ChartMath.contiguousRuns(steps).count == 1)
        #expect(steps.first?.start == start)
        #expect(steps.last?.end == end)

        // Each alert sits on a low of the sample curve.
        let readings = ChartMath.sampleReadings(extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250,
                                                endingAt: end, count: 6 * 12 + 1, cycles: 2)
        let alerts = treatments.filter { $0.noteText != nil }
        #expect(alerts.count == 2)
        for alert in alerts {
            let nearest = try #require(readings.min {
                abs($0.date.timeIntervalSince(alert.date)) < abs($1.date.timeIntervalSince(alert.date))
            })
            #expect(nearest.sgv < 54)
        }
    }

    /// Half a sweep keeps its alert and meal bolus but not the correction, which falls past the end.
    @Test func sampleTreatmentsStopAtTheWindowEnd() {
        let end = Date.now
        let treatments = ChartMath.sampleTreatments(endingAt: end, span: 6 * 3600, cycles: 1.5)
        #expect(treatments.allSatisfy { $0.date <= end })
        #expect(treatments.compactMap(\.bolusUnits) == [5.5, 1.5, 5.5])
        #expect(treatments.filter { $0.noteText != nil }.count == 2)
    }

    @Test func nearestIndexFindsTheClosestDateWithinReach() {
        let base = Date.now
        let dates = [0.0, 300, 600].map { base.addingTimeInterval($0) }
        #expect(ChartMath.nearestIndex(to: base, in: dates, maxDistance: 24) == 0)
        #expect(ChartMath.nearestIndex(to: base.addingTimeInterval(310), in: dates, maxDistance: 24) == 1)
        #expect(ChartMath.nearestIndex(to: base.addingTimeInterval(590), in: dates, maxDistance: 24) == 2)
        #expect(ChartMath.nearestIndex(to: base.addingTimeInterval(1000), in: dates, maxDistance: 24) == nil)
        #expect(ChartMath.nearestIndex(to: base, in: [], maxDistance: 24) == nil)
    }
}

extension SugargliderTests {
    private func renderedImage(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 280, height: 160))
        renderer.scale = 1
        return renderer.cgImage
    }

    /// Raw bitmap rather than PNG data, whose encoding isn't reproducible.
    private func pixels(of view: some View) -> Data? {
        guard let image = renderedImage(view) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let bytes = rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private func readingsCrossingEveryZone(until end: Date) -> [Reading] {
        let points: [(minutesAgo: Double, sgv: Int)] = [(300, 45), (240, 60), (180, 100), (120, 200),
                                                        (60, 300), (30, 150), (10, 90), (0, 110)]
        return points.map { reading($0.sgv, minutesAgo: $0.minutesAgo, from: end) }
    }

    @Test func rendersEmptyStateWithoutCrash() {
        #expect(renderedImage(GlucoseChart(readings: [], rangeHours: 6, settings: Self.makeSettings(), windowEnd: .now)) != nil)
    }

    @Test func rendersSinglePointAsNoData() {
        let chart = GlucoseChart(readings: [reading(100, minutesAgo: 0)], rangeHours: 6, settings: Self.makeSettings(), windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersFullChartMmolDirectColors() {
        let s = Self.makeSettings()
        s.units = .mmol
        let chart = GlucoseChart(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s, windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersFullChartMgdlBlendedWithBackground() {
        let s = Self.makeSettings()
        s.units = .mgdl
        s.blendLineColors = true
        s.chartBackgroundEnabled = true
        s.chartBackgroundColor = Color(red: 0.1, green: 0.1, blue: 0.12, opacity: 1)
        let chart = GlucoseChart(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s, windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersWithShadingOffAndDotHidden() {
        let s = Self.makeSettings()
        s.lineShadingEnabled = false
        s.dotRadius = 0
        s.dotHaloRadius = 0
        let chart = GlucoseChart(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s, windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersWithCustomShadingAndDotColors() {
        let s = Self.makeSettings()
        s.lineShadingUsesLineColor = false
        s.lineShadingColor = Color(red: 0.9, green: 0.2, blue: 0.4, opacity: 0.3)
        s.dotUsesZoneColor = false
        s.dotColor = Color(red: 0.1, green: 0.9, blue: 0.5, opacity: 1)
        s.dotRadius = 12
        s.dotHaloRadius = 24
        let chart = GlucoseChart(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s, windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    /// The Settings preview's contract: samples pinned to their own window end keep drawing
    /// however old they are, where a wall-clock window lets them age out into the empty state.
    @Test func pinnedWindowEndKeepsStaleSampleDataVisible() {
        let s = Self.makeSettings()
        let end = Date.now.addingTimeInterval(-6 * 3600)
        let samples = ChartMath.sampleReadings(
            extremeLow: s.extremeLow, targetLow: s.targetLow,
            targetHigh: s.targetHigh, extremeHigh: s.extremeHigh, endingAt: end)

        let emptyState = pixels(of: GlucoseChart(readings: [], rangeHours: 3, settings: s, windowEnd: .now))
        let pinned = pixels(of: GlucoseChart(readings: samples, rangeHours: 3, settings: s, windowEnd: end))
        let wallClock = pixels(of: GlucoseChart(readings: samples, rangeHours: 3, settings: s, windowEnd: .now))

        #expect(emptyState != nil)
        #expect(pinned != emptyState)
        #expect(wallClock == emptyState)
    }

    @Test func rendersWidestPreviewWindow() throws {
        let s = Self.makeSettings()
        let end = Date.now
        let samples = ChartMath.sampleReadings(
            extremeLow: s.extremeLow, targetLow: s.targetLow,
            targetHigh: s.targetHigh, extremeHigh: s.extremeHigh,
            endingAt: end, count: 72 * 12 + 1)
        #expect(samples.count == 865)
        #expect(try #require(samples.first).date == end.addingTimeInterval(-72 * 3600))

        let chart = pixels(of: GlucoseChart(readings: samples, rangeHours: 72, settings: s, windowEnd: end))
        #expect(chart != nil)
        #expect(chart != pixels(of: GlucoseChart(readings: [], rangeHours: 72, settings: s, windowEnd: .now)))
    }

    /// Both units, since LOW's 39 lies under the mg/dL axis' floor of 40, with and without blending.
    @Test(arguments: [(AppSettings.Units.mgdl, false), (.mmol, true)])
    func rendersLowAndHighStretchesDotted(units: AppSettings.Units, blended: Bool) {
        let s = Self.makeSettings()
        s.units = units
        s.blendLineColors = blended
        let end = Date.now
        let values = [120, 80, 50, 39, 39, 39, 60, 140, 250, 350, 401, 401, 380, 300, 39]
        let readings = values.enumerated().map { i, sgv in
            reading(sgv, minutesAgo: Double(values.count - 1 - i) * 5, from: end)
        }
        let chart = pixels(of: GlucoseChart(readings: readings, rangeHours: 2, settings: s, windowEnd: end))
        #expect(chart != nil)
        #expect(chart != pixels(of: GlucoseChart(readings: [], rangeHours: 2, settings: s, windowEnd: .now)))
    }

    /// Single-reading segments take the isolated-dot branch.
    @Test func rendersWithGapsAndIsolatedPoints() {
        let base = Date.now
        let readings = [300, 100, 95, 90, 0].map { reading(120, minutesAgo: $0, from: base) }
        let chart = GlucoseChart(readings: readings, rangeHours: 6, settings: Self.makeSettings(), windowEnd: .now)
        #expect(renderedImage(chart) != nil)
    }

    /// A color that never reaches the chart is a picker doing nothing.
    @Test func pumpLayersDrawInTheirOwnColors() throws {
        let s = Self.makeSettings()
        s.chartShowsDeliveryRate = true
        s.chartShowsAnnouncements = true
        let end = Date.now
        let samples = ChartMath.sampleReadings(
            extremeLow: s.extremeLow, targetLow: s.targetLow,
            targetHigh: s.targetHigh, extremeHigh: s.extremeHigh, endingAt: end)
        let treatments = ChartMath.sampleTreatments(endingAt: end, span: 3 * 3600)
        func chart() -> Data? {
            pixels(of: GlucoseChart(readings: samples, rangeHours: 3, settings: s, windowEnd: end,
                                   treatments: treatments))
        }

        let stock = try #require(chart())
        let colors: [ReferenceWritableKeyPath<AppSettings, Color>] = [\.bolusColor, \.deliveryRateColor,
                                                                       \.announcementColor]
        for keyPath in colors {
            let original = s[keyPath: keyPath]
            s[keyPath: keyPath] = Color(red: 0.9, green: 0.1, blue: 0.2, opacity: 1)
            let recolored = try #require(chart())
            // Not just unequal: once a color made from `labelColor` has been archived, as every
            // assignment does, later renders drift by ±1 in a few pixels anyway.
            let largest = zip(recolored, stock).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(largest > 64, "\(keyPath) doesn't reach the chart")
            s[keyPath: keyPath] = original
        }
    }
}
