import AppKit
import SwiftUI

/// Unit tests run inside the app, which mustn't come up for them: no menu bar item, no polling, no Keychain.
@main
enum Launcher {
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil {
            SugargliderApp.main()
        } else {
            NSApplication.shared.run()
        }
    }
}

struct SugargliderApp: App {
    @State private var settings: AppSettings
    @State private var store: ReadingStore

    init() {
        let settings = AppSettings()
        let store = ReadingStore(settings: settings)
        self.settings = settings
        self.store = store
        store.start()
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
    }
}
