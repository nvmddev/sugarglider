import Testing
import SwiftUI
@testable import Sugarglider

/// Every persisted scalar setting in the format the app has always stored it,
/// each value off its default so a skipped key can't pass unnoticed.
private enum StoredSettings {
    static let strings: [String: String] = [
        "baseURL": "https://site.example", "units": "mgdl", "dropdownBackground": "solid",
    ]
    static let doubles: [String: Double] = [
        "targetLow": 80, "targetHigh": 190, "extremeLow": 50, "extremeHigh": 260,
        "dotRadius": 6.5, "dotHaloRadius": 9,
    ]
    static let ints: [String: Int] = [
        "rangeHours": 24, "deltaDisplay": 2, "pollIntervalSeconds": 30, "staleAfterMinutes": 20,
    ]
    static let bools: [String: Bool] = [
        "chartBackgroundEnabled": true, "blendLineColors": true, "lineShadingEnabled": false,
        "lineShadingUsesLineColor": false, "dotUsesZoneColor": false,
        "showActiveInsulin": false, "showPumpMode": false, "showDeliveryRate": false,
        "showReservoir": false, "showPumpBattery": false, "showChangeAge": true,
        "showDailyInsulin": true, "showAverageGlucose": true,
        "chartShowsBoluses": false, "chartShowsDeliveryRate": true, "chartShowsAnnouncements": true,
    ]

    static var keys: [String] {
        Array(strings.keys) + Array(doubles.keys) + Array(ints.keys) + Array(bools.keys)
    }
}

@MainActor private final class CountingTokenStore: TokenStorage {
    private(set) var saves = 0
    private let token: String

    init(_ token: String) { self.token = token }

    func load() -> String { token }

    func save(_ token: String) -> Bool {
        saves += 1
        return true
    }
}

// MARK: - Loading and persistence

extension SugargliderTests {
    @Test func emptyStoreYieldsTheDefaults() {
        let s = Self.makeSettings()
        #expect(s.baseURL == "")
        #expect(s.token == "")
        #expect(s.units == .mmol)
        #expect(s.dropdownBackground == .glass)
        #expect(s.deltaDisplay == .menu)
        #expect(s.targetLow == 70)
        #expect(s.targetHigh == 180)
        #expect(s.extremeLow == 54)
        #expect(s.extremeHigh == 250)
        #expect(s.rangeHours == 6)
        #expect(s.pollIntervalSeconds == 60)
        #expect(s.staleAfterMinutes == 11)
        #expect(s.staleAfterMinutes == AppSettings.defaultStaleAfterMinutes)
        #expect(!s.chartBackgroundEnabled)
        #expect(!s.blendLineColors)
        // True by default, which `UserDefaults.bool(forKey:)` would read as false.
        #expect(s.lineShadingEnabled)
        #expect(s.lineShadingUsesLineColor)
        #expect(s.dotUsesZoneColor)
        #expect(s.dotRadius == AppSettings.defaultDotRadius)
        #expect(s.dotHaloRadius == AppSettings.defaultDotHaloRadius)
        #expect(s.appearance == AppSettings.defaultAppearance)
        #expect(s.showActiveInsulin)
        #expect(s.showPumpMode)
        #expect(s.showDeliveryRate)
        #expect(s.showReservoir)
        #expect(s.showPumpBattery)
        #expect(!s.showChangeAge)
        #expect(!s.showDailyInsulin)
        #expect(!s.showAverageGlucose)
        #expect(s.chartShowsBoluses)
        #expect(!s.chartShowsDeliveryRate)
        #expect(!s.chartShowsAnnouncements)
        #expect(s.colorPresets.isEmpty)
    }

