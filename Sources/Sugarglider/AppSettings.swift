import SwiftUI

/// Persisted settings. Every setting is a plain stored property whose `didSet`
/// writes it through to `defaults`: Observation only tracks stored properties,
/// so a computed property reading `UserDefaults` would never trigger a redraw.
/// Both dependencies are injectable so tests stay off the shared defaults
/// domain and the real Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let tokens: any TokenStorage

    // Installed by `ReadingStore.start()`. Nothing observes these, so they stay
    // out of change tracking, and none of them fire during the initial load.
    @ObservationIgnored var onConnectionChanged: (() -> Void)?
    @ObservationIgnored var onPollIntervalChanged: (() -> Void)?
    @ObservationIgnored var onRangeHoursChanged: (() -> Void)?

    var baseURL: String = "" {
        didSet {
            defaults.set(baseURL, forKey: "baseURL")
            if oldValue != baseURL { onConnectionChanged?() }
        }
    }

    /// Empty if the site allows unauthenticated reads. The one setting that
    /// doesn't go into `defaults`: a preferences plist is readable by any
    /// process running as the user, so this lives in the Keychain.
    var token: String = "" {
        didSet {
            guard oldValue != token else { return }
            tokenStorageFailed = !tokens.save(token)
            onConnectionChanged?()
        }
    }

    /// The Keychain refused the last write, so the token works this session but
    /// is gone after a relaunch. Settings shows it, because nothing else would;
    /// falling back to the plist would undo the reason the token moved.
    var tokenStorageFailed = false

    /// Display units. Nightscout stores mg/dL internally; mmol/L divides by 18.
    enum Units: String {
        case mmol, mgdl

        var label: String { self == .mmol ? "mmol/L" : "mg/dL" }

        func display(_ mgdl: Double) -> Double { self == .mmol ? mgdl / 18.0 : mgdl }
        func value(fromMgdl sgv: Int) -> Double { display(Double(sgv)) }
        func text(fromMgdl sgv: Int) -> String {
            self == .mmol ? String(format: "%.1f", Double(sgv) / 18.0) : String(sgv)
        }

        func toMgdl(_ value: Double) -> Double { self == .mmol ? value * 18.0 : value }
    }

    var units: Units = .mmol { didSet { defaults.set(units.rawValue, forKey: "units") } }

    // MARK: - Number formatting

    /// Numbers are written with a dot and no grouping whatever the system
    /// region says, so an entry field can't show "5,6" next to a reading
    /// rendered as "5.6". `String(format:)` is locale-independent already;
    /// a `FormatStyle` is not unless it's pinned like this. The price is that
    /// the entry fields won't parse "5,6" either.
    static let numberLocale = Locale(identifier: "en_US_POSIX")

    static let wholeNumberFormat = IntegerFormatStyle<Int>(locale: numberLocale).grouping(.never)

    /// One decimal in mmol/L, none in mg/dL, matching `Units.text(fromMgdl:)`.
    var thresholdFormat: FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>(locale: Self.numberLocale)
            .precision(.fractionLength(0...(units == .mmol ? 1 : 0)))
            .grouping(.never)
    }

    /// Thresholds are stored in mg/dL, Nightscout's native unit, and converted
    /// only for display and for the entry fields.
    var targetLow: Double = 70 { didSet { defaults.set(targetLow, forKey: "targetLow") } }
    var targetHigh: Double = 180 { didSet { defaults.set(targetHigh, forKey: "targetHigh") } }

    var extremeLow: Double = 54 { didSet { defaults.set(extremeLow, forKey: "extremeLow") } }
    var extremeHigh: Double = 250 { didSet { defaults.set(extremeHigh, forKey: "extremeHigh") } }

    /// What's wrong with the order of the four thresholds, or nil if they're
    /// usable. The fields aren't clamped against each other on purpose: they
    /// persist as you type, so moving a neighbour would fight anyone swapping a
    /// range around. But `ChartMath.color(for:zones:)` tests them in order, so
    /// with Low above High the in-range color becomes unreachable and the target
    /// band silently disappears. Hence the warning.
    var thresholdOrderWarning: String? {
        if targetLow >= targetHigh { return "Low must be below High." }
        if extremeLow > targetLow { return "Very low can't be above Low." }
        if extremeHigh < targetHigh { return "Very high can't be below High." }
        return nil
    }

    // Chart colors, archived as `NSColor` so alpha survives. The defaults are
    // all the adaptive label color, i.e. a monochrome chart until the user
    // assigns zone colors.
    static let defaultBandColor = Color(nsColor: .labelColor).opacity(0.08)
    static let defaultInRangeColor = Color(nsColor: .labelColor)
    static let defaultBelowColor = Color(nsColor: .labelColor)
    static let defaultAboveColor = Color(nsColor: .labelColor)
    static let defaultExtremeLowColor = Color(nsColor: .labelColor)
    static let defaultExtremeHighColor = Color(nsColor: .labelColor)
    static let defaultLineShadingColor = Color(nsColor: .labelColor).opacity(0.14)
    static let defaultDotColor = Color(nsColor: .labelColor)
    /// Matches the stock slider's neutral grey, which is what the range slider
    /// looked like before it was hand-drawn.
    static let defaultSliderColor = Color(nsColor: .tertiaryLabelColor)
    // Opaque, so the color picker's opacity slider opens at 100% instead of
    // trapping a freshly picked color at zero alpha.
    static let defaultChartBackgroundColor = Color(nsColor: .controlBackgroundColor)

    var bandColor: Color = defaultBandColor { didSet { persistColor(bandColor, "bandColor") } }
    var inRangeColor: Color = defaultInRangeColor { didSet { persistColor(inRangeColor, "inRangeColor") } }
    var belowColor: Color = defaultBelowColor { didSet { persistColor(belowColor, "belowColor") } }
    var aboveColor: Color = defaultAboveColor { didSet { persistColor(aboveColor, "aboveColor") } }
    var extremeLowColor: Color = defaultExtremeLowColor { didSet { persistColor(extremeLowColor, "extremeLowColor") } }
    var extremeHighColor: Color = defaultExtremeHighColor { didSet { persistColor(extremeHighColor, "extremeHighColor") } }
    var lineShadingColor: Color = defaultLineShadingColor { didSet { persistColor(lineShadingColor, "lineShadingColor") } }
    var dotColor: Color = defaultDotColor { didSet { persistColor(dotColor, "dotColor") } }
    var sliderColor: Color = defaultSliderColor { didSet { persistColor(sliderColor, "sliderColor") } }
    var chartBackgroundColor: Color = defaultChartBackgroundColor { didSet { persistColor(chartBackgroundColor, "chartBackgroundColor") } }

    /// Off by default, so the menu's glass material shows through the chart.
    var chartBackgroundEnabled: Bool = false { didSet { defaults.set(chartBackgroundEnabled, forKey: "chartBackgroundEnabled") } }

    /// Blend the line's zone colors across thresholds instead of switching
    /// abruptly at each boundary.
    var blendLineColors: Bool = false { didSet { defaults.set(blendLineColors, forKey: "blendLineColors") } }

    var lineShadingEnabled: Bool = true { didSet { defaults.set(lineShadingEnabled, forKey: "lineShadingEnabled") } }

    /// Derive the shading from the in-range zone color rather than from
    /// `lineShadingColor`, so it follows the line's palette.
    var lineShadingUsesLineColor: Bool = true {
        didSet { defaults.set(lineShadingUsesLineColor, forKey: "lineShadingUsesLineColor") }
    }

    /// Color the latest-reading dot by its range zone rather than by `dotColor`.
    var dotUsesZoneColor: Bool = true { didSet { defaults.set(dotUsesZoneColor, forKey: "dotUsesZoneColor") } }

    // Radius of the latest-reading dot and of the halo behind it, in points.
    // Either at 0 hides that part. The Settings sliders are built from the same
    // limits the write-through clamps to, so the two can't disagree.
    static let defaultDotRadius: Double = 4
    static let defaultDotHaloRadius: Double = 7
    static let dotRadiusLimits: ClosedRange<Double> = 0...12
    static let dotHaloRadiusLimits: ClosedRange<Double> = 0...24

    var dotRadius: Double = defaultDotRadius {
        didSet { writeThrough(\.dotRadius, key: "dotRadius", limits: Self.dotRadiusLimits) }
    }
    var dotHaloRadius: Double = defaultDotHaloRadius {
        didSet { writeThrough(\.dotHaloRadius, key: "dotHaloRadius", limits: Self.dotHaloRadiusLimits) }
    }

    /// The Colors tab's non-color options in one value. Bundling them means the
    /// defaults, the reset and the presets share one definition of "the look"
    /// instead of three lists that can fall out of step. `Codable` so a preset
    /// can persist it without a per-field serializer.
    struct Appearance: Codable, Equatable {
        var blendLineColors: Bool
        var lineShadingEnabled: Bool
        var lineShadingUsesLineColor: Bool
        var dotUsesZoneColor: Bool
        var dotRadius: Double
        var dotHaloRadius: Double
    }

    static let defaultAppearance = Appearance(
        blendLineColors: false, lineShadingEnabled: true, lineShadingUsesLineColor: true,
        dotUsesZoneColor: true, dotRadius: defaultDotRadius, dotHaloRadius: defaultDotHaloRadius
    )

    /// A view over the stored flags above. Computed is fine here: the getter
    /// reads stored properties, so Observation still tracks it.
    var appearance: Appearance {
        get {
            Appearance(blendLineColors: blendLineColors,
                       lineShadingEnabled: lineShadingEnabled,
                       lineShadingUsesLineColor: lineShadingUsesLineColor,
                       dotUsesZoneColor: dotUsesZoneColor,
                       dotRadius: dotRadius, dotHaloRadius: dotHaloRadius)
        }
        set {
            blendLineColors = newValue.blendLineColors
            lineShadingEnabled = newValue.lineShadingEnabled
            lineShadingUsesLineColor = newValue.lineShadingUsesLineColor
            dotUsesZoneColor = newValue.dotUsesZoneColor
            dotRadius = newValue.dotRadius
            dotHaloRadius = newValue.dotHaloRadius
        }
    }

    /// Restores everything the Colors tab offers, and nothing outside it.
    func resetColors() {
        for slot in Self.colorSlots { self[keyPath: slot.keyPath] = slot.defaultValue }
        chartBackgroundEnabled = false
        appearance = Self.defaultAppearance
    }

    // MARK: - Color presets

    /// One configurable chart color: archive key, property, default. Everything
    /// that treats the colors as a set (the initial load, `resetColors()`, the
    /// preset round-trip) drives off `colorSlots`, so adding a color means a
    /// stored property plus one row here. They used to be separate lists, and a
    /// color missing from one made the preset picker report "Custom" forever.
    struct ColorSlot {
        let key: String
        let keyPath: ReferenceWritableKeyPath<AppSettings, Color>
        let defaultValue: Color
    }

    static let colorSlots: [ColorSlot] = [
        .init(key: "bandColor", keyPath: \.bandColor, defaultValue: defaultBandColor),
        .init(key: "inRangeColor", keyPath: \.inRangeColor, defaultValue: defaultInRangeColor),
        .init(key: "belowColor", keyPath: \.belowColor, defaultValue: defaultBelowColor),
        .init(key: "aboveColor", keyPath: \.aboveColor, defaultValue: defaultAboveColor),
        .init(key: "extremeLowColor", keyPath: \.extremeLowColor, defaultValue: defaultExtremeLowColor),
        .init(key: "extremeHighColor", keyPath: \.extremeHighColor, defaultValue: defaultExtremeHighColor),
        .init(key: "lineShadingColor", keyPath: \.lineShadingColor, defaultValue: defaultLineShadingColor),
        .init(key: "dotColor", keyPath: \.dotColor, defaultValue: defaultDotColor),
        .init(key: "sliderColor", keyPath: \.sliderColor, defaultValue: defaultSliderColor),
        .init(key: "chartBackgroundColor", keyPath: \.chartBackgroundColor,
              defaultValue: defaultChartBackgroundColor),
    ]

    static var colorKeys: [String] { colorSlots.map(\.key) }

    /// A named snapshot of the whole Colors tab, so several looks can be kept
    /// and switched between.
    struct ColorPreset {
        var name: String
        var colors: [String: Color]   // keyed by `colorKeys`
        var backgroundEnabled: Bool
        /// Nil means "colors only": presets saved before appearances existed
        /// decode this way, and must leave the current line/dot settings alone
        /// rather than silently resetting them.
        var appearance: Appearance? = nil
    }

    var colorPresets: [ColorPreset] = [] { didSet { persistPresets(colorPresets) } }

    /// Adds `preset`, replacing any existing one with the same name.
    func saveColorPreset(_ preset: ColorPreset) {
        if let i = colorPresets.firstIndex(where: { $0.name == preset.name }) {
            colorPresets[i] = preset
        } else {
            colorPresets.append(preset)
        }
    }

    func deleteColorPreset(named name: String) {
        colorPresets.removeAll { $0.name == name }
    }

    /// Read by the slider, the clamp below and `ReadingStore`'s history sizing
    /// alike, since a wider window needs a longer fetch to fill it.
    static let rangeHoursLimits: ClosedRange<Int> = 2...72

    /// Chart window in hours. The slider steps by 2; any whole hour can be typed.
    var rangeHours: Int = 6 {
        didSet {
            guard writeThrough(\.rangeHours, key: "rangeHours", limits: Self.rangeHoursLimits) else { return }
            if oldValue != rangeHours { onRangeHoursChanged?() }
        }
    }

    /// Appearance override. `.system` follows the OS setting.
    enum Theme: String {
        case system, light, dark

        /// For the dropdown, applied per-window via `View.windowTheme(_:)`.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }

        /// For the Settings window, whose appearance SwiftUI manages itself, so
        /// it only takes the override through `preferredColorScheme`.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    var theme: Theme = .system { didSet { defaults.set(theme.rawValue, forKey: "theme") } }

    /// Where to show the change since the previous reading.
    enum DeltaDisplay: Int { case off = 0, menu = 1, menuAndStatusBar = 2 }
    var deltaDisplay: DeltaDisplay = .menu { didSet { defaults.set(deltaDisplay.rawValue, forKey: "deltaDisplay") } }

    /// How long a reading may go without a successor before it counts as stale.
    /// A setting rather than a constant because delivery cadence varies by CGM
    /// and uploader, so no single delay means "one missed reading" for everyone.
    static let defaultStaleAfterMinutes = 11
    static let staleAfterLimits: ClosedRange<Int> = 5...240

    var staleAfterMinutes: Int = defaultStaleAfterMinutes {
        didSet { writeThrough(\.staleAfterMinutes, key: "staleAfterMinutes", limits: Self.staleAfterLimits) }
    }

    var staleThreshold: TimeInterval { Double(staleAfterMinutes) * 60 }

    /// Readings arrive every ~5 min, so anything far outside this is either
    /// wasteful or pointless.
    static let pollIntervalLimits: ClosedRange<Int> = 3...300

    var pollIntervalSeconds: Int = 60 {
        didSet {
            guard writeThrough(\.pollIntervalSeconds, key: "pollIntervalSeconds",
                               limits: Self.pollIntervalLimits) else { return }
            if oldValue != pollIntervalSeconds { onPollIntervalChanged?() }
        }
    }

    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A recognizable but unreadable form of a token, e.g. "re***ef". Tokens
    /// too short to elide meaningfully are masked entirely.
    static func maskedToken(_ token: String) -> String {
        guard token.count > 6 else { return String(repeating: "*", count: token.count) }
        return "\(token.prefix(2))***\(token.suffix(2))"
    }

    /// Compares resolved sRGB channels, because `Color ==` reports unequal for
    /// colors that render identically but came from different color spaces,
    /// which is exactly what happens to one loaded back from an archive.
    static func colorsMatch(_ a: Color, _ b: Color, eps: CGFloat = 0.01) -> Bool {
        guard let x = NSColor(a).usingColorSpace(.sRGB), let y = NSColor(b).usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < eps
            && abs(x.greenComponent - y.greenComponent) < eps
            && abs(x.blueComponent - y.blueComponent) < eps
            && abs(x.alphaComponent - y.alphaComponent) < eps
    }

    /// The saved preset currently in use, if any. One without an `appearance`
    /// is judged on its colors alone, so presets saved by an older version keep
    /// showing as selected instead of turning into "Custom".
    func matchingPreset() -> ColorPreset? {
        let current = currentColors()
        return colorPresets.first { preset in
            preset.backgroundEnabled == chartBackgroundEnabled
                && (preset.appearance == nil || preset.appearance == appearance)
                && Self.colorSlots.allSatisfy { slot in
                    guard let a = preset.colors[slot.key], let b = current[slot.key] else { return false }
                    return Self.colorsMatch(a, b)
                }
        }
    }

    /// Applies everything `preset` carries; anything it doesn't is left alone.
    func apply(_ preset: ColorPreset) {
        for slot in Self.colorSlots {
            if let color = preset.colors[slot.key] { self[keyPath: slot.keyPath] = color }
        }
        chartBackgroundEnabled = preset.backgroundEnabled
        if let appearance = preset.appearance { self.appearance = appearance }
    }

    func currentPreset(name: String) -> ColorPreset {
        ColorPreset(name: name, colors: currentColors(),
                    backgroundEnabled: chartBackgroundEnabled, appearance: appearance)
    }

    /// First unused "Palette N" name, so repeated saves don't collide.
    func defaultPresetName() -> String {
        let names = Set(colorPresets.map(\.name))
        var n = 1
        while names.contains("Palette \(n)") { n += 1 }
        return "Palette \(n)"
    }

    private func currentColors() -> [String: Color] {
        Self.colorSlots.reduce(into: [:]) { dict, slot in dict[slot.key] = self[keyPath: slot.keyPath] }
    }

    // MARK: - Init / persistence plumbing

    init(defaults: UserDefaults = .standard, tokens: any TokenStorage = KeychainTokenStore()) {
        self.defaults = defaults
        self.tokens = tokens
        Self.migrateThresholdsToMgdl(in: defaults)

        if let v = defaults.string(forKey: "baseURL") { baseURL = v }
        (token, tokenStorageFailed) = Self.migrateTokenToKeychain(defaults: defaults, tokens: tokens)
        if let v = defaults.string(forKey: "units").flatMap(Units.init) { units = v }
        if let v = defaults.object(forKey: "targetLow") as? Double { targetLow = v }
        if let v = defaults.object(forKey: "targetHigh") as? Double { targetHigh = v }
        if let v = defaults.object(forKey: "extremeLow") as? Double { extremeLow = v }
        if let v = defaults.object(forKey: "extremeHigh") as? Double { extremeHigh = v }
        // These go through the real setters, unlike the direct assignments
        // above, so `isLoading` has to stop them archiving back what they just
        // read. Otherwise today's defaults get frozen into the store for colors
        // the user never touched.
        for slot in Self.colorSlots {
            self[keyPath: slot.keyPath] = Self.loadColor(slot.key, default: slot.defaultValue, from: defaults)
        }
        isLoading = false
        chartBackgroundEnabled = defaults.bool(forKey: "chartBackgroundEnabled")
        blendLineColors = defaults.bool(forKey: "blendLineColors")
        // `object(forKey:)`, not `bool(forKey:)`: these default to true, and an
        // unset key would otherwise read back as false.
        if let v = defaults.object(forKey: "lineShadingEnabled") as? Bool { lineShadingEnabled = v }
        if let v = defaults.object(forKey: "lineShadingUsesLineColor") as? Bool { lineShadingUsesLineColor = v }
        if let v = defaults.object(forKey: "dotUsesZoneColor") as? Bool { dotUsesZoneColor = v }
        if let v = defaults.object(forKey: "dotRadius") as? Double { dotRadius = v }
        if let v = defaults.object(forKey: "dotHaloRadius") as? Double { dotHaloRadius = v }
        colorPresets = Self.loadPresets(from: defaults)
        if let v = defaults.object(forKey: "rangeHours") as? Int { rangeHours = v }
        if let v = defaults.string(forKey: "theme").flatMap(Theme.init) { theme = v }
        if let v = defaults.object(forKey: "deltaDisplay") as? Int, let d = DeltaDisplay(rawValue: v) { deltaDisplay = d }
        if let v = defaults.object(forKey: "pollIntervalSeconds") as? Int { pollIntervalSeconds = v }
        if let v = defaults.object(forKey: "staleAfterMinutes") as? Int { staleAfterMinutes = v }
    }

    /// One-time migration: earlier versions stored thresholds in mmol/L. Any
    /// stored value below 40 is clearly mmol, so scale it. Runs against the raw
    /// store, before values are read into this instance.
    private static func migrateThresholdsToMgdl(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "thresholdsMgdl") else { return }
        for key in ["targetLow", "targetHigh", "extremeLow", "extremeHigh"] {
            if let v = defaults.object(forKey: key) as? Double, v > 0, v < 40 {
                defaults.set((v * 18).rounded(), forKey: key)
            }
        }
        defaults.set(true, forKey: "thresholdsMgdl")
    }

    /// One-time migration of the token out of `UserDefaults` and into the
    /// Keychain. The plaintext copy going away is the point, so the old key is
    /// dropped even when the Keychain already held a token. It survives in one
    /// case only: a refused write, where dropping it would destroy the last copy.
    private static func migrateTokenToKeychain(defaults: UserDefaults, tokens: any TokenStorage)
        -> (token: String, failed: Bool) {
        let stored = tokens.load()
        guard let legacy = defaults.string(forKey: "token") else { return (stored, false) }
        guard stored.isEmpty, !legacy.isEmpty else {
            defaults.removeObject(forKey: "token")
            return (stored, false)
        }
        guard tokens.save(legacy) else { return (legacy, true) }
        defaults.removeObject(forKey: "token")
        return (legacy, false)
    }

    /// Write-through for a clamped numeric setting, called from that property's
    /// own `didSet`. An out-of-range value is re-assigned in clamped form, which
    /// re-enters here through the setter, and `false` is returned so the outer
    /// pass skips persisting and skips the change hook: the settling pass does
    /// both, exactly once.
    @discardableResult
    private func writeThrough<T: Comparable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>,
                                            key: String, limits: ClosedRange<T>) -> Bool {
        let value = self[keyPath: keyPath]
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        guard clamped == value else { self[keyPath: keyPath] = clamped; return false }
        defaults.set(value, forKey: key)
        return true
    }

    /// True only while `init` populates the colors; see the loop there.
    private var isLoading = true

    private func persistColor(_ color: Color, _ key: String) {
        guard !isLoading else { return }
        defaults.set(Self.archive(color), forKey: key)
    }

    private static func archive(_ color: Color) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: NSColor(color), requiringSecureCoding: true)
    }

    private static func loadColor(_ key: String, default fallback: Color, from defaults: UserDefaults) -> Color {
        guard let data = defaults.data(forKey: key),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return fallback }
        return Color(nsColor: ns)
    }

    private func persistPresets(_ presets: [ColorPreset]) {
        let raw: [[String: Any]] = presets.map { preset in
            var stored: [String: Any] = [
                "name": preset.name,
                "colors": preset.colors.compactMapValues(Self.archive),
                "backgroundEnabled": preset.backgroundEnabled,
            ]
            // JSON rather than a field per key, so adding an option to
            // `Appearance` needs no change here.
            if let appearance = preset.appearance,
               let data = try? JSONEncoder().encode(appearance) {
                stored["appearance"] = data
            }
            return stored
        }
        defaults.set(raw, forKey: "colorPresets")
    }

    private static func loadPresets(from defaults: UserDefaults) -> [ColorPreset] {
        guard let raw = defaults.array(forKey: "colorPresets") as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let archived = dict["colors"] as? [String: Data] ?? [:]
            var colors: [String: Color] = [:]
            for (key, data) in archived {
                if let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                    colors[key] = Color(nsColor: ns)
                }
            }
            // Absent for presets saved before appearances existed, and for
            // anything that fails to decode. Both mean "colors only".
            let appearance = (dict["appearance"] as? Data)
                .flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) }
            return ColorPreset(name: name, colors: colors,
                               backgroundEnabled: dict["backgroundEnabled"] as? Bool ?? false,
                               appearance: appearance)
        }
    }
}
