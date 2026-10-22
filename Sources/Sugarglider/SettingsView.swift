import SwiftUI

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(settings: settings) }
            Tab("Colors", systemImage: "paintpalette") { ColorsTab(settings: settings) }
            Tab("Glucose", systemImage: "drop") { GlucoseTab(settings: settings) }
            Tab("Pump", systemImage: "syringe") { PumpTab(settings: settings) }
            Tab("About", systemImage: "info.circle") { AboutTab(settings: settings) }
        }
        // Every tab is a .grouped Form, which scrolls where a plain one would clip.
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .windowResizable(defaultSize: CGSize(width: 500, height: 700), autosaveName: "SettingsWindow")
        // Not .windowTheme(_:): SwiftUI resets a manual NSWindow.appearance on this window within milliseconds.
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
