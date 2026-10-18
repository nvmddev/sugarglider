import SwiftUI

struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    var body: some View {
        title.font(.system(size: 13, design: .monospaced))
    }

    private var title: Text {
        guard settings.isConfigured else { return Text("CGM ⚙") }
        guard let reading = store.lastReading else {
            return Text(store.lastError == nil ? "CGM …" : "CGM ⚠")
        }
        let arrow = reading.trendArrow.isEmpty
            ? Text("")
            : Text(" \(reading.trendArrow)").font(.system(size: 15, weight: .medium))
        let delta = settings.deltaDisplay == .menuAndStatusBar ? store.deltaText().map { "  (\($0))" } : nil
        // The age is the only escalation, by design: the app can't tell a sensor gap from a
        // network one, so it never notifies.
        let age = store.isStale ? " ⚠ \(ReadingStore.compactAge(reading.date))" : ""
        return Text("\(reading.text(in: settings.units))\(arrow)\(delta ?? "")\(age)")
    }
}
