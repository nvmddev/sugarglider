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
            GlucoseChart(readings: store.readings, rangeHours: settings.rangeHours, settings: settings,
                        windowEnd: store.now, treatments: store.treatments)
                .frame(height: 135 + GlucoseChart.laneSpace(for: store.treatments, settings: settings))

            HStack(spacing: 8) {
                // Steps by the hour without drawing a tick for each.
                Slider(value: rangeBinding, in: Self.rangeSliderBounds, step: 1,
                       label: { Text("Chart range") }, tick: { _ in nil })
                    .labelsHidden()
                    .tint(settings.sliderColor)
                    .accessibilityValue("\(settings.rangeHours) hours")
                Text("\(settings.rangeHours) h")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                readingLine
                ageText.font(.subheadline).foregroundStyle(.secondary)
            }

            // No modifiers: without pump data this renders nothing, but a wrapper would still take a gap.
            PumpDetailsView(settings: settings, store: store)

            Divider()

            actionButtons
        }
        .frame(width: contentWidth)
        .padding(Self.insets)
        .dropdownBackground(settings.dropdownBackground)
        .task { await store.refreshHistory(force: false) }
        .task { await store.refreshDetails(force: false) }
        .windowTheme(settings.theme)
        .windowShowsToolTipsWhenInactive()
    }

    // Not .glass: the panel is glass already, and Apple advises against glass on glass.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            actionButton("Refresh", systemImage: "arrow.clockwise", shortcut: "r") {
                Task { await store.refresh() }
                Task { await store.refreshHistory(force: true) }
                Task { await store.refreshDetails(force: true) }
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
            Text("Not configured").foregroundStyle(.secondary)
        } else if let reading = store.lastReading {
            readingText(reading)
        } else {
            Text(store.lastError == nil ? "Loading…" : "No reading yet").foregroundStyle(.secondary)
        }
    }

    private func readingText(_ reading: Reading) -> Text {
        // LOW and HIGH have no value to put a unit to, and no delta: they say where the sensor ran out instead.
        let text = reading.text(in: settings.units)
        let value = Text(verbatim: reading.outOfRange == nil ? "\(text) \(settings.units.label)" : text)
            .font(.title3.weight(.medium))
        let arrow = reading.direction.map { Text(verbatim: " \($0.arrow)").font(.title2.weight(.semibold)) }
            ?? Text(verbatim: "")
        let note: Text? = switch reading.outOfRange {
        case .low: Text("below the sensor's range")
        case .high: Text("above the sensor's range")
        case nil: store.deltaText().map { Text(verbatim: "(\($0))") }
        }
        let detail = note.map { Text("  \($0.foregroundStyle(.secondary))") } ?? Text(verbatim: "")
        return Text("\(value)\(arrow)\(detail)")
    }

    private var ageText: Text {
        guard settings.isConfigured else { return Text("Open Settings to add your Nightscout URL") }
        guard let reading = store.lastReading else { return Text(store.lastError ?? "") }
        let age = reading.date.relative(to: store.now)
        let line = store.isStale ? Text("Reading from \(age) (stale)") : Text("Reading from \(age)")
        guard let error = store.lastError else { return line }
        return Text("\(line) — \(error)")
    }
}
