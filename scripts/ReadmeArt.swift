// Draws the README pictures with the app's own views; run through
// scripts/make-readme-art.sh.
//
// The data is invented: six plausible hours (a dip, a meal spike above range, a
// soft low) from fixed control points, with pump data that fits them, so no real
// readings end up in the repository and an unchanged view renders the same curve.

import AppKit
import SwiftUI

// The README shows the pictures at a third of their pixel size.
let scale = 3.0
let outputDirectory = URL(filePath: "docs", directoryHint: .isDirectory)

// Crosses three of the five zones at the stock thresholds (54/70/180/250 mg/dL):
// the low is deep enough to show its color.
let curve: [(hoursAgo: Double, mgdl: Double)] = [
    (6.00, 124), (5.50, 117), (5.00, 106), (4.50,  97), (4.00,  92),
    (3.50, 116), (3.00, 167), (2.60, 196), (2.20, 185), (1.80, 157),
    (1.40, 131), (1.00, 104), (0.70,  80), (0.50,  64), (0.35,  66),
    (0.15,  96), (0.00, 112),
]

// Seeded, so the noise looks like a sensor's but every render is the same.
struct Wobble {
    private var state: UInt64 = 0x5EED_5EED

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 40) / Double(1 << 24) * 2 - 1   // -1...1
    }
}

func interpolate(hoursAgo h: Double) -> Double {
    if h >= curve[0].hoursAgo { return curve[0].mgdl }
    for (a, b) in zip(curve, curve.dropFirst()) where h <= a.hoursAgo && h >= b.hoursAgo {
        let t = (a.hoursAgo - h) / (a.hoursAgo - b.hoursAgo)
        let eased = t * t * (3 - 2 * t)   // smoothstep, so joins aren't kinked
        return a.mgdl + (b.mgdl - a.mgdl) * eased
    }
    return curve[curve.count - 1].mgdl
}

// The slope thresholds the uploaders use for Nightscout's trend names.
func direction(slopePerMinute s: Double) -> Reading.Direction {
    switch s {
    case ..<(-3): .doubleDown
    case ..<(-2): .singleDown
    case ..<(-1): .fortyFiveDown
    case ..<1: .flat
    case ..<2: .fortyFiveUp
    case ..<3: .singleUp
    default: .doubleUp
    }
}

// Six hours at a five-minute cadence, oldest first, ending five minutes ago so
// the dropdown doesn't say "just now".
func fixtureReadings(now: Date) -> [Reading] {
    let spacingHours = 5.0 / 60
    var wobble = Wobble()
    var points: [(hoursAgo: Double, mgdl: Double)] = []
    var hoursAgo = 6.0
    while hoursAgo > spacingHours / 2 {
        points.append((hoursAgo, interpolate(hoursAgo: hoursAgo) + wobble.next() * 1.6))
        hoursAgo -= spacingHours
    }
    return points.enumerated().map { index, point in
        let previous = index > 0 ? points[index - 1].mgdl : point.mgdl
        return Reading(sgv: Int(point.mgdl.rounded()),
                       direction: direction(slopePerMinute: (point.mgdl - previous) / 5),
                       date: now.addingTimeInterval(-point.hoursAgo * 3600))
    }
}

// A meal bolus before the spike and a correction near its top. The rate climbs
// with the rise and stops in the low; each one runs until the next. An alert
// marks the top of the spike and one the low.
func fixtureTreatments(now: Date) -> [Treatment] {
    func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
    let rates: [(hoursAgo: Double, rate: Double)] = [
        (6.5, 0.8), (4.3, 0.6), (3.4, 1.3), (2.8, 1.9), (2.1, 1.2),
        (1.4, 0.8), (0.9, 0.3), (0.6, 0.0), (0.25, 0.7),
    ]
    let steps = rates.enumerated().map { index, step in
        Treatment(id: "rate-\(index)", date: hoursAgo(step.hoursAgo), kind: .tempBasal(rate: step.rate, minutes: 180))
    }
    let boluses = [Treatment(id: "meal", date: hoursAgo(3.45), kind: .bolus(units: 5.5)),
                   Treatment(id: "correction", date: hoursAgo(2.5), kind: .bolus(units: 1.5))]
    let alerts = [Treatment(id: "high", date: hoursAgo(2.6), kind: .note("High glucose")),
                  Treatment(id: "low", date: hoursAgo(0.45), kind: .note("Low glucose"))]
    return (steps + boluses + alerts).sorted { $0.date < $1.date }
}