    /// Seeded rather than written through the setters, so a renamed key or a
    /// changed value type fails here instead of round-tripping consistently.
    @Test func everySettingLoadsFromItsStoredKey() {
        let defaults = Self.makeDefaults()
        for (key, value) in StoredSettings.strings { defaults.set(value, forKey: key) }
        for (key, value) in StoredSettings.doubles { defaults.set(value, forKey: key) }
        for (key, value) in StoredSettings.ints { defaults.set(value, forKey: key) }
        for (key, value) in StoredSettings.bools { defaults.set(value, forKey: key) }

        let s = Self.makeSettings(defaults: defaults)
        #expect(s.baseURL == "https://site.example")
        #expect(s.units == .mgdl)
        #expect(s.dropdownBackground == .solid)
        #expect(s.targetLow == 80)
        #expect(s.targetHigh == 190)
        #expect(s.extremeLow == 50)
        #expect(s.extremeHigh == 260)
        #expect(s.dotRadius == 6.5)
        #expect(s.dotHaloRadius == 9)
        #expect(s.rangeHours == 24)
        #expect(s.deltaDisplay == .menuAndStatusBar)
        #expect(s.pollIntervalSeconds == 30)
        #expect(s.staleAfterMinutes == 20)
        #expect(s.chartBackgroundEnabled)
        #expect(s.blendLineColors)
        #expect(!s.lineShadingEnabled)
        #expect(!s.lineShadingUsesLineColor)
        #expect(!s.dotUsesZoneColor)
        #expect(!s.showActiveInsulin)
        #expect(!s.showPumpMode)
        #expect(!s.showDeliveryRate)
        #expect(!s.showReservoir)
        #expect(!s.showPumpBattery)
        #expect(s.showChangeAge)
        #expect(s.showDailyInsulin)
        #expect(s.showAverageGlucose)
        #expect(!s.chartShowsBoluses)
        #expect(s.chartShowsDeliveryRate)
        #expect(s.chartShowsAnnouncements)
    }

    @Test func lineShadingMenuMapsOntoBothSwitches() {
        let s = Self.makeSettings()
        #expect(s.lineShading == .lineColor)
        s.lineShading = .custom
        #expect(s.lineShadingEnabled && !s.lineShadingUsesLineColor)
        s.lineShading = .off
        #expect(!s.lineShadingEnabled)
        #expect(!s.lineShadingUsesLineColor, "off keeps the color choice")
        #expect(s.lineShading == .off)
        s.lineShadingEnabled = true
        #expect(s.lineShading == .custom)
        s.lineShading = .lineColor
        #expect(s.lineShadingEnabled && s.lineShadingUsesLineColor)
    }

