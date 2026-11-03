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
        text(spoken: false, locale: locale)
    }

    var title: String { title() }

    /// Words where the title draws symbols: VoiceOver would read "gear" and "warning sign".
    func spokenTitle(locale: Locale = .autoupdatingCurrent) -> String {
        text(spoken: true, locale: locale)
    }

    var spokenTitle: String { spokenTitle() }

    private func text(spoken: Bool, locale: Locale) -> String {
        guard settings.isConfigured else {
            return spoken ? String(localized: "CGM, not set up", locale: locale) : "CGM ⚙"
        }
        guard let reading = store.lastReading else {
            if store.lastError == nil { return spoken ? String(localized: "CGM, loading", locale: locale) : "CGM …" }
            return spoken ? String(localized: "CGM, no reading", locale: locale) : "CGM ⚠"
        }
        let arrow = reading.direction.map { spoken ? ", \($0.spokenName)" : " \($0.arrow)" } ?? ""
        let delta = settings.deltaDisplay == .dropdownAndStatusBar
            ? store.deltaText(locale: locale).map { "  (\($0))" } : nil
        var age = ""
        if store.isStale {
            // The age stays narrow in the title; VoiceOver spells the letters of the narrow units.
            age = spoken ? String(localized: ", stale, \(reading.date.relative(to: store.now, locale: locale))", locale: locale)
                : " ⚠ \(reading.date.age(at: store.now, locale: locale))"
        }
        return "\(reading.text(in: settings.units, locale: locale))\(arrow)\(delta ?? "")\(age)"
    }
}
