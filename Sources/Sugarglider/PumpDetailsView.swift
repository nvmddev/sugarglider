import SwiftUI

/// The pump values under the reading in the dropdown: a label/value list, then
/// today's and yesterday's totals as a small table. Each item has its own
/// switch in Settings and appears only when the site reports it, so a CGM-only
/// setup renders nothing here at all.
///
/// The rows are built by the static functions below, which are plain data in,
/// strings out, so what the dropdown says is testable without a view.
struct PumpDetailsView: View {
    var settings: AppSettings
    var store: ReadingStore
    var width: CGFloat

    struct Row: Equatable {
        var label: String
        var value: String
        /// Secondary text after the value, the time since a change.
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
                             batteryChanged: store.batteryChanged, settings: settings)
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
                if let stale = Self.staleNote(status: store.pumpStatus, settings: settings) {
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

    /// Two numbers per row, so a column each with a header, rather than two
    /// rows apiece in the list above.
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

    // MARK: - Content

    static func rows(status: PumpStatus?, reservoirChanged: Date?, batteryChanged: Date?,
                     settings: AppSettings, now: Date = Date()) -> [Row] {
        guard let status else { return [] }
        var rows: [Row] = []
        if settings.showActiveInsulin, let iob = status.insulinOnBoard {
            rows.append(Row(label: "Active insulin", value: PumpFormat.insulin(iob)))
        }

        // With both on, the mode labels the rate: "Auto mode … 1.20 U/h" reads
        // as one statement and saves a row that would mostly just say "Auto
        // mode". An uploader's own status text stays on its own row, since it
        // can be anything.
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
            let age = ages ? reservoirChanged.map { PumpFormat.age(since: $0, now: now) } : nil
            rows.append(Row(label: "Reservoir", value: PumpFormat.reservoir(units), note: age,
                            help: age.map { "Reservoir changed \($0) ago" }))
        }
        if settings.showPumpBattery, let percent = status.batteryPercent {
            let age = ages ? batteryChanged.map { PumpFormat.age(since: $0, now: now) } : nil
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

    /// Dates the values once they're older than a reading may be: the uploader
    /// can stop sending device statuses while glucose still flows, and nothing
    /// else would show it.
    static func staleNote(status: PumpStatus?, settings: AppSettings, now: Date = Date()) -> String? {
        guard let status, now.timeIntervalSince(status.date) > settings.staleThreshold else { return nil }
        return "Pump data from \(ReadingStore.relative(status.date))"
    }
}
