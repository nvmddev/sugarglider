// Draws the README pictures with the app's own views, so they cannot drift
// from what ships.
//
//   scripts/make-readme-art.sh
//
// The glucose data is invented. It is a plausible six hours (a dip, a meal
// spike above range, a soft low afterwards) built from fixed control points,
// so nobody's real readings end up in the repository and a re-render of an
// unchanged view produces the same curve.

import AppKit
import SwiftUI

/// The README shows the pictures at a third of their pixel size, so they stay
/// sharp on a Retina display.
let scale = 3.0
let outputDirectory = URL(fileURLWithPath: "docs", isDirectory: true)

// MARK: - Invented readings

/// Hours before "now" paired with a glucose value in mg/dL. Chosen to cross
/// four of the five zones with the stock thresholds (54 / 70 / 180 / 250), so
/// the zone coloring is actually visible in the picture.
let curve: [(hoursAgo: Double, mgdl: Double)] = [
    (6.00, 124), (5.50, 117), (5.00, 106), (4.50,  97), (4.00,  92),
    (3.50, 116), (3.00, 167), (2.60, 196), (2.20, 185), (1.80, 157),
    (1.40, 131), (1.00, 104), (0.70,  82), (0.50,  68), (0.35,  74),
    (0.15,  96), (0.00, 112),
]

/// A fixed-seed generator: the wobble has to look like sensor noise without
/// making every re-render a new picture.
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
        let eased = t * t * (3 - 2 * t)          // smoothstep, so joins aren't kinked
        return a.mgdl + (b.mgdl - a.mgdl) * eased
    }
    return curve.last!.mgdl
}

/// Nightscout's own wording for the trend, derived from the slope in mg/dL per
/// minute the way the uploaders do it.
func direction(slopePerMinute s: Double) -> String {
    switch s {
    case ..<(-3):  return "DoubleDown"
    case ..<(-2):  return "SingleDown"
    case ..<(-1):  return "FortyFiveDown"
    case ..<1:     return "Flat"
    case ..<2:     return "FortyFiveUp"
    case ..<3:     return "SingleUp"
    default:       return "DoubleUp"
    }
}

/// Six hours at the usual five-minute cadence, oldest first. The newest reading
/// is two minutes old rather than zero, so the dropdown says "2 min ago"
/// instead of "just now".
@MainActor
func fixtureReadings(now: Date) -> [Reading] {
    let spacing = 5.0 / 60                        // hours
    let newestAge = 2.0 / 60
    var wobble = Wobble()
    var values: [(Double, Double)] = []           // (hoursAgo, mgdl)
    var h = 6.0
    while h >= newestAge - 1e-9 {
        values.append((h, interpolate(hoursAgo: h) + wobble.next() * 1.6))
        h -= spacing
    }
    return values.enumerated().map { index, point in
        let previous = index > 0 ? values[index - 1].1 : point.1
        return Reading(sgv: Int(point.1.rounded()),
                       direction: direction(slopePerMinute: (point.1 - previous) / 5),
                       date: now.addingTimeInterval(-point.0 * 3600))
    }
}

@MainActor
func makeStore(_ settings: AppSettings, readings: [Reading]) -> ReadingStore {
    let store = ReadingStore(settings: settings)   // init is inert: no timer, no network
    store.readings = readings
    store.lastReading = readings.last
    store.previousReading = readings.dropLast().last
    return store
}

/// The pictures need no access token, and reaching the real Keychain from a
/// throwaway binary would only earn an access prompt.
@MainActor
struct NoTokenStore: TokenStorage {
    func load() -> String { "" }
    func save(_ token: String) -> Bool { true }
}

/// Isolated defaults, so the pictures show the stock look rather than whatever
/// the person re-rendering them happens to have configured.
@MainActor
func makeSettings(_ configure: (AppSettings) -> Void = { _ in }) -> AppSettings {
    let suite = UserDefaults(suiteName: "dev.nevermind.sugarglider.readme-art")!
    suite.removePersistentDomain(forName: "dev.nevermind.sugarglider.readme-art")
    let settings = AppSettings(defaults: suite, tokens: NoTokenStore())
    settings.baseURL = "https://cgm.example.invalid"   // configured, unreachable
    configure(settings)
    return settings
}

// MARK: - Appearance

enum Appearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    /// Standing in for the panel's material, which renders as clear.
    var panelBackground: Color { self == .dark ? Color(white: 0.16) : Color(white: 0.97) }
}

// MARK: - The pictures

/// Three states of the status-bar item, side by side.
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

/// The dropdown, on a stand-in for the panel it normally lives in.
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
                    .strokeBorder(Color.primary.opacity(appearance == .dark ? 0.18 : 0.10),
                                  lineWidth: 0.5)
            }
            .padding(10)
    }
}

// MARK: - Rendering

@MainActor
func write(_ view: some View, appearance: Appearance, to name: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance.colorScheme))
    renderer.scale = scale
    renderer.isOpaque = false

    var image: CGImage?
    appearance.nsAppearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
    guard let image else { fatalError("could not render \(name)") }

    let url = outputDirectory.appendingPathComponent("\(name)-\(appearance.rawValue).png")
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
    print("  \(url.path) (\(image.width)×\(image.height))")
}

@MainActor
func main() {
    // Otherwise the chart's time axis comes out in the region of whoever
    // re-renders the pictures.
    UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    UserDefaults.standard.set("en_US", forKey: "AppleLocale")

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    // Anchored to the actual clock, because the views date their text against
    // it: "2 min ago" and the chart's time axis both come out wrong if the
    // fixture is pinned to a rounded slot. The cost is that a re-render moves
    // the axis labels, which is why this script is run on purpose rather than
    // from a build.
    let now = Date()
    let readings = fixtureReadings(now: now)

    for appearance in Appearance.allCases {
        write(MenuBarStrip(now: now), appearance: appearance, to: "menubar")

        let settings = makeSettings()
        write(DropdownShot(appearance: appearance, settings: settings,
                           store: makeStore(settings, readings: readings)),
              appearance: appearance, to: "dropdown")
    }
}

main()