    @Test func everySettingPersistsUnderItsKeyInItsStoredType() {
        let defaults = Self.makeDefaults()
        let s = Self.makeSettings(defaults: defaults)
        s.baseURL = "https://site.example"
        s.units = .mgdl
        s.dropdownBackground = .solid
        s.targetLow = 80
        s.targetHigh = 190
        s.extremeLow = 50
        s.extremeHigh = 260
        s.appearance = .init(blendLineColors: true, lineShadingEnabled: false, lineShadingUsesLineColor: false,
                             dotUsesZoneColor: false, dotRadius: 6.5, dotHaloRadius: 9)
        s.chartBackgroundEnabled = true
        s.rangeHours = 24
        s.deltaDisplay = .menuAndStatusBar
        s.pollIntervalSeconds = 30
        s.staleAfterMinutes = 20
        s.showActiveInsulin = false
        s.showPumpMode = false
        s.showDeliveryRate = false
        s.showReservoir = false
        s.showPumpBattery = false
        s.showChangeAge = true
        s.showDailyInsulin = true
        s.showAverageGlucose = true
        s.chartShowsBoluses = false
        s.chartShowsDeliveryRate = true
        s.chartShowsAnnouncements = true

        for (key, value) in StoredSettings.strings { #expect(defaults.object(forKey: key) as? String == value, "\(key)") }
        for (key, value) in StoredSettings.doubles { #expect(defaults.object(forKey: key) as? Double == value, "\(key)") }
        for (key, value) in StoredSettings.ints { #expect(defaults.object(forKey: key) as? Int == value, "\(key)") }
        for (key, value) in StoredSettings.bools { #expect(defaults.object(forKey: key) as? Bool == value, "\(key)") }
    }

    @Test func outOfRangeStoredValuesAreClampedOnLoad() {
        let defaults = Self.makeDefaults()
        defaults.set(100, forKey: "rangeHours")
        defaults.set(1, forKey: "pollIntervalSeconds")
        defaults.set(9999, forKey: "staleAfterMinutes")
        defaults.set(-1.0, forKey: "dotRadius")
        defaults.set(99.0, forKey: "dotHaloRadius")
        let s = Self.makeSettings(defaults: defaults)
        #expect(s.rangeHours == AppSettings.rangeHoursLimits.upperBound)
        #expect(s.pollIntervalSeconds == AppSettings.pollIntervalLimits.lowerBound)
        #expect(s.staleAfterMinutes == AppSettings.staleAfterLimits.upperBound)
        #expect(s.dotRadius == AppSettings.dotRadiusLimits.lowerBound)
        #expect(s.dotHaloRadius == AppSettings.dotHaloRadiusLimits.upperBound)
        // The clamping setters ran during init, and loading still writes nothing back.
        #expect(defaults.integer(forKey: "rangeHours") == 100)
        #expect(defaults.double(forKey: "dotHaloRadius") == 99)
    }

    @Test func unreadableStoredValuesKeepTheDefaults() {
        let defaults = Self.makeDefaults()
        defaults.set("metric", forKey: "units")
        defaults.set("frosted", forKey: "dropdownBackground")
        defaults.set(7, forKey: "deltaDisplay")
        defaults.set("lots", forKey: "rangeHours")
        let s = Self.makeSettings(defaults: defaults)
        #expect(s.units == .mmol)
        #expect(s.dropdownBackground == .glass)
        #expect(s.deltaDisplay == .menu)
        #expect(s.rangeHours == 6)
    }

    /// Archiving a default color, for one, would pin it against later changes to that default.
    @Test func loadingWritesNothingBack() {
        let defaults = Self.makeDefaults()
        _ = Self.makeSettings(defaults: defaults)
        let written = (StoredSettings.keys + AppSettings.colorKeys + ["colorPresets", "token"])
            .filter { defaults.object(forKey: $0) != nil }
        #expect(written.isEmpty, "loading wrote \(written)")
    }

    @Test func loadingDoesNotSaveTheTokenAgain() {
        let tokens = CountingTokenStore("monitor-current")
        let s = Self.makeSettings(tokens: tokens)
        #expect(s.token == "monitor-current")
        #expect(tokens.saves == 0)
    }

    /// A stored 0 is a value, not "never set".
    @Test func zeroThresholdSurvivesARelaunch() {
        let defaults = Self.makeDefaults()
        Self.makeSettings(defaults: defaults).targetLow = 0
        #expect(Self.makeSettings(defaults: defaults).targetLow == 0)
    }
}

// MARK: - Scalar settings

extension SugargliderTests {
    @Test func thresholdOrderWarning() {
        let s = Self.makeSettings()
        #expect(s.thresholdOrderWarning == nil)

        s.targetLow = 200
        #expect(s.thresholdOrderWarning == "Low must be below High.")
        #expect(s.targetLow == 200)

        let low = Self.makeSettings()
        low.extremeLow = 90
        #expect(low.thresholdOrderWarning == "Very low can't be above Low.")

        let high = Self.makeSettings()
        high.extremeHigh = 100
        #expect(high.thresholdOrderWarning == "Very high can't be below High.")

        // Equal bounds just mean no separate extreme zone.
        let touching = Self.makeSettings()
        touching.extremeLow = touching.targetLow
        touching.extremeHigh = touching.targetHigh
        #expect(touching.thresholdOrderWarning == nil)
    }

    @Test func rangeHoursIsClampedToItsLimits() {
        let s = Self.makeSettings()
        s.rangeHours = 24
        #expect(s.rangeHours == 24)
        s.rangeHours = 72
        #expect(s.rangeHours == 72)
        s.rangeHours = 100
        #expect(s.rangeHours == 72)
        s.rangeHours = 1
        #expect(s.rangeHours == 2)
        s.rangeHours = -5
        #expect(s.rangeHours == 2)
    }

    @Test func pollIntervalIsClampedToItsLimits() {
        let s = Self.makeSettings()
        s.pollIntervalSeconds = 30
        #expect(s.pollIntervalSeconds == 30)
        s.pollIntervalSeconds = 1
        #expect(s.pollIntervalSeconds == AppSettings.pollIntervalLimits.lowerBound)
        s.pollIntervalSeconds = 9999
        #expect(s.pollIntervalSeconds == AppSettings.pollIntervalLimits.upperBound)
    }

    @Test func staleDelayIsClampedAndExposedInSeconds() {
        let s = Self.makeSettings()
        #expect(s.staleThreshold == 11 * 60)
        s.staleAfterMinutes = 20
        #expect(s.staleThreshold == 20 * 60)
        s.staleAfterMinutes = 1
        #expect(s.staleAfterMinutes == AppSettings.staleAfterLimits.lowerBound)
        s.staleAfterMinutes = 9999
        #expect(s.staleAfterMinutes == AppSettings.staleAfterLimits.upperBound)
    }

    @Test func dotSizesAreClampedAndZeroIsValid() {
        let s = Self.makeSettings()
        s.dotRadius = 0
        #expect(s.dotRadius == 0)
        s.dotRadius = -3
        #expect(s.dotRadius == 0)
        s.dotRadius = 99
        #expect(s.dotRadius == 12)
        s.dotHaloRadius = 99
        #expect(s.dotHaloRadius == 24)
    }

    /// The Settings sliders and the dropdown's range slider are built from these,
    /// so a clamp that disagreed with them would fight the control.
    @Test func clampLimitsAreTheOnesTheUIOffers() {
        #expect(AppSettings.rangeHoursLimits == 2...72)
        #expect(AppSettings.dotRadiusLimits == 0...12)
        #expect(AppSettings.dotHaloRadiusLimits == 0...24)
        #expect(AppSettings.pollIntervalLimits == 3...300)
        #expect(AppSettings.staleAfterLimits == 5...240)
    }

    @Test func isConfiguredNeedsANonBlankURL() {
        let s = Self.makeSettings()
        #expect(!s.isConfigured)
        s.baseURL = "   "
        #expect(!s.isConfigured)
        s.baseURL = "https://site.example"
        #expect(s.isConfigured)
    }
}

// MARK: - Number formatting

extension SugargliderTests {
    /// Pinned to a locale here only so the expectations don't depend on this machine's region.
    @Test func thresholdFieldsShowOneDecimalInMmolOnly() {
        let s = Self.makeSettings()
        let us = Locale(identifier: "en_US"), german = Locale(identifier: "de_DE")
        s.units = .mmol
        #expect(10.5.formatted(s.thresholdFormat.locale(us)) == "10.5")
        #expect(10.5.formatted(s.thresholdFormat.locale(german)) == "10,5")
        #expect(10.0.formatted(s.thresholdFormat.locale(us)) == "10")
        #expect(1234.5.formatted(s.thresholdFormat.locale(us)) == "1234.5")
        s.units = .mgdl
        #expect(180.4.formatted(s.thresholdFormat.locale(us)) == "180")
    }

    @Test func thresholdFieldsParseWhatTheyShow() throws {
        let s = Self.makeSettings()
        s.units = .mmol
        #expect(try s.thresholdFormat.locale(Locale(identifier: "en_US")).parseStrategy.parse("10.5") == 10.5)
        #expect(try s.thresholdFormat.locale(Locale(identifier: "de_DE")).parseStrategy.parse("10,5") == 10.5)
    }
}

// MARK: - Threshold migration

extension SugargliderTests {
    @Test func migrationScalesLegacyMmolToMgdl() {
        let defaults = Self.makeDefaults()
        defaults.set(3.9, forKey: "targetLow")
        defaults.set(10.0, forKey: "targetHigh")
        defaults.set(3.0, forKey: "extremeLow")
        defaults.set(13.9, forKey: "extremeHigh")
        let s = Self.makeSettings(defaults: defaults)
        #expect(s.targetLow == 70)     // 70.2, rounded
        #expect(s.targetHigh == 180)
        #expect(s.extremeLow == 54)
        #expect(s.extremeHigh == 250)  // 250.2, rounded
    }

    @Test func migrationLeavesMgdlValuesAlone() {
        let defaults = Self.makeDefaults()
        defaults.set(180.0, forKey: "targetHigh")
        #expect(Self.makeSettings(defaults: defaults).targetHigh == 180)
    }

    @Test func migrationRunsOnlyOnce() {
        let defaults = Self.makeDefaults()
        defaults.set(3.9, forKey: "targetLow")
        _ = Self.makeSettings(defaults: defaults)
        #expect(defaults.double(forKey: "targetLow") == 70)

        defaults.set(3.9, forKey: "targetLow")
        #expect(Self.makeSettings(defaults: defaults).targetLow == 3.9)
    }
}

// MARK: - Colors

extension SugargliderTests {
    @Test func colorDefaultsWhenUnset() {
        let s = Self.makeSettings()
        #expect(AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))
        #expect(AppSettings.colorsMatch(s.bandColor, AppSettings.defaultBandColor))
        #expect(AppSettings.colorsMatch(s.sliderColor, AppSettings.defaultSliderColor))
        #expect(AppSettings.colorsMatch(s.lineShadingColor, AppSettings.defaultLineShadingColor))
        #expect(AppSettings.colorsMatch(s.dotColor, AppSettings.defaultDotColor))
    }

    @Test func colorRoundTripsThroughTheArchive() {
        let defaults = Self.makeDefaults()
        let s = Self.makeSettings(defaults: defaults)
        let custom = Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        s.inRangeColor = custom
        #expect(AppSettings.colorsMatch(s.inRangeColor, custom))
        #expect(AppSettings.colorsMatch(Self.makeSettings(defaults: defaults).inRangeColor, custom))
    }

    /// Colors and presets are stored as keyed archives of `NSColor`.
    @Test func colorsLoadFromArchivedNSColor() throws {
        let defaults = Self.makeDefaults()
        let red = try NSKeyedArchiver.archivedData(withRootObject: NSColor.red, requiringSecureCoding: true)
        defaults.set(red, forKey: "inRangeColor")
        defaults.set([["name": "Old", "colors": ["bandColor": red], "backgroundEnabled": true]],
                     forKey: "colorPresets")

        let s = Self.makeSettings(defaults: defaults)
        #expect(AppSettings.colorsMatch(s.inRangeColor, Color(nsColor: .red)))
        let preset = try #require(s.colorPresets.first)
        #expect(preset.name == "Old")
        #expect(preset.backgroundEnabled)
        #expect(preset.appearance == nil)
        #expect(AppSettings.colorsMatch(try #require(preset.colors["bandColor"]), Color(nsColor: .red)))
    }

    @Test func resetColorsRestoresDefaultsAndClearsBackground() {
        let s = Self.makeSettings()
        s.inRangeColor = Color(red: 1, green: 0, blue: 0, opacity: 1)
        s.chartBackgroundEnabled = true
        #expect(!AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))

        s.resetColors()
        #expect(AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))
        #expect(!s.chartBackgroundEnabled)
    }

    @Test func resetColorsRestoresShadingAndDotAppearance() {
        let s = Self.makeSettings()
        s.blendLineColors = true
        s.lineShadingEnabled = false
        s.lineShadingUsesLineColor = false
        s.lineShadingColor = Color(red: 1, green: 0, blue: 0, opacity: 1)
        s.dotUsesZoneColor = false
        s.dotColor = Color(red: 0, green: 1, blue: 0, opacity: 1)
        s.dotRadius = 1
        s.dotHaloRadius = 20

        s.resetColors()
        #expect(s.appearance == AppSettings.defaultAppearance)
        #expect(!s.blendLineColors)
        #expect(s.lineShadingEnabled)
        #expect(s.lineShadingUsesLineColor)
        #expect(s.dotUsesZoneColor)
        #expect(s.dotRadius == AppSettings.defaultDotRadius)
        #expect(s.dotHaloRadius == AppSettings.defaultDotHaloRadius)
        #expect(AppSettings.colorsMatch(s.lineShadingColor, AppSettings.defaultLineShadingColor))
        #expect(AppSettings.colorsMatch(s.dotColor, AppSettings.defaultDotColor))
    }

    @Test func colorsMatchComparesResolvedChannels() {
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        #expect(AppSettings.colorsMatch(red, red))
        #expect(AppSettings.colorsMatch(red, Color(red: 1, green: 0, blue: 0, opacity: 1)))
        #expect(!AppSettings.colorsMatch(red, Color(red: 0, green: 0, blue: 1, opacity: 1)))
    }
}

// MARK: - Color presets

extension SugargliderTests {
    @Test func colorKeysAreEveryConfigurableColor() {
        #expect(AppSettings.colorKeys == [
            "bandColor", "inRangeColor", "belowColor", "aboveColor",
            "extremeLowColor", "extremeHighColor", "lineShadingColor", "dotColor",
            "sliderColor", "chartBackgroundColor", "bolusColor", "deliveryRateColor", "announcementColor",
        ])
    }

    /// The load, the reset and the preset round-trip all read `colorSlots`.
    @Test func colorSlotsPointAtTheirOwnProperty() {
        let s = Self.makeSettings()
        #expect(AppSettings.colorSlots.count == AppSettings.colorKeys.count)
        for slot in AppSettings.colorSlots {
            #expect(AppSettings.colorsMatch(s[keyPath: slot.keyPath], slot.defaultValue),
                    "\(slot.key) default mismatch")
            let probe = Color(red: 0.42, green: 0.17, blue: 0.93, opacity: 1)
            s[keyPath: slot.keyPath] = probe
            let hits = AppSettings.colorSlots.filter { AppSettings.colorsMatch(s[keyPath: $0.keyPath], probe) }
            #expect(hits.map(\.key) == [slot.key], "\(slot.key) key path is not unique")
            s[keyPath: slot.keyPath] = slot.defaultValue
        }
    }

    /// A key that `apply` or `currentPreset` misses makes `matchingPreset()`
    /// report "Custom" forever.
    @Test func everyColorKeyRoundTripsThroughAPreset() throws {
        let s = Self.makeSettings()
        let distinct = AppSettings.colorKeys.enumerated().reduce(into: [String: Color]()) { dict, pair in
            dict[pair.element] = Color(red: Double(pair.offset) / 16, green: 0.3, blue: 0.7, opacity: 1)
        }
        s.apply(.init(name: "P", colors: distinct, backgroundEnabled: true))
        let snapshot = s.currentPreset(name: "P")
        for key in AppSettings.colorKeys {
            let expected = try #require(distinct[key])
            let actual = try #require(snapshot.colors[key], "\(key) missing from currentPreset")
            #expect(AppSettings.colorsMatch(actual, expected), "\(key) not applied")
        }
    }

    @Test func savedPresetSurvivesARelaunch() throws {
        let defaults = Self.makeDefaults()
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let green = Color(red: 0, green: 1, blue: 0, opacity: 1)
        Self.makeSettings(defaults: defaults)
            .saveColorPreset(.init(name: "P", colors: ["bandColor": red, "sliderColor": green], backgroundEnabled: true))

        let presets = Self.makeSettings(defaults: defaults).colorPresets
        #expect(presets.count == 1)
        let p = try #require(presets.first)
        #expect(p.name == "P")
        #expect(p.backgroundEnabled)
        #expect(AppSettings.colorsMatch(try #require(p.colors["bandColor"]), red))
        #expect(AppSettings.colorsMatch(try #require(p.colors["sliderColor"]), green))
    }

    @Test func savePresetWithSameNameReplaces() throws {
        let s = Self.makeSettings()
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let blue = Color(red: 0, green: 0, blue: 1, opacity: 1)
        s.saveColorPreset(.init(name: "P", colors: ["bandColor": red], backgroundEnabled: false))
        s.saveColorPreset(.init(name: "P", colors: ["bandColor": blue], backgroundEnabled: true))
        #expect(s.colorPresets.count == 1)
        let p = try #require(s.colorPresets.first)
        #expect(p.backgroundEnabled)
        #expect(AppSettings.colorsMatch(try #require(p.colors["bandColor"]), blue))
    }

    @Test func deletePreset() {
        let s = Self.makeSettings()
        s.saveColorPreset(.init(name: "A", colors: [:], backgroundEnabled: false))
        s.saveColorPreset(.init(name: "B", colors: [:], backgroundEnabled: false))
        s.deleteColorPreset(named: "A")
        #expect(s.colorPresets.map(\.name) == ["B"])
        s.deleteColorPreset(named: "does-not-exist")
        #expect(s.colorPresets.map(\.name) == ["B"])
    }

    @Test func defaultPresetNameSkipsTakenNames() {
        let s = Self.makeSettings()
        #expect(s.defaultPresetName() == "Palette 1")
        s.saveColorPreset(.init(name: "Palette 1", colors: [:], backgroundEnabled: false))
        #expect(s.defaultPresetName() == "Palette 2")
    }

    @Test func matchingPresetFindsSavedPalette() {
        let s = Self.makeSettings()
        s.saveColorPreset(s.currentPreset(name: "cur"))
        #expect(s.matchingPreset()?.name == "cur")
    }

    @Test func matchingPresetNilWhenNoFullMatch() {
        let s = Self.makeSettings()
        s.saveColorPreset(.init(name: "partial",
                                colors: ["bandColor": Color(red: 1, green: 0, blue: 0, opacity: 1)],
                                backgroundEnabled: false))
        #expect(s.matchingPreset() == nil)
    }

    @Test func appearanceIsAViewOverTheStoredFlags() {
        let s = Self.makeSettings()
        s.appearance = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                              lineShadingUsesLineColor: false, dotUsesZoneColor: false,
                                              dotRadius: 2, dotHaloRadius: 9)
        #expect(s.blendLineColors)
        #expect(!s.lineShadingEnabled)
        #expect(!s.lineShadingUsesLineColor)
        #expect(!s.dotUsesZoneColor)
        #expect(s.dotRadius == 2)
        #expect(s.dotHaloRadius == 9)
        s.dotRadius = 5
        #expect(s.appearance.dotRadius == 5)
    }

