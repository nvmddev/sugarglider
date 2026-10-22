import SwiftUI

struct PumpDetailsView: View {
    var settings: AppSettings
    var store: ReadingStore
    var width: CGFloat

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
                    Text(stale).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .frame(width: width)
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
            .font(.system(size: 10))
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
            rows.append(Row(label: "Active insulin", value: PumpFormat.insulin(iob)))
        }

        // With both on, the mode labels the rate ("Auto mode … 1.20 U/h"); an uploader's free-form status
        // text can say anything, so it keeps a row of its own.
        let mode = settings.showPumpMode ? status.mode : nil
        let rate = settings.showDeliveryRate ? status.deliveryRate : nil
        if let mode, let rate, !mode.isStatusText {
            rows.append(Row(label: mode.label, value: PumpFormat.rate(rate), help: "Current delivery rate"))
        } else {
            if let mode { rows.append(Row(label: "Mode", value: mode.label)) }
            if let rate { rows.append(Row(label: "Delivery rate", value: PumpFormat.rate(rate))) }
        }

        let ages = settings.showChangeAge
        if settings.showReservoir, let units = status.reservoir {
            let age = ages ? reservoirChanged?.age(at: now, units: 2) : nil
            rows.append(Row(label: "Reservoir", value: PumpFormat.reservoir(units), note: age,
                            help: age.map { "Reservoir changed \($0) ago" }))
        }
        if settings.showPumpBattery, let percent = status.batteryPercent {
            let age = ages ? batteryChanged?.age(at: now, units: 2) : nil
            rows.append(Row(label: "Pump battery", value: PumpFormat.battery(percent), note: age,
                            help: age.map { "Battery changed \($0) ago" }))
        }
        return rows
    }

    static func dailyRows(status: PumpStatus?, settings: AppSettings) -> [DailyRow] {
        guard let status else { return [] }
        var rows: [DailyRow] = []
        func text(_ value: Double?, _ format: (Double) -> String) -> String { value.map(format) ?? "–" }
        if settings.showDailyInsulin, status.insulinToday != nil || status.insulinYesterday != nil {
            rows.append(DailyRow(label: "Total insulin",
                                 today: text(status.insulinToday, PumpFormat.dailyInsulin),
                                 yesterday: text(status.insulinYesterday, PumpFormat.dailyInsulin)))
        }
        if settings.showAverageGlucose, status.averageToday != nil || status.averageYesterday != nil {
            let glucose = { (mgdl: Double) in settings.units.text(fromMgdl: Int(mgdl.rounded())) }
            rows.append(DailyRow(label: "Average glucose",
                                 today: text(status.averageToday, glucose),
                                 yesterday: text(status.averageYesterday, glucose)))
        }
        return rows
    }

    /// The uploader can stop sending device statuses while glucose keeps flowing, and nothing else
    /// would show it.
    static func staleNote(status: PumpStatus?, settings: AppSettings, now: Date) -> String? {
        guard let status, now.timeIntervalSince(status.date) > settings.staleThreshold else { return nil }
        return "Pump data from \(status.date.relative(to: now))"
    }
}
