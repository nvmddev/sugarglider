// Draws the README pictures with the app's own views; run through
// scripts/make-readme-art.sh.
//
// The glucose data is invented: six plausible hours (a dip, a meal spike above
// range, a soft low) from fixed control points, so no real readings end up in
// the repository and an unchanged view renders the same curve.

import AppKit
import SwiftUI

// The README shows the pictures at a third of their pixel size.
let scale = 3.0
let outputDirectory = URL(filePath: "docs", directoryHint: .isDirectory)

// Crosses four of the five zones at the stock thresholds (54/70/180/250 mg/dL).
let curve: [(hoursAgo: Double, mgdl: Double)] = [
    (6.00, 124), (5.50, 117), (5.00, 106), (4.50,  97), (4.00,  92),
    (3.50, 116), (3.00, 167), (2.60, 196), (2.20, 185), (1.80, 157),
    (1.40, 131), (1.00, 104), (0.70,  82), (0.50,  68), (0.35,  74),
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
func direction(slopePerMinute s: Double) -> String {
    switch s {
    case ..<(-3): "DoubleDown"
    case ..<(-2): "SingleDown"
    case ..<(-1): "FortyFiveDown"
    case ..<1: "Flat"
    case ..<2: "FortyFiveUp"
    case ..<3: "SingleUp"
    default: "DoubleUp"
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

func makeStore(_ settings: AppSettings, readings: [Reading]) -> ReadingStore {
    let store = ReadingStore(settings: settings)   // inert until start(): no timer, no network
    store.readings = readings
    store.lastReading = readings.last
    store.previousReading = readings.dropLast().last
    return store
}

// The real Keychain would prompt the throwaway binary for access.
struct NoTokenStore: TokenStorage {
    func load() -> String { "" }
    func save(_ token: String) -> Bool { true }
}

// Fresh defaults: the pictures show the stock look, not the settings of whoever renders them.
func makeSettings(_ configure: (AppSettings) -> Void = { _ in }) -> AppSettings {
    let suiteName = "dev.nevermind.sugarglider.readme-art"
    guard let suite = UserDefaults(suiteName: suiteName) else { fatalError("no defaults suite \(suiteName)") }
    suite.removePersistentDomain(forName: suiteName)
    let settings = AppSettings(defaults: suite, tokens: NoTokenStore())
    settings.baseURL = "https://cgm.example.invalid"   // configured, unreachable
    configure(settings)
    return settings
}

enum Appearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    // Stands in for the panel's material, which renders as clear off-screen.
    var panelBackground: Color { self == .dark ? Color(white: 0.16) : Color(white: 0.97) }
}

struct MenuBarStrip: View {
    let now: Date

    var body: some View {
        HStack(spacing: 28) {
            label(sgv: 101, direction: "FortyFiveUp", minutesAgo: 2)
            label(sgv: 101, direction: "FortyFiveUp", minutesAgo: 2, showDelta: true, previous: 99)
            label(sgv: 223, direction: "SingleUp", minutesAgo: 23)
        }
        .padding(.horizontal, 4)
    }

    private func label(sgv: Int, direction: String, minutesAgo: Double,
                       showDelta: Bool = false, previous: Int? = nil) -> some View {
        let settings = makeSettings { if showDelta { $0.deltaDisplay = .menuAndStatusBar } }
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
            .overlay(alignment: .bottom) {
                ActionRowStandIn(appearance: appearance).padding(MenuBarContentView.insets)
            }
            .background(appearance.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(appearance == .dark ? 0.18 : 0.10),
                                  lineWidth: 0.5)
            }
            .padding(10)
    }
}

// Glass doesn't render off-screen, which leaves the dropdown's row of glass
// buttons blank. Mirrors that row in MenuBarContentView, for the pictures only.
struct ActionRowStandIn: View {
    let appearance: Appearance

    // Glass still takes part in layout, so the real button can be measured.
    private static let diameter = NSHostingView(rootView: GlassButton()).fittingSize.height

    private struct GlassButton: View {
        var body: some View {
            Button {} label: { Image(systemName: "power").frame(width: 18, height: 18) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            button("arrow.clockwise")
            button("gearshape")
            Spacer()
            button("power")
        }
    }

    private func button(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(width: Self.diameter, height: Self.diameter)
            .background {
                Circle()
                    .fill(appearance == .dark ? Color(white: 0.26) : .white)
                    .shadow(color: .black.opacity(appearance == .dark ? 0.4 : 0.14), radius: 1.5, y: 0.5)
            }
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
    // Otherwise the chart's time axis follows the region of whoever renders.
    UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    UserDefaults.standard.set("en_US", forKey: "AppleLocale")

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    // The real clock, because the views date their text against it ("2 min ago",
    // the time axis). The axis labels move on every render as a consequence.
    let now = Date.now
    let readings = fixtureReadings(now: now)

    for appearance in Appearance.allCases {
        try write(MenuBarStrip(now: now), appearance: appearance, to: "menubar")

        let settings = makeSettings()
        try write(DropdownShot(appearance: appearance, settings: settings,
                               store: makeStore(settings, readings: readings)),
                  appearance: appearance, to: "dropdown")
    }
}

try main()