    /// A preset is the whole look: it brings its line, shading and dot settings
    /// along, survives a relaunch, and stops matching once one of them changes.
    @Test func presetsCarryTheAppearance() throws {
        let defaults = Self.makeDefaults()
        let s = Self.makeSettings(defaults: defaults)
        let look = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                          lineShadingUsesLineColor: true, dotUsesZoneColor: false,
                                          dotRadius: 6.5, dotHaloRadius: 0)
        s.appearance = look
        s.chartBackgroundEnabled = true
        s.saveColorPreset(s.currentPreset(name: "full"))

        #expect(s.colorPresets.first?.appearance == look)
        #expect(s.matchingPreset()?.name == "full")
        s.blendLineColors = false
        #expect(s.matchingPreset() == nil)

        s.appearance = AppSettings.defaultAppearance
        s.apply(try #require(s.colorPresets.first))
        #expect(s.appearance == look)

        #expect(Self.makeSettings(defaults: defaults).colorPresets.first?.appearance == look)
    }

    /// Presets saved before appearances existed must still register as selected
    /// after an update, rather than turning into "Custom".
    @Test func presetsWithoutAnAppearanceApplyColorsOnly() {
        let s = Self.makeSettings()
        let look = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                          lineShadingUsesLineColor: true, dotUsesZoneColor: false,
                                          dotRadius: 6.5, dotHaloRadius: 0)
        s.appearance = look
        var legacy = s.currentPreset(name: "legacy")
        legacy.appearance = nil
        s.saveColorPreset(legacy)

