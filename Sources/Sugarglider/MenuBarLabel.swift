import SwiftUI

struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    // MenuBarExtra turns the label into a plain status item title in the system font, so no Text
    // styling would reach the menu bar.
    var body: some View {
        Text(title)
    }

    private var title: String {
        guard settings.isConfigured else { return "CGM ⚙" }
        guard let reading = store.lastReading else { return store.lastError == nil ? "CGM …" : "CGM ⚠" }
        let arrow = reading.trendArrow.isEmpty ? "" : " \(reading.trendArrow)"
        let delta = settings.deltaDisplay == .menuAndStatusBar ? store.deltaText().map { "  (\($0))" } : nil
        // The age is the only escalation, by design: the app can't tell a sensor gap from a
        // network one, so it never notifies.
        let age = store.isStale ? " ⚠ \(ReadingStore.compactAge(reading.date, now: store.now))" : ""
        return "\(reading.text(in: settings.units))\(arrow)\(delta ?? "")\(age)"
    }
}
