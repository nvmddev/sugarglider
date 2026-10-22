import SwiftUI

/// Each setting is a stored property whose `didSet` persists it: Observation
/// tracks only stored properties, so one computed over `UserDefaults` would
/// never trigger a redraw.
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let tokens: any TokenStorage

    // MARK: - Connection

    var baseURL: String = "" { didSet { persist(baseURL, "baseURL") } }

    /// Empty for a site that allows unauthenticated reads. Lives in the Keychain,
    /// not in `defaults`: a preferences plist is readable by any process running
    /// as the user.
    var token: String = "" {
        didSet {
            guard !isLoading, oldValue != token else { return }
            tokenStorageFailed = !tokens.save(token)
        }
    }

    /// The Keychain refused the last write, so the token won't survive a relaunch.
    /// No plist fallback on purpose: that is what the Keychain replaced.
    var tokenStorageFailed = false

    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var nightscout: Nightscout { Nightscout(baseURL: baseURL, token: token) }

    // MARK: - Glucose and display

    /// The display unit only: glucose is always held in mg/dL, Nightscout's native unit.
    enum Units: String {
        case mmol, mgdl

        static let mgdlPerMmol = 18.0

        var label: String { self == .mmol ? "mmol/L" : "mg/dL" }

        func value(fromMgdl mgdl: Double) -> Double { self == .mmol ? mgdl / Self.mgdlPerMmol : mgdl }
        func mgdl(from value: Double) -> Double { self == .mmol ? value * Self.mgdlPerMmol : value }
        func text(fromMgdl sgv: Int) -> String {
            self == .mmol ? value(fromMgdl: Double(sgv)).formatted(.number.precision(.fractionLength(1))) : sgv.formatted()
        }
    }

    var units: Units = .mmol { didSet { persist(units.rawValue, "units") } }

    // In mg/dL whatever `units` says.
    var targetLow: Double = 70 { didSet { persist(targetLow, "targetLow") } }
    var targetHigh: Double = 180 { didSet { persist(targetHigh, "targetHigh") } }
    var extremeLow: Double = 54 { didSet { persist(extremeLow, "extremeLow") } }
    var extremeHigh: Double = 250 { didSet { persist(extremeHigh, "extremeHigh") } }

    /// Out-of-order thresholds are reported, never corrected: moving a range takes one field at a
    /// time, so clamping a neighbor would fight the user mid-edit. They matter because
    /// `ChartMath.color(for:zones:)` tests them in order.
    var thresholdOrderWarning: String? {
        if targetLow >= targetHigh { return String(localized: "Low must be below High.") }
        if extremeLow > targetLow { return String(localized: "Very low can't be above Low.") }
        if extremeHigh < targetHigh { return String(localized: "Very high can't be below High.") }
        return nil
    }

    var thresholdFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0...(units == .mmol ? 1 : 0))).grouping(.never)
    }

    enum DropdownBackground: String { case glass, solid }

    var dropdownBackground: DropdownBackground = .glass {
        didSet { persist(dropdownBackground.rawValue, "dropdownBackground") }
    }

    enum DeltaDisplay: Int { case off = 0, menu = 1, menuAndStatusBar = 2 }

    var deltaDisplay: DeltaDisplay = .menu { didSet { persist(deltaDisplay.rawValue, "deltaDisplay") } }

    static let rangeHoursLimits: ClosedRange<Int> = 2...72

    var rangeHours: Int = 6 {
        didSet { writeThrough(\.rangeHours, key: "rangeHours", limits: Self.rangeHoursLimits) }
    }

    static let defaultStaleAfterMinutes = 11
    static let staleAfterLimits: ClosedRange<Int> = 5...240

    var staleAfterMinutes: Int = defaultStaleAfterMinutes {
        didSet { writeThrough(\.staleAfterMinutes, key: "staleAfterMinutes", limits: Self.staleAfterLimits) }
    }

    var staleThreshold: TimeInterval { Double(staleAfterMinutes) * 60 }

    static let pollIntervalLimits: ClosedRange<Int> = 3...300

    var pollIntervalSeconds: Int = 60 {
        didSet { writeThrough(\.pollIntervalSeconds, key: "pollIntervalSeconds", limits: Self.pollIntervalLimits) }
    }

    // MARK: - Chart look

    static let defaultBandColor = Color(nsColor: .labelColor).opacity(0.08)
    static let defaultInRangeColor = Color(nsColor: .labelColor)
    static let defaultBelowColor = Color(nsColor: .labelColor)
    static let defaultAboveColor = Color(nsColor: .labelColor)
    static let defaultExtremeLowColor = Color(nsColor: .labelColor)
    static let defaultExtremeHighColor = Color(nsColor: .labelColor)
    static let defaultLineShadingColor = Color(nsColor: .labelColor).opacity(0.14)
    static let defaultDotColor = Color(nsColor: .labelColor)
    static let defaultSliderColor = Color(nsColor: .tertiaryLabelColor)
    /// Opaque: with a clear default, the color picker's opacity slider would open at zero.
    static let defaultChartBackgroundColor = Color(nsColor: .controlBackgroundColor)
    static let defaultBolusColor = Color(nsColor: .labelColor).opacity(0.6)
    static let defaultDeliveryRateColor = Color(nsColor: .labelColor).opacity(0.4)
    static let defaultAnnouncementColor = Color(nsColor: .labelColor).opacity(0.45)

    var bandColor: Color = defaultBandColor { didSet { persistColor(bandColor, "bandColor") } }
    var inRangeColor: Color = defaultInRangeColor { didSet { persistColor(inRangeColor, "inRangeColor") } }
    var belowColor: Color = defaultBelowColor { didSet { persistColor(belowColor, "belowColor") } }
    var aboveColor: Color = defaultAboveColor { didSet { persistColor(aboveColor, "aboveColor") } }
    var extremeLowColor: Color = defaultExtremeLowColor { didSet { persistColor(extremeLowColor, "extremeLowColor") } }
    var extremeHighColor: Color = defaultExtremeHighColor {
        didSet { persistColor(extremeHighColor, "extremeHighColor") }
    }
    var lineShadingColor: Color = defaultLineShadingColor {
        didSet { persistColor(lineShadingColor, "lineShadingColor") }
    }
    var dotColor: Color = defaultDotColor { didSet { persistColor(dotColor, "dotColor") } }
    var sliderColor: Color = defaultSliderColor { didSet { persistColor(sliderColor, "sliderColor") } }
    var chartBackgroundColor: Color = defaultChartBackgroundColor {
        didSet { persistColor(chartBackgroundColor, "chartBackgroundColor") }
    }
    var bolusColor: Color = defaultBolusColor { didSet { persistColor(bolusColor, "bolusColor") } }
    var deliveryRateColor: Color = defaultDeliveryRateColor {
        didSet { persistColor(deliveryRateColor, "deliveryRateColor") }
    }
    var announcementColor: Color = defaultAnnouncementColor {
        didSet { persistColor(announcementColor, "announcementColor") }
    }

    var chartBackgroundEnabled: Bool = false {
        didSet { persist(chartBackgroundEnabled, "chartBackgroundEnabled") }
    }
    var blendLineColors: Bool = false { didSet { persist(blendLineColors, "blendLineColors") } }
    var lineShadingEnabled: Bool = true { didSet { persist(lineShadingEnabled, "lineShadingEnabled") } }
    /// Shade with the in-range zone color instead of `lineShadingColor`.
    var lineShadingUsesLineColor: Bool = true {
        didSet { persist(lineShadingUsesLineColor, "lineShadingUsesLineColor") }
    }
    var dotUsesZoneColor: Bool = true { didSet { persist(dotUsesZoneColor, "dotUsesZoneColor") } }

    enum LineShading: Hashable { case off, lineColor, custom }

    /// The two shading switches as the Colors tab's one menu. Off leaves `lineShadingUsesLineColor`
    /// alone, so switching shading back on returns to the color it had.
    var lineShading: LineShading {
        get {
            guard lineShadingEnabled else { return .off }
            return lineShadingUsesLineColor ? .lineColor : .custom
        }
        set {
            lineShadingEnabled = newValue != .off
            if newValue != .off { lineShadingUsesLineColor = newValue == .lineColor }
        }
    }

    // In points; 0 hides that part of the dot.
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

    /// The Colors tab's non-color options as one value, shared by the defaults,
    /// `resetColors()` and the presets, which store it as JSON.
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

    /// Computed, yet observed: it only reads stored properties.
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

    /// Everything on the Colors tab, nothing else.
    func resetColors() {
        for slot in Self.colorSlots { self[keyPath: slot.keyPath] = slot.defaultValue }
        chartBackgroundEnabled = false
        appearance = Self.defaultAppearance
    }

    // MARK: - Color presets

    /// Everything that treats the colors as a set iterates `colorSlots`, so a new
    /// color is a stored property plus one row there.
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
        .init(key: "bolusColor", keyPath: \.bolusColor, defaultValue: defaultBolusColor),
        .init(key: "deliveryRateColor", keyPath: \.deliveryRateColor, defaultValue: defaultDeliveryRateColor),
        .init(key: "announcementColor", keyPath: \.announcementColor, defaultValue: defaultAnnouncementColor),
    ]

    static var colorKeys: [String] { colorSlots.map(\.key) }

    struct ColorPreset {
        var name: String
        /// Keyed by `colorKeys`. A preset saved before a color existed lacks its key, and that
        /// color isn't part of it: `apply` leaves it alone and `matchingPreset()` ignores it.
        var colors: [String: Color]
        var backgroundEnabled: Bool
        /// Nil for presets saved before appearances existed: they carry colors only.
        var appearance: Appearance? = nil
    }

    var colorPresets: [ColorPreset] = [] { didSet { persistPresets() } }

    /// Replaces a preset of the same name.
    func saveColorPreset(_ preset: ColorPreset) {
        if let index = colorPresets.firstIndex(where: { $0.name == preset.name }) {
            colorPresets[index] = preset
        } else {
            colorPresets.append(preset)
        }
    }

    func deleteColorPreset(named name: String) {
        colorPresets.removeAll { $0.name == name }
    }

    func matchingPreset() -> ColorPreset? {
        colorPresets.first { preset in
            preset.backgroundEnabled == chartBackgroundEnabled
                && (preset.appearance == nil || preset.appearance == appearance)
                && Self.colorSlots.allSatisfy { slot in
                    preset.colors[slot.key].map { Self.colorsMatch($0, self[keyPath: slot.keyPath]) } ?? true
                }
        }
    }

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

    func defaultPresetName() -> String {
        let names = Set(colorPresets.map(\.name))
        var number = 1
        while names.contains("Palette \(number)") { number += 1 }
        return "Palette \(number)"
    }

    /// Compares sRGB channels, because `==` tells apart colors that render the same
    /// but come from different color spaces, as an archive round-trip produces.
    static func colorsMatch(_ a: Color, _ b: Color, eps: CGFloat = 0.01) -> Bool {
        guard let x = NSColor(a).usingColorSpace(.sRGB), let y = NSColor(b).usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < eps
            && abs(x.greenComponent - y.greenComponent) < eps
            && abs(x.blueComponent - y.blueComponent) < eps
            && abs(x.alphaComponent - y.alphaComponent) < eps
    }

    private func currentColors() -> [String: Color] {
        Self.colorSlots.reduce(into: [:]) { colors, slot in colors[slot.key] = self[keyPath: slot.keyPath] }
    }

    // MARK: - Pump

    var showActiveInsulin: Bool = true { didSet { persist(showActiveInsulin, "showActiveInsulin") } }
    var showPumpMode: Bool = true { didSet { persist(showPumpMode, "showPumpMode") } }
    var showDeliveryRate: Bool = true { didSet { persist(showDeliveryRate, "showDeliveryRate") } }
    var showReservoir: Bool = true { didSet { persist(showReservoir, "showReservoir") } }
    var showPumpBattery: Bool = true { didSet { persist(showPumpBattery, "showPumpBattery") } }
    /// Time since the last reservoir or battery change.
    var showChangeAge: Bool = false { didSet { persist(showChangeAge, "showChangeAge") } }
    var showDailyInsulin: Bool = false { didSet { persist(showDailyInsulin, "showDailyInsulin") } }
    var showAverageGlucose: Bool = false { didSet { persist(showAverageGlucose, "showAverageGlucose") } }

    var chartShowsBoluses: Bool = true { didSet { persist(chartShowsBoluses, "chartShowsBoluses") } }
    var chartShowsDeliveryRate: Bool = false {
        didSet { persist(chartShowsDeliveryRate, "chartShowsDeliveryRate") }
    }
    var chartShowsAnnouncements: Bool = false {
        didSet { persist(chartShowsAnnouncements, "chartShowsAnnouncements") }
    }

    var needsPumpStatus: Bool {
        showActiveInsulin || showPumpMode || showDeliveryRate || showReservoir || showPumpBattery
            || showDailyInsulin || showAverageGlucose
    }
    var needsTreatments: Bool { chartShowsBoluses || chartShowsDeliveryRate || chartShowsAnnouncements }
    var needsChangeDates: Bool { showChangeAge && (showReservoir || showPumpBattery) }

    // MARK: - Loading and persistence

    init(defaults: UserDefaults = .standard, tokens: any TokenStorage = KeychainTokenStore()) {
        self.defaults = defaults
        self.tokens = tokens
        Self.migrateThresholdsToMgdl(in: defaults)
        (token, tokenStorageFailed) = Self.migrateTokenToKeychain(defaults: defaults, tokens: tokens)

        load(\.baseURL, "baseURL")
        load(\.units, "units")
        load(\.targetLow, "targetLow")
        load(\.targetHigh, "targetHigh")
        load(\.extremeLow, "extremeLow")
        load(\.extremeHigh, "extremeHigh")
        load(\.dropdownBackground, "dropdownBackground")
        load(\.deltaDisplay, "deltaDisplay")
        load(\.rangeHours, "rangeHours")
        load(\.staleAfterMinutes, "staleAfterMinutes")
        load(\.pollIntervalSeconds, "pollIntervalSeconds")

        for slot in Self.colorSlots {
            if let color = defaults.data(forKey: slot.key).flatMap(Self.unarchiveColor) {
                self[keyPath: slot.keyPath] = color
            }
        }
        load(\.chartBackgroundEnabled, "chartBackgroundEnabled")
        load(\.blendLineColors, "blendLineColors")
        load(\.lineShadingEnabled, "lineShadingEnabled")
        load(\.lineShadingUsesLineColor, "lineShadingUsesLineColor")
        load(\.dotUsesZoneColor, "dotUsesZoneColor")
        load(\.dotRadius, "dotRadius")
        load(\.dotHaloRadius, "dotHaloRadius")
        colorPresets = Self.loadPresets(from: defaults)

        load(\.showActiveInsulin, "showActiveInsulin")
        load(\.showPumpMode, "showPumpMode")
        load(\.showDeliveryRate, "showDeliveryRate")
        load(\.showReservoir, "showReservoir")
        load(\.showPumpBattery, "showPumpBattery")
        load(\.showChangeAge, "showChangeAge")
        load(\.showDailyInsulin, "showDailyInsulin")
        load(\.showAverageGlucose, "showAverageGlucose")
        load(\.chartShowsBoluses, "chartShowsBoluses")
        load(\.chartShowsDeliveryRate, "chartShowsDeliveryRate")
        load(\.chartShowsAnnouncements, "chartShowsAnnouncements")
        isLoading = false
    }

    /// Assignments in `init` run `didSet` too. Without this, loading would write
    /// every value straight back and save the token to the Keychain again.
    @ObservationIgnored private var isLoading = true

    /// Assigns through the setter, so stored values are clamped too. An absent or
    /// mistyped value keeps the declared default, where `bool(forKey:)` would read
    /// an absent flag as false.
    private func load<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>, _ key: String) {
        if let value = defaults.object(forKey: key) as? Value { self[keyPath: keyPath] = value }
    }

    private func load<Value: RawRepresentable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>,
                                               _ key: String) {
        if let raw = defaults.object(forKey: key) as? Value.RawValue, let value = Value(rawValue: raw) {
            self[keyPath: keyPath] = value
        }
    }

    /// Older versions stored thresholds in mmol/L, and below 40 a value can only be that.
    private static func migrateThresholdsToMgdl(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "thresholdsMgdl") else { return }
        for key in ["targetLow", "targetHigh", "extremeLow", "extremeHigh"] {
            if let value = defaults.object(forKey: key) as? Double, value > 0, value < 40 {
                defaults.set(Units.mmol.mgdl(from: value).rounded(), forKey: key)
            }
        }
        defaults.set(true, forKey: "thresholdsMgdl")
    }

    /// Moves a token that older versions kept in the plist. The plist copy goes even
    /// when the Keychain already has a token, unless the Keychain refused the write
    /// and the plist holds the only copy.
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

    private func persist(_ value: Any?, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    /// Clamps and persists a bounded setting from its `didSet`. An out-of-range value is
    /// reassigned clamped, which runs the `didSet` again.
    private func writeThrough<Value: Comparable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>,
                                                 key: String, limits: ClosedRange<Value>) {
        let value = self[keyPath: keyPath]
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        if clamped == value { persist(value, key) } else { self[keyPath: keyPath] = clamped }
    }

    private func persistColor(_ color: Color, _ key: String) {
        persist(Self.archive(color), key)
    }

    private static func archive(_ color: Color) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: NSColor(color), requiringSecureCoding: true)
    }

    private static func unarchiveColor(_ data: Data) -> Color? {
        guard let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else { return nil }
        return Color(nsColor: color)
    }

    private func persistPresets() {
        let entries: [[String: Any]] = colorPresets.map { preset in
            var entry: [String: Any] = [
                "name": preset.name,
                "colors": preset.colors.compactMapValues(Self.archive),
                "backgroundEnabled": preset.backgroundEnabled,
            ]
            if let appearance = preset.appearance, let json = try? JSONEncoder().encode(appearance) {
                entry["appearance"] = json
            }
            return entry
        }
        persist(entries, "colorPresets")
    }

    private static func loadPresets(from defaults: UserDefaults) -> [ColorPreset] {
        let entries = defaults.array(forKey: "colorPresets") as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let archived = entry["colors"] as? [String: Data] ?? [:]
            let appearance = (entry["appearance"] as? Data)
                .flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) }
            return ColorPreset(name: name, colors: archived.compactMapValues(unarchiveColor),
                               backgroundEnabled: entry["backgroundEnabled"] as? Bool ?? false,
                               appearance: appearance)
        }
    }
}
