import SwiftUI

/// The dropdown behind the status-bar item: chart, range slider, the current
/// reading, and the action buttons.
struct MenuBarContentView: View {
    var settings: AppSettings
    var store: ReadingStore
    @Environment(\.openSettings) private var openSettings
    /// Tracked so the hours field can be unfocused deliberately, see
    /// `defocusBackdrop`.
    @FocusState private var rangeFieldFocused: Bool
    /// Whether the hours cell currently hosts a live `TextField`, see
    /// `rangeField`.
    @State private var rangeFieldEditing = false

    private let contentWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartCanvas(readings: store.readings, rangeHours: settings.rangeHours, settings: settings)
                .frame(width: contentWidth, height: 160)

            HStack(spacing: 6) {
                // Not SwiftUI's Slider: its track ignores every tint mechanism
                // macOS offers. See TintedSlider.
                TintedSlider(value: rangeBinding, range: rangeSliderBounds, step: 2,
                             tint: settings.sliderColor,
                             accessibilityValueText: "\(settings.rangeHours) hours")
                    .accessibilityLabel("Chart range")
                rangeField
            }
            .frame(width: contentWidth)

            Divider().frame(width: contentWidth)

            VStack(alignment: .leading, spacing: 2) {
                readingRow
                Text(ageText).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Divider().frame(width: contentWidth)

            HStack(spacing: 8) {
                iconButton("arrow.clockwise", label: "Refresh", shortcut: "r") {
                    store.refresh()
                    store.refreshHistory(force: true)
                }
                iconButton("gearshape", label: "Settings…", shortcut: ",") { showSettings() }
                Spacer()
                iconButton("power", label: "Quit", shortcut: "q") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
            .frame(width: contentWidth)
        }
        .padding(18)
        .background(defocusBackdrop)
        .onAppear { store.refreshHistory(force: false) }
        .windowTheme(settings.theme)
    }

    /// A click-catching layer behind the content that drops the hours field's
    /// focus. The dropdown holds exactly one focusable control, so without this
    /// the field keeps first responder for as long as the panel is open: there
    /// is nothing else to focus by clicking elsewhere. It has to be a
    /// `background` rather than an overlay or a gesture on the `VStack`, or it
    /// competes with the slider's drag and the buttons.
    private var defocusBackdrop: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { endRangeEditing() }
    }

    /// Symbol only, so the label survives as the tooltip and the accessibility
    /// name.
    private func iconButton(_ symbol: String, label: String, shortcut: KeyEquivalent,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .keyboardShortcut(shortcut)
        .help(label)
        .accessibilityLabel(label)
    }

    /// The chart range as a typed number, so any whole hour is reachable; the
    /// slider next to it steps by 2. Value-based rather than text-based so it
    /// commits on Return or focus loss instead of reformatting mid-typing.
    /// Out-of-range input needs no validation, `rangeHours` clamps it.
    ///
    /// This is a click-to-edit cell rather than a live `TextField` because
    /// `MenuBarExtra`'s panel hands its initial focus to the first focusable
    /// control it finds, and a real field here lit up the moment the dropdown
    /// opened. Swapping the field in only once it's clicked leaves that focus
    /// pass nothing to land on. Both states share one hand-drawn frame and
    /// bezel so nothing jumps; the accent border stands in for the focus ring
    /// `.plain` doesn't draw.
    private var rangeField: some View {
        HStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(rangeFieldEditing ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: rangeFieldEditing ? 1.5 : 1)
                if rangeFieldEditing {
                    TextField("Chart range", value: hoursBinding, format: AppSettings.wholeNumberFormat)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .font(rangeFont)
                        .padding(.trailing, 4)
                        .accessibilityLabel("Chart range in hours")
                        .focused($rangeFieldFocused)
                        // Only in the tree while editing, so it can take the
                        // focus itself.
                        .onAppear { rangeFieldFocused = true }
                        // So the keyboard alone can get back out of the field.
                        .onSubmit { endRangeEditing() }
                        .onExitCommand { endRangeEditing() }
                        // Covers a focus loss this view didn't initiate.
                        .onChange(of: rangeFieldFocused) { _, focused in
                            if !focused { rangeFieldEditing = false }
                        }
                } else {
                    // The tap goes on the inert Text, never on the ZStack: it
                    // would otherwise compete with the live field's own click
                    // handling and stop the caret being placed.
                    Text("\(settings.rangeHours)")
                        .font(rangeFont)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
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
            .frame(width: 30, height: 18)
            Text("h")
                .font(rangeFont)
                .foregroundStyle(.secondary)
        }
    }

    private var rangeFont: Font { .system(size: 11, design: .monospaced) }

    /// Leaves the editing state without relying on the focus transition: if the
    /// field never took focus, no `onChange` fires and the cell would stay stuck
    /// looking editable.
    private func endRangeEditing() {
        rangeFieldFocused = false
        rangeFieldEditing = false
    }

    /// Moving the slider also ends editing: a focused `TextField(value:)` keeps
    /// its own buffer and would go on showing the half-typed number while the
    /// slider moved the real value underneath it.
    private var rangeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.rangeHours) },
            set: { newValue in
                if rangeFieldEditing { endRangeEditing() }
                settings.rangeHours = Int(newValue)
            }
        )
    }

    private var hoursBinding: Binding<Int> {
        Binding(get: { settings.rangeHours }, set: { settings.rangeHours = $0 })
    }

    private var rangeSliderBounds: ClosedRange<Double> {
        Double(AppSettings.rangeHoursLimits.lowerBound)...Double(AppSettings.rangeHoursLimits.upperBound)
    }

    /// Opens Settings in front *and key*. An accessory (LSUIElement) app is
    /// normally inactive, and a window merely ordered front without key status
    /// silently ignores all typing: mouse-driven controls work, text fields
    /// never take focus. The window is created asynchronously, hence the poll.
    private func showSettings() {
        NSApp.activate()
        openSettings()
        Task { @MainActor in
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

    @ViewBuilder private var readingRow: some View {
        if !settings.isConfigured {
            Text("Not configured").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if let r = store.lastReading {
            (valueText(r) + arrowText(r) + deltaText)
        } else if store.lastError != nil {
            Text("No reading yet").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            Text("Loading…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func valueText(_ r: Reading) -> Text {
        Text("\(r.text(in: settings.units)) \(settings.units.label)")
            .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
    }

    private func arrowText(_ r: Reading) -> Text {
        guard !r.trendArrow.isEmpty else { return Text("") }
        return Text(" \(r.trendArrow)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
    }

    private var deltaText: Text {
        guard let delta = store.deltaText() else { return Text("") }
        return Text("  (\(delta))").font(.system(size: 13)).foregroundStyle(.secondary)
    }

    private var ageText: String {
        guard settings.isConfigured else { return "Open Settings to add your Nightscout URL" }
        if let r = store.lastReading {
            var age = "Reading \(ReadingStore.relative(r.date))" + (store.isStale ? " (stale)" : "")
            if let err = store.lastError { age += " — \(err)" }
            return age
        } else if let err = store.lastError {
            return err
        }
        return ""
    }
}
