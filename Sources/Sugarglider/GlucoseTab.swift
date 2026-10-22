import SwiftUI

struct GlucoseTab: View {
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
                    Text("""
                        Until these are in order (very low ≤ low < high ≤ very high), the chart \
                        can't color the zones or draw the optimal range.
                        """)
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
            get: { settings.units.value(fromMgdl: settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = settings.units.mgdl(from: $0) }
        )
    }
}
