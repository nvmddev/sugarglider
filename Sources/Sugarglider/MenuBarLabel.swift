import SwiftUI

struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    // MenuBarExtra turns the label into a plain status item title in the system font, so no Text
    // styling would reach the menu bar.
    var body: some View {
        Text(title)
    }

    var title: String {
        guard settings.isConfigured else { return "CGM ⚙" }
        guard let reading = store.lastReading else { return store.lastError == nil ? "CGM …" : "CGM ⚠" }
        let arrow = reading.direction.map { " \($0.arrow)" } ?? ""
        let delta = settings.deltaDisplay == .menuAndStatusBar ? store.deltaText().map { "  (\($0))" } : nil
        let age = store.isStale ? " ⚠ \(reading.date.age(at: store.now))" : ""
        return "\(reading.text(in: settings.units))\(arrow)\(delta ?? "")\(age)"
    }
}
