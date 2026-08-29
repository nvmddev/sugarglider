import SwiftUI

@main
struct SugargliderApp: App {
    @State private var settings: AppSettings
    @State private var store: ReadingStore

    init() {
        let settings = AppSettings()
        let store = ReadingStore(settings: settings)
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        store.start()   // subscribes to `settings`, then begins polling
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(settings: settings, store: store)
        } label: {
            MenuBarLabel(settings: settings, store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
        .windowResizability(.contentSize)
    }
}
