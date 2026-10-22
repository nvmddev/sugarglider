import SwiftUI
import AppKit

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(settings: settings) }
            Tab("Colors", systemImage: "paintpalette") { ColorsTab(settings: settings) }
            Tab("Glucose", systemImage: "drop") { GlucoseTab(settings: settings) }
            Tab("Pump", systemImage: "syringe") { PumpTab(settings: settings) }
            Tab("About", systemImage: "info.circle") { AboutTab(settings: settings) }
        }
        // Every tab is a .grouped Form, which scrolls where a plain one would clip.
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .windowResizable(defaultSize: CGSize(width: 500, height: 700), autosaveName: "SettingsWindow")
        // Not .windowTheme(_:): SwiftUI resets a manual NSWindow.appearance on this window within milliseconds.
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

private struct GeneralTab: View {
    @Bindable var settings: AppSettings
    @FocusState private var tokenFieldFocused: Bool
    @State private var status = ConnectionStatus.unconfigured

    private enum ConnectionStatus {
        case unconfigured
        case checking
        case probed(Nightscout.ProbeResult)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nightscout URL", text: $settings.baseURL,
                          prompt: Text("https://your-site.nightscout.app"))
                TextField("Access token", text: tokenText, prompt: Text("e.g. monitor-1a2b3c4d"))
                    .focused($tokenFieldFocused)
                LabeledContent("Status") { statusView }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave the token empty if your site allows unauthenticated reads. "
                         + "It is kept in your Keychain, not in the preferences file.")
                    if settings.tokenStorageFailed {
                        Text("The Keychain refused to store the token, so Sugarglider will "
                             + "forget it when it quits.")
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Theme", selection: $settings.theme) {
                    Text("Automatic").tag(AppSettings.Theme.system)
                    Text("Light").tag(AppSettings.Theme.light)
                    Text("Dark").tag(AppSettings.Theme.dark)
                }
                Picker("Dropdown background", selection: $settings.dropdownBackground) {
                    Text("Glass").tag(AppSettings.DropdownBackground.glass)
                    Text("Solid").tag(AppSettings.DropdownBackground.solid)
                }
                Picker("Units", selection: $settings.units) {
                    Text("mmol/L").tag(AppSettings.Units.mmol)
                    Text("mg/dL").tag(AppSettings.Units.mgdl)
                }
                Picker("Show delta", selection: $settings.deltaDisplay) {
                    Text("Off").tag(AppSettings.DeltaDisplay.off)
                    Text("In Dropdown").tag(AppSettings.DeltaDisplay.menu)
                    Text("In Dropdown + Menu Bar").tag(AppSettings.DeltaDisplay.menuAndStatusBar)
                }
                LabeledContent("Refresh") {
                    intervalField("Every", value: $settings.pollIntervalSeconds,
                                  unit: "seconds", limits: AppSettings.pollIntervalLimits)
                }
                LabeledContent("Stale warning") {
                    intervalField("After", value: $settings.staleAfterMinutes,
                                  unit: "minutes", limits: AppSettings.staleAfterLimits)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("A reading with no successor for the stale delay is marked with ⚠ and its "
                     + "age in the menu bar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .autocorrectionDisabled()
        .task(id: [settings.baseURL, settings.token]) { await checkConnection() }
    }

    private func intervalField(_ prefix: String, value: Binding<Int>,
                               unit: String, limits: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
            TextField("", value: value, format: AppSettings.wholeNumberFormat)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
            Text(unit)
                .help("\(limits.lowerBound)–\(limits.upperBound) \(unit)")
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .unconfigured:
            Text("Not configured").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .probed(.connected):
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .probed(.failed(let message)):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // Debounced: .task(id:) restarts on every keystroke, which cancels the sleep.
    private func checkConnection() async {
        guard settings.isConfigured else { status = .unconfigured; return }
        status = .checking
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let result = await Nightscout.probe(baseURL: settings.baseURL, token: settings.token)
        guard !Task.isCancelled else { return }
        status = .probed(result)
    }

    // Masked until focused. The setter drops the mask, so a commit while unfocused can't store it.
    private var tokenText: Binding<String> {
        Binding(
            get: { tokenFieldFocused ? settings.token : AppSettings.maskedToken(settings.token) },
            set: { newValue in
                guard newValue != AppSettings.maskedToken(settings.token) else { return }
                settings.token = newValue
            }
        )
    }
}

private struct ColorsTab: View {
    @Bindable var settings: AppSettings
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
    // Deliberately not settings.rangeHours: the preview is a demo and must not move the dropdown's window.
    @State private var previewHours = 6.0
    // Pins the chart's window to the samples, which only regenerate when the body runs.
    @State private var sampleEnd = Date.now

    var body: some View {
        VStack(spacing: 0) {
            preview
            form
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupBox {
                VStack(spacing: 8) {
                    let treatments = sampleTreatments
                    // Grows by the lane like the dropdown's chart, so the lane doesn't squeeze the plot.
                    ChartCanvas(readings: sampleReadings, rangeHours: Int(previewHours),
                                settings: settings, windowEnd: sampleEnd, treatments: treatments)
                        .frame(height: 95 + ChartCanvas.laneSpace(for: treatments, settings: settings))
                    HStack(spacing: 8) {
                        TintedSlider(value: $previewHours, range: Self.previewHoursBounds, step: 2,
                                     tint: settings.sliderColor,
                                     accessibilityValueText: "\(Int(previewHours)) hours, preview only")
                            .accessibilityLabel("Preview chart range")
                        Text("\(Int(previewHours)) h")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .padding(5)
            }
            Text("Preview — sample data, not your readings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .padding([.horizontal, .top], 20)
        // Lined up with the form below, whose grouped sections stop growing at this width (measured).
        .frame(maxWidth: Self.formSectionMaxWidth + 40)
        .onAppear { sampleEnd = .now }
    }

    private static let formSectionMaxWidth: CGFloat = 704

    private static let previewHoursBounds =
        Double(AppSettings.rangeHoursLimits.lowerBound)...Double(AppSettings.rangeHoursLimits.upperBound)

    // Zone sweeps grow with the square root of the window: 72 h shows about five, not a comb of 24.
    private static let previewHoursPerCycle = 3.0

    private var previewCycles: Double {
        max(1, (previewHours / Self.previewHoursPerCycle).squareRoot())
    }

    // 5-minute spacing; anything wider exceeds ChartMath.dropoutThreshold and breaks the line.
    private var sampleReadings: [Reading] {
        ChartMath.sampleReadings(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            endingAt: sampleEnd, count: Int(previewHours) * 12 + 1,
            cycles: previewCycles
        )
    }

    // Shown or not by the Pump tab's chart switches, like the real chart.
    private var sampleTreatments: [Treatment] {
        ChartMath.sampleTreatments(endingAt: sampleEnd, span: previewHours * 3600, cycles: previewCycles)
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Preset") {
                    HStack(spacing: 8) {
                        Picker("Preset", selection: presetSelection) {
                            Text("Custom").tag(String?.none)
                            ForEach(settings.colorPresets, id: \.name) { preset in
                                Text(preset.name).tag(String?(preset.name))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Save…") {
                            newPresetName = settings.matchingPreset()?.name ?? settings.defaultPresetName()
                            showingSavePreset = true
                        }
                        Button("Delete", role: .destructive) {
                            if let name = settings.matchingPreset()?.name { settings.deleteColorPreset(named: name) }
                        }
                        .disabled(settings.matchingPreset() == nil)
                    }
                }
            }
            Section("Line") {
                // Low to high, the way the zones stack up on the chart's axis.
                swatchRow("Zones", [
                    Swatch("Very low", help: "Very low", color: $settings.extremeLowColor),
                    Swatch("Low", help: "Below the optimal range", color: $settings.belowColor),
                    Swatch("In range", help: "In the optimal range", color: $settings.inRangeColor),
                    Swatch("High", help: "Above the optimal range", color: $settings.aboveColor),
                    Swatch("Very high", help: "Very high", color: $settings.extremeHighColor),
                ])
                Toggle("Blend zone colors", isOn: $settings.blendLineColors)
                choiceRow("Shading", selection: $settings.lineShading, color: $settings.lineShadingColor,
                          customEnabled: settings.lineShading == .custom) {
                    Text("Off").tag(AppSettings.LineShading.off)
                    Text("Line color").tag(AppSettings.LineShading.lineColor)
                    Text("Custom").tag(AppSettings.LineShading.custom)
                }
            }
            Section("Latest reading dot") {
                sizeRow("Size", value: $settings.dotRadius, range: AppSettings.dotRadiusLimits)
                sizeRow("Halo", value: $settings.dotHaloRadius, range: AppSettings.dotHaloRadiusLimits)
                choiceRow("Color", selection: $settings.dotUsesZoneColor, color: $settings.dotColor,
                          customEnabled: !settings.dotUsesZoneColor) {
                    Text("Zone color").tag(true)
                    Text("Custom").tag(false)
                }
            }
            Section {
                swatchRow("Colors", [
                    Swatch("Range band", help: "The optimal range behind the line", color: $settings.bandColor),
                    Swatch("Slider", help: "The dropdown's range slider", color: $settings.sliderColor),
                ])
                // Two options, so a switch rather than a menu.
                wellRow("Background", color: $settings.chartBackgroundColor,
                        enabled: settings.chartBackgroundEnabled) {
                    // Explicit: nested in a row's content, a toggle falls back to a checkbox.
                    Toggle("Background", isOn: $settings.chartBackgroundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                swatchRow("Pump data", [
                    Swatch("Boluses", help: "Bolus bars under the chart", color: $settings.bolusColor,
                           enabled: settings.chartShowsBoluses),
                    Swatch("Delivery rate", help: "The delivery rate under the chart",
                           color: $settings.deliveryRateColor, enabled: settings.chartShowsDeliveryRate),
                    Swatch("Announcements", help: "Announcement marks along the top",
                           color: $settings.announcementColor, enabled: settings.chartShowsAnnouncements),
                ])
            } header: {
                Text("Chart")
            } footer: {
                Text("A pump color applies once its item is switched on in the Pump tab.")
                    .foregroundStyle(.secondary)
            }
            Button("Reset Colors to Default") { settings.resetColors() }
        }
        .formStyle(.grouped)
        // A sheet, not an .alert: macOS alerts render only text fields and buttons.
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet(settings: settings, name: $newPresetName)
        }
    }

    private struct Swatch: Identifiable {
        var caption: String
        var help: String
        var color: Binding<Color>
        var enabled = true
        var id: String { caption }

        init(_ caption: String, help: String, color: Binding<Color>, enabled: Bool = true) {
            self.caption = caption; self.help = help; self.color = color; self.enabled = enabled
        }
    }

    // One row of wells instead of a row per color; a common column width lines them up across rows.
    // Not LabeledContent: that pins its label to the top of a two-line row instead of centering it.
    private func swatchRow(_ label: String, _ swatches: [Swatch]) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(alignment: .top, spacing: 4) {
                ForEach(swatches) { swatch in
                    VStack(spacing: 3) {
                        ColorPicker(swatch.help, selection: swatch.color)
                            .labelsHidden()
                        Text(swatch.caption)
                            .font(.caption2)
                            .foregroundStyle(swatch.enabled ? .secondary : .tertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    // A minimum, not a width: "Announcements" is wider and must not run into its neighbor.
                    .frame(minWidth: Self.swatchWidth)
                    .disabled(!swatch.enabled)
                    .help(swatch.help)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private static let swatchWidth: CGFloat = 70

    // A mode menu plus the well it unlocks, in place of a switch row followed by a color row.
    private func choiceRow<Value: Hashable>(_ label: String, selection: Binding<Value>, color: Binding<Color>,
                                            customEnabled: Bool,
                                            @ViewBuilder options: () -> some View) -> some View {
        wellRow(label, color: color, enabled: customEnabled) {
            Picker(label, selection: selection, content: options)
                .labelsHidden()
                .fixedSize()
        }
    }

    // A control and the well it unlocks, the well in the swatch rows' last column.
    private func wellRow(_ label: String, color: Binding<Color>, enabled: Bool,
                         @ViewBuilder control: () -> some View) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                control()
                ColorPicker("\(label) color", selection: color)
                    .labelsHidden()
                    .disabled(!enabled)
                    .frame(width: Self.swatchWidth)
            }
        }
    }

    // Continuous plus rounding rather than step:, which on macOS draws a tick mark per half point.
    private func sizeRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let halfPoints = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 * 2).rounded() / 2 }
        )
        return LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: halfPoints, in: range)
                Text(String(format: "%g", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
    }

    private var presetSelection: Binding<String?> {
        Binding(
            get: { settings.matchingPreset()?.name },
            set: { name in
                guard let name, let preset = settings.colorPresets.first(where: { $0.name == name }) else { return }
                settings.apply(preset)
            }
        )
    }
}

private struct SavePresetSheet: View {
    let settings: AppSettings
    @Binding var name: String
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var overwrites: Bool { settings.colorPresets.contains { $0.name == trimmedName } }

    private var overwrittenPreset: Binding<String?> {
        Binding(
            get: { overwrites ? trimmedName : nil },
            set: { if let picked = $0 { name = picked } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save color preset").font(.headline)
            TextField("Name", text: $name)
            if !settings.colorPresets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Or overwrite an existing preset:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    List(settings.colorPresets, id: \.name, selection: overwrittenPreset) { preset in
                        Text(preset.name)
                    }
                    .listStyle(.bordered)
                    .frame(height: 120)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(overwrites ? "Overwrite" : "Save") {
                    settings.saveColorPreset(settings.currentPreset(name: trimmedName))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct GlucoseTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Optimal range") {
                thresholdField("Low", \.targetLow)
                thresholdField("High", \.targetHigh)
            }
            Section("Extreme thresholds") {
                thresholdField("Very low", \.extremeLow)
                thresholdField("Very high", \.extremeHigh)
            }
            if let warning = settings.thresholdOrderWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Until these are in order — very low ≤ low < high ≤ very high — the chart "
                         + "can't color the zones or draw the optimal range.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // Value-based: a text binding reformats on every keystroke, which makes decimals impossible to type.
    private func thresholdField(_ label: String, _ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: displayValue(keyPath), format: settings.thresholdFormat)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text(settings.units.label).foregroundStyle(.secondary)
            }
        }
    }

    private func displayValue(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings.units.display(settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = settings.units.toMgdl($0) }
        )
    }
}

private struct PumpTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Active insulin", isOn: $settings.showActiveInsulin)
                toggle("Mode", detail: "Auto mode, Boost or Ease-off", isOn: $settings.showPumpMode)
                toggle("Delivery rate", detail: "What the pump delivers right now", isOn: $settings.showDeliveryRate)
                Toggle("Reservoir", isOn: $settings.showReservoir)
                Toggle("Pump battery", isOn: $settings.showPumpBattery)
                toggle("Time since change", detail: "Next to the reservoir and the battery",
                       isOn: $settings.showChangeAge)
                    .disabled(!settings.showReservoir && !settings.showPumpBattery)
                toggle("Total insulin", detail: "Today and yesterday", isOn: $settings.showDailyInsulin)
                toggle("Average glucose", detail: "Today and yesterday", isOn: $settings.showAverageGlucose)
            } header: {
                Text("Dropdown")
            } footer: {
                Text("Each item appears only if your Nightscout site reports it, through the "
                     + "device status a pump or loop uploader sends. Mode, delivery rate and the "
                     + "daily figures are CamAPS FX values, which only some uploaders pass on.")
                    .foregroundStyle(.secondary)
            }
            Section {
                toggle("Boluses", detail: "As bars under the chart", isOn: $settings.chartShowsBoluses)
                toggle("Delivery rate", detail: "As an area under the chart", isOn: $settings.chartShowsDeliveryRate)
                toggle("Announcements", detail: "Marks along the top, e.g. pump and sensor alerts",
                       isOn: $settings.chartShowsAnnouncements)
            } header: {
                Text("Chart")
            } footer: {
                Text("Hover the chart for the amounts and the announcement texts. Pump data is "
                     + "fetched when the dropdown opens, never in the background.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }
}

// A tab because an LSUIElement app has no app menu to hold the standard About item.
private struct AboutTab: View {
    let settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                LabeledContent("Project") {
                    Link(AppInfo.repositoryLabel, destination: AppInfo.repositoryURL)
                }
                LabeledContent("Report an issue") {
                    Link("GitHub Issues", destination: AppInfo.issuesURL)
                }
                LabeledContent("License") {
                    Link("MIT", destination: AppInfo.licenseURL)
                }
            } header: {
                header
            }
            Section {
                Label {
                    Text("Sugarglider only displays what your Nightscout site reports. It is not a "
                         + "medical device and raises no alarms — don't rely on it to catch a high, "
                         + "a low, or a stopped feed, and don't use it for treatment decisions.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        VStack(spacing: 2) {
            // Theme first, so a Light/Dark override wins over the system appearance.
            if let icon = AppInfo.appIcon(for: settings.theme.colorScheme ?? colorScheme) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .padding(.bottom, 4)
            }
            Text("Sugarglider")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(AppInfo.versionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }
}

enum AppInfo {
    static let repositoryLabel = "nvmddev/sugarglider"
    static let repositoryURL = URL(string: "https://github.com/nvmddev/sugarglider")!
    static let issuesURL = repositoryURL.appending(path: "issues")
    static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")

    // Asked by name, AppKit returns the light rendition from Assets.car in either appearance, hence the PNGs.
    static func appIcon(for scheme: ColorScheme) -> NSImage? {
        NSImage(named: scheme == .dark ? "AppIcon-Dark" : "AppIcon-Light")
            ?? NSImage(named: NSImage.applicationIconName)
    }

    static var versionText: String {
        versionText(short: bundleString("CFBundleShortVersionString"),
                    build: bundleString("CFBundleVersion"))
    }

    static func versionText(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return "Development build" }
        guard let build, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    static var copyright: String {
        bundleString("NSHumanReadableCopyright") ?? "© 2026 nevermind.dev"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
