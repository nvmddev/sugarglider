import SwiftUI

struct PumpTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Active insulin", isOn: $settings.showActiveInsulin)
                toggle("Mode", detail: "Auto mode, Boost or Ease-off", isOn: $settings.showPumpMode)
                toggle("Delivery rate", detail: "What the pump delivers right now", isOn: $settings.showDeliveryRate)
                Toggle("Reservoir", isOn: $settings.showReservoir)
                Toggle("Pump battery", isOn: $settings.showPumpBattery)
                toggle("Time since change", detail: "Next to the reservoir and the battery",
                       isOn: $settings.showChangeAge)
                    .disabled(!settings.showReservoir && !settings.showPumpBattery)
                toggle("Total insulin", detail: "Today and yesterday", isOn: $settings.showDailyInsulin)
                toggle("Average glucose", detail: "Today and yesterday", isOn: $settings.showAverageGlucose)
            } header: {
                Text("Dropdown")
            } footer: {
                Text("""
                    Each item appears only if your Nightscout site reports it, through the \
                    device status a pump or loop uploader sends. Mode, delivery rate and the \
                    daily figures are CamAPS FX values, which only some uploaders pass on.
                    """)
                    .foregroundStyle(.secondary)
            }
            Section {
                toggle("Boluses", detail: "As bars under the chart", isOn: $settings.chartShowsBoluses)
                toggle("Delivery rate", detail: "As an area under the chart", isOn: $settings.chartShowsDeliveryRate)
                toggle("Announcements", detail: "Marks along the top, e.g. pump and sensor alerts",
                       isOn: $settings.chartShowsAnnouncements)
            } header: {
                Text("Chart")
            } footer: {
                Text("""
                    Hover the chart for the amounts and the announcement texts. Pump data is \
                    fetched when the dropdown opens, never in the background.
                    """)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }
}