// Every pump value the dropdown can show. The settings decide which of them it does.
func makeStore(_ settings: AppSettings, readings: [Reading], now: Date) -> ReadingStore {
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86400) }
    let store = ReadingStore(settings: settings)   // inert until start(): no timer, no network
    store.readings = readings
    store.lastReading = readings.last
    store.previousReading = readings.dropLast().last
    store.treatments = fixtureTreatments(now: now)
    store.pumpStatus = PumpStatus(date: now.addingTimeInterval(-4 * 60), insulinOnBoard: 1.35,
                                  reservoir: 142, batteryPercent: 75, mode: .auto, deliveryRate: 0.7,
                                  insulinToday: 24.6, insulinYesterday: 41.3,
                                  averageToday: 128, averageYesterday: 139)
    store.changed = [.reservoir: daysAgo(2.2), .cannula: daysAgo(2.2),
                     .battery: daysAgo(6.1), .sensor: daysAgo(4.4)]
    return store
}

// The real Keychain would prompt the throwaway binary for access.
struct NoTokenStore: TokenStorage {
    func load() -> String { "" }
    func save(_ token: String) -> Bool { true }
}

// Fresh defaults: the pictures show the stock look, not the settings of whoever renders them.
// A suite named by a path keeps its plist out of ~/Library/Preferences, where no API removes it.
// This one lands next to the binary, in the work directory make-readme-art.sh deletes.
func makeSettings(_ configure: (AppSettings) -> Void = { _ in }) -> AppSettings {
    let path = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appending(path: UUID().uuidString).path(percentEncoded: false)
    guard let suite = UserDefaults(suiteName: path) else { fatalError("no defaults suite at \(path)") }
    let settings = AppSettings(defaults: suite, tokens: NoTokenStore())
    settings.baseURL = "https://cgm.example.invalid"   // configured, unreachable
    configure(settings)
    return settings
}

// The stock palette is monochrome. This one shows what your own colors look like,
// in the zone colors of the standard time in range report (AGP).
func useZoneColors(_ settings: AppSettings) {
    settings.extremeLowColor = Color(red: 0.64, green: 0.09, blue: 0.11)
    settings.belowColor = Color(red: 0.91, green: 0.24, blue: 0.22)
    settings.inRangeColor = Color(red: 0.20, green: 0.66, blue: 0.35)
    settings.aboveColor = Color(red: 0.96, green: 0.69, blue: 0.05)
    settings.extremeHighColor = Color(red: 0.95, green: 0.46, blue: 0.11)
    settings.bandColor = settings.inRangeColor.opacity(0.12)
    settings.sliderColor = settings.inRangeColor
    settings.bolusColor = Color(red: 0.22, green: 0.49, blue: 0.95)
    settings.deliveryRateColor = Color(red: 0.22, green: 0.49, blue: 0.95).opacity(0.6)
}

enum Appearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    // Stand in for the materials of the panel and the popover, which render as clear off-screen.
    var panelBackground: Color { self == .dark ? Color(white: 0.16) : Color(white: 0.97) }
    var popoverBackground: Color { self == .dark ? Color(white: 0.23) : Color(white: 0.995) }
    var border: Color { Color.primary.opacity(self == .dark ? 0.18 : 0.10) }
}

struct MenuBarStrip: View {
    let now: Date

    var body: some View {
        HStack(spacing: 28) {
            label(sgv: 101, direction: .fortyFiveUp, minutesAgo: 2)
            label(sgv: 101, direction: .fortyFiveUp, minutesAgo: 2, showDelta: true, previous: 99)
            label(sgv: 223, direction: .singleUp, minutesAgo: 23)
        }
        .padding(.horizontal, 4)
    }

    private func label(sgv: Int, direction: Reading.Direction, minutesAgo: Double,
                       showDelta: Bool = false, previous: Int? = nil) -> some View {
        let settings = makeSettings { if showDelta { $0.deltaDisplay = .dropdownAndStatusBar } }
        let store = ReadingStore(settings: settings)
        store.lastReading = Reading(sgv: sgv, direction: direction,
                                    date: now.addingTimeInterval(-minutesAgo * 60))
        if let previous {
            store.previousReading = Reading(sgv: previous, direction: direction,
                                            date: now.addingTimeInterval(-(minutesAgo + 5) * 60))
        }
        return MenuBarLabel(settings: settings, store: store)
    }
}

