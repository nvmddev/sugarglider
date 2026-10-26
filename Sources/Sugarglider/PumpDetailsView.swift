import SwiftUI

struct PumpDetailsView: View {
    var settings: AppSettings
    var store: ReadingStore

    struct Row: Equatable {
        var label: String
        var value: String
        var note: String? = nil
        var help: String? = nil
    }

    struct DailyRow: Equatable {
        var label: String
        var today: String
        var yesterday: String
    }

    var body: some View {
        let rows = Self.rows(status: store.pumpStatus, reservoirChanged: store.reservoirChanged,
                             batteryChanged: store.batteryChanged, settings: settings, now: store.now)
        let daily = Self.dailyRows(status: store.pumpStatus, settings: settings)
        if !rows.isEmpty || !daily.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !rows.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(rows, id: \.label) { row in
                            GridRow {
                                Text(row.label)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                valueText(row)
                                    .gridColumnAlignment(.trailing)
                                    .help(row.help ?? "")
                            }
                        }
                    }
                }
                if !daily.isEmpty { dailyTable(daily) }
                if let stale = Self.staleNote(status: store.pumpStatus, settings: settings, now: store.now) {
                    Text(stale).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
        }
    }

    private func valueText(_ row: Row) -> Text {
        guard let note = row.note else { return Text(row.value) }
        return Text("\(Text(row.value))\(Text(" · " + note).foregroundStyle(.secondary))")
    }

    private func dailyTable(_ rows: [DailyRow]) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Today")
                Text("Yesterday")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            ForEach(rows, id: \.label) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.today)
                    Text(row.yesterday)
                }
            }
        }
    }

    static func rows(status: PumpStatus?, reservoirChanged: Date?, batteryChanged: Date?,
                     settings: AppSettings, now: Date) -> [Row] {
        guard let status else { return [] }
        var rows: [Row] = []
        if settings.showActiveInsulin, let iob = status.insulinOnBoard {
            rows.append(Row(label: String(localized: "Active insulin"), value: PumpFormat.insulin(iob)))
        }

        // With both on, the mode labels the rate ("Auto mode … 1.20 U/h"); an uploader's free-form status
        // text can say anything, so it keeps a row of its own.
        let mode = settings.showPumpMode ? status.mode : nil
        let rate = settings.showDeliveryRate ? status.deliveryRate : nil
        if let mode, let rate, !mode.isStatusText {
            rows.append(Row(label: mode.label, value: PumpFormat.rate(rate), help: String(localized: "Current delivery rate")))
        } else {
            if let mode { rows.append(Row(label: String(localized: "Mode"), value: mode.label)) }
            if let rate { rows.append(Row(label: String(localized: "Delivery rate"), value: PumpFormat.rate(rate))) }
        }

        let ages = settings.showChangeAge
        if settings.showReservoir, let value = status.reservoirMessage ?? status.reservoir.map(PumpFormat.reservoir) {
            let age = ages ? reservoirChanged?.age(at: now, units: 2) : nil
            rows.append(Row(label: String(localized: "Reservoir"), value: value, note: age,
                            help: age.map { String(localized: "Reservoir changed \($0) ago") }))
        }
        if settings.showPumpBattery, let percent = status.batteryPercent {
            let age = ages ? batteryChanged?.age(at: now, units: 2) : nil
            rows.append(Row(label: String(localized: "Pump battery"), value: PumpFormat.battery(percent), note: age,
                            help: age.map { String(localized: "Battery changed \($0) ago") }))
        }
        return rows
    }

    static func dailyRows(status: PumpStatus?, settings: AppSettings) -> [DailyRow] {
        guard let status else { return [] }
        var rows: [DailyRow] = []
        func text(_ value: Double?, _ format: (Double) -> String) -> String { value.map(format) ?? "–" }
        if settings.showDailyInsulin, status.insulinToday != nil || status.insulinYesterday != nil {
            rows.append(DailyRow(label: String(localized: "Total insulin"),
                                 today: text(status.insulinToday, PumpFormat.dailyInsulin),
                                 yesterday: text(status.insulinYesterday, PumpFormat.dailyInsulin)))
        }
        if settings.showAverageGlucose, status.averageToday != nil || status.averageYesterday != nil {
            let glucose = { (mgdl: Double) in settings.units.text(fromMgdl: Int(mgdl.rounded())) }
            rows.append(DailyRow(label: String(localized: "Average glucose"),
                                 today: text(status.averageToday, glucose),
                                 yesterday: text(status.averageYesterday, glucose)))
        }
        return rows
    }

    /// The uploader can stop sending device statuses while glucose keeps flowing, and nothing else
    /// would show it.
    static func staleNote(status: PumpStatus?, settings: AppSettings, now: Date) -> String? {
        guard let status, now.timeIntervalSince(status.date) > settings.staleThreshold else { return nil }
        return String(localized: "Pump data from \(status.date.relative(to: now))")
    }
}
