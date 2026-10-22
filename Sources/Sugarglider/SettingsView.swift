import SwiftUI

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(settings: settings) }
            Tab("Colors", systemImage: "paintpalette") { ColorsTab(settings: settings) }
            Tab("Glucose", systemImage: "drop") { GlucoseTab(settings: settings) }
            Tab("Pump", systemImage: "syringe") { PumpTab(settings: settings) }
            Tab("About", systemImage: "info.circle") { AboutTab() }
        }
        // Every tab is a .grouped Form, which scrolls where a plain one would clip.
        .frame(width: 520, height: 640)
    }
}