struct DropdownShot: View {
    let appearance: Appearance
    let settings: AppSettings
    let store: ReadingStore

    var body: some View {
        MenuBarContentView(settings: settings, store: store)
            .background(appearance.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(appearance.border, lineWidth: 0.5)
            }
            .padding(10)
    }
}

// A rounded box with the arrow on top, centered.
nonisolated struct PopoverShape: Shape {
    static let arrowHeight = 10.0
    static let arrowWidth = 22.0
    static let cornerRadius = 13.0

    func path(in rect: CGRect) -> Path {
        let box = CGRect(x: rect.minX, y: rect.minY + Self.arrowHeight,
                         width: rect.width, height: rect.height - Self.arrowHeight)
        var path = Path(roundedRect: box, cornerRadius: Self.cornerRadius, style: .continuous)
        path.move(to: CGPoint(x: rect.midX - Self.arrowWidth / 2, y: box.minY + 0.5))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.midX - 3, y: box.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + Self.arrowWidth / 2, y: box.minY + 0.5),
                          control: CGPoint(x: rect.midX + 3, y: box.minY))
        path.closeSubpath()
        return path
    }
}

// The dropdown with the time in range popover open. A popover is a window of its
// own, so ImageRenderer can't draw the real one: this places the app's popover
// content below the ring, where the real one opens (measured).
struct ZonesShot: View {
    // The ring's horizontal center and bottom edge in DropdownShot, measured on its render.
    // Check them after changing the dropdown's layout.
    nonisolated static let ringCenterX = 287.5
    nonisolated static let ringBottom = 273.0

    let appearance: Appearance
    let settings: AppSettings
    let store: ReadingStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            DropdownShot(appearance: appearance, settings: settings, store: store)
            if let summary = TimeInRangeView.summary(readings: store.readings, windowEnd: store.now,
                                                     settings: settings) {
                ZoneShares(summary: summary)
                    .padding(.top, PopoverShape.arrowHeight)
                    .background {
                        PopoverShape()
                            .fill(appearance.popoverBackground)
                            .shadow(color: .black.opacity(appearance == .dark ? 0.5 : 0.18), radius: 8, y: 3)
                    }
                    .overlay { PopoverShape().stroke(appearance.border, lineWidth: 0.5) }
                    .fixedSize()
                    .alignmentGuide(.leading) { $0.width / 2 - Self.ringCenterX }
                    .alignmentGuide(.top) { _ in -Self.ringBottom }
            }
        }
        .padding([.trailing, .bottom], 14)   // room for the popover's shadow
    }
}

func write(_ view: some View, appearance: Appearance, to name: String) throws {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance.colorScheme))
    renderer.scale = scale
    renderer.isOpaque = false

    var image: CGImage?
    appearance.nsAppearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
    guard let image else { fatalError("could not render \(name)") }

    let url = outputDirectory.appending(path: "\(name)-\(appearance.rawValue).png")
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
    print("  \(url.path) (\(image.width)×\(image.height))")
}

func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    // The real clock, because the views date their text against it ("2 min ago",
    // the time axis). The axis labels move on every render as a consequence.
    let now = Date.now
    let readings = fixtureReadings(now: now)

    for appearance in Appearance.allCases {
        try write(MenuBarStrip(now: now), appearance: appearance, to: "menubar")

        // Every pump item on, also those off by default, so one picture shows them all.
        let settings = makeSettings {
            $0.chartShowsDeliveryRate = true
            $0.chartShowsAnnouncements = true
            $0.showChangeAge = true
            $0.showCannulaAge = true
            $0.showSensorAge = true
            $0.showDailyInsulin = true
            $0.showAverageGlucose = true
        }
        try write(DropdownShot(appearance: appearance, settings: settings,
                               store: makeStore(settings, readings: readings, now: now)),
                  appearance: appearance, to: "dropdown")

        let colored = makeSettings {
            $0.chartShowsDeliveryRate = true
            useZoneColors($0)
        }
        try write(ZonesShot(appearance: appearance, settings: colored,
                            store: makeStore(colored, readings: readings, now: now)),
                  appearance: appearance, to: "dropdown-colors")
    }
}

try main()
