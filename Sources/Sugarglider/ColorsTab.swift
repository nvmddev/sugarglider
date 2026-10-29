import SwiftUI

struct ColorsTab: View {
    @Bindable var settings: AppSettings
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
    // Deliberately not settings.rangeHours: the preview is a demo and must not move the dropdown's window.
    @State private var previewHours = 6
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
                    let hours = Duration.seconds(Double(previewHours) * 3600)
                    // Grows by the lane like the dropdown's chart, so the lane doesn't squeeze the plot.
                    GlucoseChart(readings: sampleReadings, rangeHours: previewHours,
                                settings: settings, windowEnd: sampleEnd, treatments: treatments,
                                accessibilityTitle: "Glucose, sample data")
                        .frame(height: 95 + GlucoseChart.laneSpace(for: treatments, settings: settings))
                    HStack(spacing: 8) {
                        Slider(value: $previewHours.sliderValue, in: Self.previewHoursBounds) {
                            Text("Preview chart range")
                        }
                        .labelsHidden()
                        .tint(settings.sliderColor)
                        .accessibilityValue(Text("\(hours.formatted(.units(allowed: [.hours], width: .wide))) · \(String(localized: "preview only"))"))
                        Text(hours.formatted(.units(allowed: [.hours], width: .narrow)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .padding(5)
            }
            Text("Preview with sample data, not your readings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .padding([.horizontal, .top], 20)
        .onAppear { sampleEnd = .now }
    }

    private static let previewHoursBounds =
        Double(AppSettings.rangeHoursLimits.lowerBound)...Double(AppSettings.rangeHoursLimits.upperBound)

    // Zone sweeps grow with the square root of the window: 72 h shows about five, not a comb of 24.
    private static let previewHoursPerCycle = 3.0

    private var previewCycles: Double {
        max(1, (Double(previewHours) / Self.previewHoursPerCycle).squareRoot())
    }

    // 5-minute spacing; anything wider exceeds ChartMath.dropoutThreshold and breaks the line.
    private var sampleReadings: [Reading] {
        ChartMath.sampleReadings(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            endingAt: sampleEnd, count: previewHours * 12 + 1,
            cycles: previewCycles
        )
    }

    // Shown or not by the Pump tab's chart switches, like the real chart.
    private var sampleTreatments: [Treatment] {
        ChartMath.sampleTreatments(endingAt: sampleEnd, span: Double(previewHours) * 3600, cycles: previewCycles)
    }

    private var form: some View {
        let match = settings.matchingPreset()
        return Form {
            Section {
                LabeledContent("Preset") {
                    HStack(spacing: 8) {
                        Picker("Preset", selection: presetSelection(match)) {
                            Text("Custom").tag(String?.none)
                            ForEach(settings.colorPresets, id: \.name) { preset in
                                Text(preset.name).tag(String?(preset.name))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Save…") {
                            newPresetName = match?.name ?? settings.defaultPresetName()
                            showingSavePreset = true
                        }
                        Button("Delete", role: .destructive) {
                            if let match { settings.deleteColorPreset(named: match.name) }
                        }
                        .disabled(match == nil)
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
                choiceRow("Color", wellLabel: "Dot color", selection: $settings.dotUsesZoneColor,
                          color: $settings.dotColor, customEnabled: !settings.dotUsesZoneColor) {
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
                // Top of the chart to bottom; also keeps the widest caption away from the trailing edge.
                swatchRow("Pump data", [
                    Swatch("Announcements", help: "Announcement marks along the top",
                           color: $settings.announcementColor, enabled: settings.chartShowsAnnouncements),
                    Swatch("Delivery rate", help: "The delivery rate under the chart",
                           color: $settings.deliveryRateColor, enabled: settings.chartShowsDeliveryRate),
                    Swatch("Boluses", help: "Bolus bars under the chart", color: $settings.bolusColor,
                           enabled: settings.chartShowsBoluses),
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

    private struct Swatch {
        var caption: LocalizedStringKey
        var help: LocalizedStringKey
        var color: Binding<Color>
        var enabled = true

        init(_ caption: LocalizedStringKey, help: LocalizedStringKey, color: Binding<Color>, enabled: Bool = true) {
            self.caption = caption; self.help = help; self.color = color; self.enabled = enabled
        }
    }

    // An HStack, not LabeledContent: that pins its label to the top of a two-line row instead of centering it.
    private func swatchRow(_ label: LocalizedStringKey, _ swatches: [Swatch]) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(alignment: .top, spacing: Self.swatchSpacing) {
                // A fixed list, so its positions are its identities.
                ForEach(swatches.indices, id: \.self) { index in
                    let swatch = swatches[index]
                    VStack(spacing: 3) {
                        ColorPicker(swatch.help, selection: swatch.color)
                            .labelsHidden()
                        // Zero-width, so the column is as wide as the well and the last well ends flush
                        // with the row like every other control; the caption overhangs it, centered.
                        Text(swatch.caption)
                            .font(.caption2)
                            .foregroundStyle(swatch.enabled ? .secondary : .tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: 0)
                    }
                    .disabled(!swatch.enabled)
                    .help(swatch.help)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // Room for two neighboring captions' overhang ("Announcements" next to "Delivery rate").
    private static let swatchSpacing: CGFloat = 34

    // A mode menu plus the well it unlocks.
    private func choiceRow<Value: Hashable>(_ label: LocalizedStringKey, wellLabel: LocalizedStringKey? = nil,
                                            selection: Binding<Value>, color: Binding<Color>,
                                            customEnabled: Bool,
                                            @ViewBuilder options: () -> some View) -> some View {
        wellRow(label, wellLabel: wellLabel, color: color, enabled: customEnabled) {
            Picker(label, selection: selection, content: options)
                .labelsHidden()
                .fixedSize()
        }
    }

    // A control and the well it unlocks, flush with the trailing edge like the swatch rows' last well.
    private func wellRow(_ label: LocalizedStringKey, wellLabel: LocalizedStringKey? = nil,
                         color: Binding<Color>, enabled: Bool,
                         @ViewBuilder control: () -> some View) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                control()
                ColorPicker(wellLabel ?? "\(Text(label)) color", selection: color)
                    .labelsHidden()
                    .disabled(!enabled)
            }
        }
    }

    // Continuous plus rounding rather than step:, which on macOS draws a tick mark per half point.
    private func sizeRow(_ label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let halfPoints = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 * 2).rounded() / 2 }
        )
        return LabeledContent(label) {
            HStack(spacing: 8) {
                // The label is hidden visually but stays the control's name for VoiceOver.
                Slider(value: halfPoints, in: range) { Text(label) }
                    .labelsHidden()
                Text(value.wrappedValue.formatted())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
    }

    private func presetSelection(_ match: AppSettings.ColorPreset?) -> Binding<String?> {
        Binding(
            get: { match?.name },
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
