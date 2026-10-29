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

    func title(locale: Locale = .autoupdatingCurrent) -> String {
        text(trend: { " \($0.arrow)" }, ageWidth: .narrow, locale: locale)
    }

    var title: String { title() }

    func spokenTitle(locale: Locale = .autoupdatingCurrent) -> String {
        text(trend: { ", \($0.spokenName)" }, ageWidth: .wide, locale: locale)
    }

    var spokenTitle: String { spokenTitle() }

    private func text(trend: (Reading.Direction) -> String,
                      ageWidth: Duration.UnitsFormatStyle.UnitWidth,
                      locale: Locale) -> String {
        guard settings.isConfigured else { return "CGM ⚙" }
        guard let reading = store.lastReading else { return store.lastError == nil ? "CGM …" : "CGM ⚠" }
        let arrow = reading.direction.map(trend) ?? ""
        let delta = settings.deltaDisplay == .dropdownAndStatusBar
            ? store.deltaText(locale: locale).map { "  (\($0))" } : nil
        // The age stays narrow in the title; VoiceOver spells the letters of the narrow units.
        let age = store.isStale ? " ⚠ \(reading.date.age(at: store.now, width: ageWidth, locale: locale))" : ""
        return "\(reading.text(in: settings.units, locale: locale))\(arrow)\(delta ?? "")\(age)"
    }
}