        #expect(s.matchingPreset()?.name == "legacy")
        s.apply(legacy)
        #expect(s.appearance == look)
    }

    /// Likewise for a color added after the preset was saved: without this, every preset
    /// would turn into "Custom" with the update that adds a color.
    @Test func presetsWithoutAColorLeaveItAlone() {
        let s = Self.makeSettings()
        var legacy = s.currentPreset(name: "legacy")
        legacy.colors["bolusColor"] = nil
        s.saveColorPreset(legacy)
        #expect(s.matchingPreset()?.name == "legacy")

        let bolus = Color(red: 0.2, green: 0.4, blue: 0.9, opacity: 1)
        s.bolusColor = bolus
        #expect(s.matchingPreset()?.name == "legacy")
        s.apply(legacy)
        #expect(AppSettings.colorsMatch(s.bolusColor, bolus))

        // The colors it does carry still decide.
        s.inRangeColor = Color(red: 1, green: 0, blue: 0, opacity: 1)
        #expect(s.matchingPreset() == nil)
    }

    @Test func applyPresetSetsColorsAndBackgroundFlag() {
        let s = Self.makeSettings()
        let band = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let background = Color(red: 0, green: 0, blue: 1, opacity: 1)
        s.apply(.init(name: "P", colors: ["bandColor": band, "chartBackgroundColor": background],
                      backgroundEnabled: true))
        #expect(AppSettings.colorsMatch(s.bandColor, band))
        #expect(AppSettings.colorsMatch(s.chartBackgroundColor, background))
        #expect(s.chartBackgroundEnabled)
    }
}

