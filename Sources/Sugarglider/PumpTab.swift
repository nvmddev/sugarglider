import SwiftUI

struct PumpTab: View {
    @Bindable var settings: AppSettings
    var store: ReadingStore

    var body: some View {
        let reported = store.reportedPumpExtras
        Form {
            Section {
                Toggle("Active insulin", isOn: $settings.showActiveInsulin)
                if reported.contains(.mode) {
                    toggle("Mode", detail: "The pump's current mode, e.g. Auto mode or Boost", isOn: $settings.showPumpMode)
                }
                if reported.contains(.deliveryRate) {
                    toggle("Delivery rate", detail: "What the pump delivers right now", isOn: $settings.showDeliveryRate)
                }
                Toggle("Reservoir", isOn: $settings.showReservoir)
                Toggle("Pump battery", isOn: $settings.showPumpBattery)
                toggle("Time since change", detail: "Next to the reservoir and the battery",
                       isOn: $settings.showChangeAge)
                    .disabled(!settings.showReservoir && !settings.showPumpBattery)
                if reported.contains(.dailyInsulin) {
                    toggle("Total insulin", detail: "Today and yesterday", isOn: $settings.showDailyInsulin)
                }
                if reported.contains(.averageGlucose) {
                    toggle("Average glucose", detail: "Today and yesterday", isOn: $settings.showAverageGlucose)
                }
            } header: {
                Text("Dropdown")
            } footer: {
                Text("""
                    Each item appears only if your Nightscout site reports it, through the \
                    device status a pump or loop uploader sends.
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
        .task { await store.refreshPumpStatus(force: false, evenIfSwitchedOff: true) }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }
}
