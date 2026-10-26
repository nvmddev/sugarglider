import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @Bindable var settings: AppSettings
    @State private var status = ConnectionStatus.unconfigured
    // SMAppService's status isn't observable, so it's mirrored here and re-read after every change.
    @State private var loginItem = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private enum ConnectionStatus {
        case unconfigured
        case checking
        case probed(Nightscout.ProbeResult)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nightscout URL", text: $settings.baseURL,
                          prompt: Text("https://your-site.nightscout.app"))
                SecureField("Access token", text: $settings.token, prompt: Text("e.g. monitor-1a2b3c4d"))
                LabeledContent("Status") { statusView }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("""
                        Leave the token empty if your site allows unauthenticated reads. \
                        It is kept in your Keychain, not in the preferences file.
                        """)
                    if settings.tokenStorageFailed {
                        Text("The Keychain refused to store the token, so Sugarglider will forget it when it quits.")
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Dropdown background", selection: $settings.dropdownBackground) {
                    Text("Glass").tag(AppSettings.DropdownBackground.glass)
                    Text("Solid").tag(AppSettings.DropdownBackground.solid)
                }
                Picker("Units", selection: $settings.units) {
                    Text("mmol/L").tag(AppSettings.Units.mmol)
                    Text("mg/dL").tag(AppSettings.Units.mgdl)
                }
                Picker("Show delta", selection: $settings.deltaDisplay) {
                    Text("Off").tag(AppSettings.DeltaDisplay.off)
                    Text("In Dropdown").tag(AppSettings.DeltaDisplay.menu)
                    Text("In Dropdown + Menu Bar").tag(AppSettings.DeltaDisplay.menuAndStatusBar)
                }
                LabeledContent("Refresh") {
                    intervalField("Every", value: $settings.pollIntervalSeconds,
                                  unit: "seconds", limits: AppSettings.pollIntervalLimits)
                }
                LabeledContent("Stale warning") {
                    intervalField("After", value: $settings.staleAfterMinutes,
                                  unit: "minutes", limits: AppSettings.staleAfterLimits)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("A reading with no successor for the stale delay is marked with ⚠ and its age in the menu bar.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem == .enabled || loginItem == .requiresApproval },
                    set: { setOpensAtLogin($0) }))
            } footer: {
                if loginItem == .requiresApproval {
                    HStack {
                        Text("Allow Sugarglider under Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                    }
                }
                if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .autocorrectionDisabled()
        .task(id: [settings.baseURL, settings.token]) { await checkConnection() }
        .onAppear { loginItem = SMAppService.mainApp.status }
    }

    private func setOpensAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItem = SMAppService.mainApp.status
    }

    private func intervalField(_ prefix: LocalizedStringKey, value: Binding<Int>,
                               unit: LocalizedStringKey, limits: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
            TextField("", value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
            Text(unit)
                .help(Text("\(limits.lowerBound)–\(limits.upperBound) \(Text(unit))"))
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .unconfigured:
            Text("Not configured").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .probed(.connected):
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .probed(.failed(let message)):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // Debounced: .task(id:) restarts on every keystroke, which cancels the sleep.
    private func checkConnection() async {
        guard settings.isConfigured else { status = .unconfigured; return }
        status = .checking
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let result = await settings.nightscout.probe()
        guard !Task.isCancelled else { return }
        status = .probed(result)
    }
}