// MARK: - Access token storage

extension SugargliderTests {
    /// Any process running as the user can read the plist; keeping the token out of it is the point.
    @Test func tokenPersistsToTheTokenStoreNotDefaults() {
        let defaults = Self.makeDefaults()
        let tokens = InMemoryTokenStore()
        let s = Self.makeSettings(defaults: defaults, tokens: tokens)
        s.token = "monitor-abc"
        #expect(s.token == "monitor-abc")
        #expect(tokens.stored == "monitor-abc")
        #expect(defaults.string(forKey: "token") == nil)
    }

    /// Otherwise the next launch would find the old token again.
    @Test func clearingTheTokenEmptiesTheStore() {
        let tokens = InMemoryTokenStore("monitor-abc")
        let s = Self.makeSettings(tokens: tokens)
        #expect(s.token == "monitor-abc")
        s.token = ""
        #expect(tokens.stored == "")
    }

    @Test func legacyTokenMigratesOutOfDefaults() {
        let defaults = Self.makeDefaults()
        defaults.set("monitor-legacy", forKey: "token")
        let tokens = InMemoryTokenStore()
        let s = Self.makeSettings(defaults: defaults, tokens: tokens)
        #expect(s.token == "monitor-legacy")
        #expect(tokens.stored == "monitor-legacy")
        #expect(defaults.string(forKey: "token") == nil)
    }

