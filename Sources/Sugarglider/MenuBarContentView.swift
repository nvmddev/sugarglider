import SwiftUI

struct MenuBarContentView: View {
    var settings: AppSettings
    var store: ReadingStore
    @Environment(\.openSettings) private var openSettings

    private let contentWidth: CGFloat = 280
    private static let spacing: CGFloat = 10
    /// The button row sits as far above the bottom edge as below the divider, so it reads centered between them.
    static let insets = EdgeInsets(top: 18, leading: 18, bottom: spacing, trailing: 18)
    private static let rangeSliderBounds =
        Double(AppSettings.rangeHoursLimits.lowerBound)...Double(AppSettings.rangeHoursLimits.upperBound)

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ChartCanvas(readings: store.readings, rangeHours: settings.rangeHours, settings: settings,
                        windowEnd: store.now, treatments: store.treatments)
                .frame(height: 135 + ChartCanvas.laneSpace(for: store.treatments, settings: settings))

            HStack(spacing: 8) {
                TintedSlider(value: rangeBinding, range: Self.rangeSliderBounds, step: 1,
                             tint: settings.sliderColor,
                             accessibilityValueText: "\(settings.rangeHours) hours")
                    .accessibilityLabel("Chart range")
                Text("\(settings.rangeHours) h")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
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
        .padding(Self.insets)
        .dropdownBackground(settings.dropdownBackground)
        .onAppear {
            store.refreshHistory(force: false)
            store.refreshDetails(force: false)
        }
        .windowTheme(settings.theme)
        .windowShowsToolTipsWhenInactive()
    }

    // Not .glass: the panel is glass already, and Apple advises against glass on glass.
    private var actionButtons: some View {
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
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private func actionButton(_ title: String, systemImage: String, shortcut: KeyEquivalent,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // A circle sizes to its label, so only equal squares give equal circles.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 18, height: 18)
        }
        .keyboardShortcut(shortcut)
        .help(title)
    }

    private var rangeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.rangeHours) },
            set: { settings.rangeHours = Int($0) }
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
        // LOW and HIGH have no value to put a unit to, and no delta: they say where the sensor ran out instead.
        let text = reading.text(in: settings.units)
        let value = Text(reading.outOfRange == nil ? "\(text) \(settings.units.label)" : text)
            .font(.system(size: 15, weight: .medium))
        let arrow = reading.trendArrow.isEmpty
            ? Text("")
            : Text(" \(reading.trendArrow)").font(.system(size: 17, weight: .semibold))
        let note: String? = switch reading.outOfRange {
        case .low: "below the sensor's range"
        case .high: "above the sensor's range"
        case nil: store.deltaText().map { "(\($0))" }
        }
        let detail = note.map { Text("  \($0)").font(.system(size: 13)).foregroundStyle(.secondary) }
        return Text("\(value)\(arrow)\(detail ?? Text(""))")
    }

    private var ageText: String {
        guard settings.isConfigured else { return "Open Settings to add your Nightscout URL" }
        guard let reading = store.lastReading else { return store.lastError ?? "" }
        var text = "Reading from \(reading.date.relative(to: store.now))"
        if store.isStale { text += " (stale)" }
        if let error = store.lastError { text += " — \(error)" }
        return text
    }
}
