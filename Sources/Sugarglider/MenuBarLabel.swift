import SwiftUI

struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    // MenuBarExtra turns the label into a plain status item title in the system font, so no Text
    // styling would reach the menu bar.
    var body: some View {
        Text(title)
            .accessibilityLabel(spokenTitle)
    }

    var title: String { text(trend: { " \($0.arrow)" }, ageWidth: .narrow) }

    var spokenTitle: String { text(trend: { ", \($0.spokenName)" }, ageWidth: .wide) }

    private func text(trend: (Reading.Direction) -> String,
                      ageWidth: Duration.UnitsFormatStyle.UnitWidth) -> String {
        guard settings.isConfigured else { return "CGM ⚙" }
        guard let reading = store.lastReading else { return store.lastError == nil ? "CGM …" : "CGM ⚠" }
        let arrow = reading.direction.map(trend) ?? ""
        let delta = settings.deltaDisplay == .dropdownAndStatusBar ? store.deltaText().map { "  (\($0))" } : nil
        // The age stays narrow in the title; VoiceOver spells the letters of the narrow units.
        let age = store.isStale ? " ⚠ \(reading.date.age(at: store.now, width: ageWidth))" : ""
        return "\(reading.text(in: settings.units))\(arrow)\(delta ?? "")\(age)"
    }
}