    @Test func storedTokenWinsOverStaleLegacyTokenWhichIsStillRemoved() {
        let defaults = Self.makeDefaults()
        defaults.set("monitor-legacy", forKey: "token")
        let s = Self.makeSettings(defaults: defaults, tokens: InMemoryTokenStore("monitor-current"))
        #expect(s.token == "monitor-current")
        #expect(defaults.string(forKey: "token") == nil)
    }

    /// Dropping the plist key after a refused write would lose the only copy.
    @Test func refusedMigrationIsReportedAndKeepsTheOldKey() {
        let defaults = Self.makeDefaults()
        defaults.set("monitor-legacy", forKey: "token")
        let tokens = InMemoryTokenStore()
        tokens.refuseWrites = true
        let s = Self.makeSettings(defaults: defaults, tokens: tokens)
        #expect(s.token == "monitor-legacy")
        #expect(s.tokenStorageFailed)
        #expect(defaults.string(forKey: "token") == "monitor-legacy")
    }

    @Test func refusedWriteSetsTheFlagAndASuccessClearsIt() {
        let tokens = InMemoryTokenStore()
        let s = Self.makeSettings(tokens: tokens)
        tokens.refuseWrites = true
        s.token = "monitor-abc"
        #expect(s.tokenStorageFailed)
        tokens.refuseWrites = false
        s.token = "monitor-def"
        #expect(!s.tokenStorageFailed)
    }

