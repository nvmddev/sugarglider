import AppKit
import SwiftUI
import Testing
@testable import Sugarglider

private func elements(of path: Path) -> [Path.Element] {
    var result: [Path.Element] = []
    path.forEach { result.append($0) }
    return result
}

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

    @Test func labelsNeedDayOnceAWindowCanRepeatAClockTime() {
        #expect(ChartMath.labelsNeedDay(span: 6 * 3600) == false)
        #expect(ChartMath.labelsNeedDay(span: 23.5 * 3600) == false)
        #expect(ChartMath.labelsNeedDay(span: 24 * 3600))
        #expect(ChartMath.labelsNeedDay(span: 72 * 3600))
    }

    @Test func dropoutThresholdIsSharedWithTheStore() {
        #expect(ChartMath.dropoutThreshold == 15 * 60)
        #expect(ReadingStore.contiguityThreshold == ChartMath.dropoutThreshold)
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

    @Test func smoothElementCounts() {
        let p = { (x: CGFloat) in CGPoint(x: x, y: x) }
        #expect(elements(of: ChartMath.smooth([])).isEmpty)
        #expect(elements(of: ChartMath.smooth([p(0)])).count == 1)
        #expect(elements(of: ChartMath.smooth([p(0), p(1)])).count == 2)
        #expect(elements(of: ChartMath.smooth([p(0), p(1), p(2)])).count == 3)   // move + 2 curves
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

    @Test func nearestIndexFindsClosestByX() {
        let base = Date.now
        let offsets: [TimeInterval] = [0, 300, 600]
        let readings = offsets.map { Reading(sgv: 100, direction: "Flat", date: base.addingTimeInterval($0)) }
        func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(base)) }
        #expect(ChartMath.nearestIndex(to: 0, x: x, in: readings, maxDistance: 24) == 0)
        #expect(ChartMath.nearestIndex(to: 310, x: x, in: readings, maxDistance: 24) == 1)
        #expect(ChartMath.nearestIndex(to: 590, x: x, in: readings, maxDistance: 24) == 2)
        #expect(ChartMath.nearestIndex(to: 1000, x: x, in: readings, maxDistance: 24) == nil)
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
        #expect(renderedImage(ChartCanvas(readings: [], rangeHours: 6, settings: Self.makeSettings())) != nil)
    }

    @Test func rendersSinglePointAsNoData() {
        let chart = ChartCanvas(readings: [reading(100, minutesAgo: 0)], rangeHours: 6, settings: Self.makeSettings())
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersFullChartMmolDirectColors() {
        let s = Self.makeSettings()
        s.units = .mmol
        let chart = ChartCanvas(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersFullChartMgdlBlendedWithBackground() {
        let s = Self.makeSettings()
        s.units = .mgdl
        s.blendLineColors = true
        s.chartBackgroundEnabled = true
        s.chartBackgroundColor = Color(red: 0.1, green: 0.1, blue: 0.12, opacity: 1)
        let chart = ChartCanvas(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersWithShadingOffAndDotHidden() {
        let s = Self.makeSettings()
        s.lineShadingEnabled = false
        s.dotRadius = 0
        s.dotHaloRadius = 0
        let chart = ChartCanvas(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s)
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
        let chart = ChartCanvas(readings: readingsCrossingEveryZone(until: .now), rangeHours: 6, settings: s)
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

        let emptyState = pixels(of: ChartCanvas(readings: [], rangeHours: 3, settings: s))
        let pinned = pixels(of: ChartCanvas(readings: samples, rangeHours: 3, settings: s, windowEnd: end))
        let wallClock = pixels(of: ChartCanvas(readings: samples, rangeHours: 3, settings: s))

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

        let chart = pixels(of: ChartCanvas(readings: samples, rangeHours: 72, settings: s, windowEnd: end))
        #expect(chart != nil)
        #expect(chart != pixels(of: ChartCanvas(readings: [], rangeHours: 72, settings: s)))
    }

    /// Single-reading segments take the isolated-dot branch.
    @Test func rendersWithGapsAndIsolatedPoints() {
        let base = Date.now
        let readings = [300, 100, 95, 90, 0].map { reading(120, minutesAgo: $0, from: base) }
        let chart = ChartCanvas(readings: readings, rangeHours: 6, settings: Self.makeSettings())
        #expect(renderedImage(chart) != nil)
    }

    /// A color that never reaches the chart is a picker doing nothing, as `sliderColor` once did.
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
            pixels(of: ChartCanvas(readings: samples, rangeHours: 3, settings: s, windowEnd: end,
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
