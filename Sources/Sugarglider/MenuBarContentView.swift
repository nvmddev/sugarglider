import SwiftUI

struct MenuBarContentView: View {
    var settings: AppSettings
    var store: ReadingStore
    @Environment(\.openSettings) private var openSettings
    @FocusState private var rangeFieldFocused: Bool
    @State private var rangeFieldEditing = false

    private let contentWidth: CGFloat = 280
    private static let rangeSliderBounds =
        Double(AppSettings.rangeHoursLimits.lowerBound)...Double(AppSettings.rangeHoursLimits.upperBound)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartCanvas(readings: store.readings, rangeHours: settings.rangeHours, settings: settings,
                        treatments: store.treatments)
                .frame(height: 160 + ChartCanvas.laneSpace(for: store.treatments, settings: settings))

            HStack(spacing: 6) {
                TintedSlider(value: rangeBinding, range: Self.rangeSliderBounds, step: 2,
                             tint: settings.sliderColor,
                             accessibilityValueText: "\(settings.rangeHours) hours")
                    .accessibilityLabel("Chart range")
                rangeField
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                readingLine
                Text(ageText).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            // No modifiers: without pump data this renders nothing, but a wrapper would still take a gap.
            PumpDetailsView(settings: settings, store: store, width: contentWidth)

            Divider()

            actionButtons
        }
        .frame(width: contentWidth)
        .padding(18)
        .background(defocusBackdrop)
        .onAppear {
            store.refreshHistory(force: false)
            store.refreshDetails(force: false)
        }
        .windowTheme(settings.theme)
    }

    // The panel has nothing else focusable, so clicking anywhere must release the hours field. A background,
    // because an overlay or a gesture on the stack competes with the slider drag and the buttons.
    private var defocusBackdrop: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { endRangeEditing() }
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                actionButton("Refresh", systemImage: "arrow.clockwise", shortcut: "r") {
                    store.refresh()
                    store.refreshHistory(force: true)
                    store.refreshDetails(force: true)
                }
                actionButton("Settings…", systemImage: "gearshape", shortcut: ",") { showSettings() }
                Spacer()
                actionButton("Quit", systemImage: "power", shortcut: "q") { NSApp.terminate(nil) }
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private func actionButton(_ title: String, systemImage: String, shortcut: KeyEquivalent,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // A glass circle sizes to its label, so only equal squares give equal circles.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 18, height: 18)
        }
        .keyboardShortcut(shortcut)
        .help(title)
    }

    // A click-to-edit cell, not a live TextField: the MenuBarExtra panel focuses the first focusable control
    // as it opens, which lit the field up every time. Both states share one bezel so nothing jumps.
    private var rangeField: some View {
        HStack(spacing: 3) {
            ZStack {
                let bezel = RoundedRectangle(cornerRadius: 5, style: .continuous)
                bezel.fill(Color(nsColor: .textBackgroundColor))
                bezel.strokeBorder(rangeFieldEditing ? Color.accentColor : Color(nsColor: .separatorColor),
                                   lineWidth: rangeFieldEditing ? 1.5 : 1)
                if rangeFieldEditing {
                    TextField("Chart range", value: Bindable(settings).rangeHours,
                              format: AppSettings.wholeNumberFormat)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .font(rangeFont)
                        .padding(.trailing, 5)
                        .accessibilityLabel("Chart range in hours")
                        .focused($rangeFieldFocused)
                        .onAppear { rangeFieldFocused = true }
                        .onSubmit { endRangeEditing() }
                        .onExitCommand { endRangeEditing() }
                        .onChange(of: rangeFieldFocused) { _, focused in
                            if !focused { rangeFieldEditing = false }
                        }
                } else {
                    // Tap on the inert Text, not the ZStack, where it would steal the live field's clicks.
                    Text("\(settings.rangeHours)")
                        .font(rangeFont)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 5)
                        .contentShape(Rectangle())
                        .onTapGesture { rangeFieldEditing = true }
                        .accessibilityElement()
                        .accessibilityLabel("Chart range in hours")
                        .accessibilityValue("\(settings.rangeHours)")
                        .accessibilityHint("Click to type an exact number of hours")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { rangeFieldEditing = true }
                }
            }
            .frame(width: 32, height: 20)
            Text("h")
                .font(rangeFont)
                .foregroundStyle(.secondary)
        }
    }

    private var rangeFont: Font { .system(size: 11, design: .monospaced) }

    // Not left to the focus change: if the field never took focus, none fires and the cell stays editable.
    private func endRangeEditing() {
        rangeFieldFocused = false
        rangeFieldEditing = false
    }

    // Ends editing first: a focused TextField(value:) would go on showing its own half-typed buffer.
    private var rangeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.rangeHours) },
            set: { newValue in
                if rangeFieldEditing { endRangeEditing() }
                settings.rangeHours = Int(newValue)
            }
        )
    }

    // An accessory app's window that is only ordered front ignores typing, so Settings has to become key.
    // SwiftUI creates the window asynchronously, hence the poll.
    private func showSettings() {
        NSApp.activate()
        openSettings()
        Task {
            for _ in 0..<20 {
                if let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue.hasPrefix("com_apple_SwiftUI_Settings") == true
                }) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    @ViewBuilder private var readingLine: some View {
        if !settings.isConfigured {
            statusText("Not configured")
        } else if let reading = store.lastReading {
            readingText(reading)
        } else {
            statusText(store.lastError == nil ? "Loading…" : "No reading yet")
        }
    }

    private func statusText(_ text: String) -> Text {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
    }

    private func readingText(_ reading: Reading) -> Text {
        let value = Text("\(reading.text(in: settings.units)) \(settings.units.label)")
            .font(.system(size: 15, weight: .medium))
        let arrow = reading.trendArrow.isEmpty
            ? Text("")
            : Text(" \(reading.trendArrow)").font(.system(size: 17, weight: .semibold))
        let delta = store.deltaText().map {
            Text("  (\($0))").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        return Text("\(value)\(arrow)\(delta ?? Text(""))")
    }

    private var ageText: String {
        guard settings.isConfigured else { return "Open Settings to add your Nightscout URL" }
        guard let reading = store.lastReading else { return store.lastError ?? "" }
        var text = "Reading \(ReadingStore.relative(reading.date))"
        if store.isStale { text += " (stale)" }
        if let error = store.lastError { text += " — \(error)" }
        return text
    }
}