    /// A refused first migration keeps the plist copy. Clearing the token then used to save an
    /// empty store without touching the plist, so the next launch re-migrated the deleted token.
    @Test func clearedTokenStaysGoneWhenTheMigrationWasRefused() {
        let defaults = Self.makeDefaults()
        defaults.set("monitor-legacy", forKey: "token")
        let tokens = InMemoryTokenStore()
        tokens.refuseWrites = true
        let s = Self.makeSettings(defaults: defaults, tokens: tokens)
        #expect(s.token == "monitor-legacy")
        #expect(s.tokenStorageFailed)
        #expect(defaults.string(forKey: "token") == "monitor-legacy")   // the only copy stays

        tokens.refuseWrites = false
        s.token = ""   // the user clears the token
        #expect(!s.tokenStorageFailed)
        #expect(defaults.string(forKey: "token") == nil)   // nothing to resurrect

        let relaunch = Self.makeSettings(defaults: defaults, tokens: InMemoryTokenStore())
        #expect(relaunch.token == "")
        #expect(!relaunch.tokenStorageFailed)
    }

    /// After a refused save the flag used to clear only for a different value; re-entering the
    /// same token skipped the save and left the token memory-only.
    @Test func reenteringTheSameTokenRetriesAfterARefusedSave() {
        let tokens = InMemoryTokenStore()
        let s = Self.makeSettings(tokens: tokens)
        tokens.refuseWrites = true
        s.token = "monitor-abc"
        #expect(s.tokenStorageFailed)
        #expect(tokens.stored.isEmpty)

        tokens.refuseWrites = false
        s.token = "monitor-abc"   // the same value: the flag lets the save through
        #expect(!s.tokenStorageFailed)
        #expect(tokens.stored == "monitor-abc")
    }
}
