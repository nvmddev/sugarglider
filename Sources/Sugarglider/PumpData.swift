import Foundation

/// The pump and the system driving it, as the newest device statuses on the
/// site describe them. Every field is optional: which ones exist depends on the
/// uploader, and a CGM-only site has none at all.
///
/// Insulin is in units, rates in U/h, glucose in mg/dL like everywhere else.
struct PumpStatus: Equatable {
    /// When the newest record that contributed was created. It dates the data,
    /// not the fetch, so it's what the dropdown's staleness note goes by.
    var date: Date
    var insulinOnBoard: Double?
    var reservoir: Double?
    var batteryPercent: Double?
    var mode: Mode?
    var deliveryRate: Double?
    var insulinToday: Double?
    var insulinYesterday: Double?
    var averageToday: Double?
    var averageYesterday: Double?

    enum Mode: Equatable {
        case auto
        case off
        /// CamAPS FX's temporary modes. `until` is the end as the clock time the
        /// uploader's status text gives, when it gives one.
        case boost(until: String?)
        case easeOff(until: String?)
        /// An uploader's own status text, shown as it comes.
        case other(String)

        var label: String {
            switch self {
            case .auto: return "Auto mode"
            case .off: return "Auto mode off"
            case .boost(let until): return "Boost" + (until.map { " until \($0)" } ?? "")
            case .easeOff(let until): return "Ease-off" + (until.map { " until \($0)" } ?? "")
            case .other(let text): return text
            }
        }

        var isStatusText: Bool {
            if case .other = self { return true }
            return false
        }
    }

    var hasData: Bool {
        insulinOnBoard != nil || reservoir != nil || batteryPercent != nil || mode != nil
            || deliveryRate != nil || insulinToday != nil || insulinYesterday != nil
            || averageToday != nil || averageYesterday != nil
    }

    /// One `devicestatus` record. Read from `JSONSerialization` output rather
    /// than through `Decodable`: the record nests several levels deep, its shape
    /// differs by uploader, and any one field may be missing or typed
    /// differently, which a strict decode would answer by dropping the record.
    ///
    /// `pump` is Nightscout's common pump block. `camaps` is a block an
    /// uploader for CamAPS FX adds, since Nightscout has no place for that
    /// system's mode and daily totals. Loop and OpenAPS-style uploaders
    /// (AndroidAPS, Trio) report the insulin on board under their own key
    /// instead of `pump`.
    init?(record: [String: Any]) {
        guard let date = NightscoutTime.date(record["created_at"]) ?? NightscoutTime.date(record["mills"])
        else { return nil }
        self.date = date
        let pump = record["pump"] as? [String: Any]
        let camaps = record["camaps"] as? [String: Any]

        let pumpIOB = pump?["iob"] as? [String: Any]
        let loopIOB = (record["loop"] as? [String: Any])?["iob"] as? [String: Any]
        // OpenAPS sends an array of forecast points here, the first being now.
        let openapsIOB = (record["openaps"] as? [String: Any])?["iob"]
        let openapsNow = (openapsIOB as? [String: Any]) ?? (openapsIOB as? [[String: Any]])?.first
        insulinOnBoard = Self.number(pumpIOB?["iob"]) ?? Self.number(pumpIOB?["bolusiob"])
            ?? Self.number(loopIOB?["iob"]) ?? Self.number(openapsNow?["iob"])

        reservoir = Self.number(pump?["reservoir"])
        batteryPercent = Self.number((pump?["battery"] as? [String: Any])?["percent"])
        mode = Self.mode(autoMode: camaps?["auto_mode"] as? Bool,
                         boost: camaps?["boost"] as? Bool,
                         easeOff: camaps?["ease_off"] as? Bool,
                         statusText: (pump?["status"] as? [String: Any])?["status"] as? String)
        deliveryRate = Self.number(camaps?["delivery_rate"])
        insulinToday = Self.number(camaps?["insulin_today"])
        insulinYesterday = Self.number(camaps?["insulin_yesterday"])
        averageToday = Self.number(camaps?["glucose_mean_today_mmol"]).map { $0 * 18 }
        averageYesterday = Self.number(camaps?["glucose_mean_yesterday_mmol"]).map { $0 * 18 }
    }

    init(date: Date) { self.date = date }

    /// How far back from the newest record a field may still be filled in. An
    /// uploader can split its data over several records, and two uploaders can
    /// share a site, but a value from an uploader that stopped hours ago must
    /// not pass for current next to fresh ones.
    static let mergeSpan: TimeInterval = 15 * 60

    /// Records combined field by field, each value taken from the newest record
    /// within `mergeSpan` that has it. Nil when no record says anything.
    static func merged(_ records: [PumpStatus]) -> PumpStatus? {
        let newestFirst = records.filter(\.hasData).sorted { $0.date > $1.date }
        guard var merged = newestFirst.first else { return nil }
        for r in newestFirst.dropFirst() where merged.date.timeIntervalSince(r.date) <= mergeSpan {
            merged.insulinOnBoard = merged.insulinOnBoard ?? r.insulinOnBoard
            merged.reservoir = merged.reservoir ?? r.reservoir
            merged.batteryPercent = merged.batteryPercent ?? r.batteryPercent
            merged.mode = merged.mode ?? r.mode
            merged.deliveryRate = merged.deliveryRate ?? r.deliveryRate
            merged.insulinToday = merged.insulinToday ?? r.insulinToday
            merged.insulinYesterday = merged.insulinYesterday ?? r.insulinYesterday
            merged.averageToday = merged.averageToday ?? r.averageToday
            merged.averageYesterday = merged.averageYesterday ?? r.averageYesterday
        }
        return merged
    }

    /// CamAPS FX reports its mode as flags. The status text is still read for
    /// those, because it's the only place a Boost's end time appears ("Boost
    /// bis 15:04"). Without the flags the text itself is the mode.
    static func mode(autoMode: Bool?, boost: Bool?, easeOff: Bool?, statusText: String?) -> Mode? {
        let text = statusText?.trimmingCharacters(in: .whitespaces) ?? ""
        let until = text.firstMatch(of: #/\b([01]?\d|2[0-3]):[0-5]\d\b/#).map { String($0.output.0) }
        if boost == true { return .boost(until: until) }
        if easeOff == true { return .easeOff(until: until) }
        if let autoMode { return autoMode ? .auto : .off }
        return text.isEmpty ? nil : .other(text)
    }

    /// A JSON number, or a string holding one, which some uploaders send. No
    /// `is Bool` guard: `JSONSerialization` hands numbers out as `NSNumber`,
    /// which casts to `Bool` whenever it holds 0 or 1, so such a guard would
    /// drop every insulin on board of exactly 0.
    static func number(_ value: Any?) -> Double? {
        if let n = value as? Double { return n.isFinite ? n : nil }
        return (value as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// A treatment, reduced to the kinds the chart draws.
struct Treatment: Equatable {
    var id: String
    var date: Date
    var kind: Kind

    enum Kind: Equatable {
        case bolus(units: Double)
        /// An absolute rate that holds for `minutes` or until the next temp
        /// basal starts, see `ChartMath.deliverySteps`. A zero duration only
        /// ends the one before it, which is how some loops cancel a temp basal.
        case tempBasal(rate: Double, minutes: Double)
        /// An announcement or note. Uploaders file pump and sensor alarms as
        /// announcements, so they aren't lost once acknowledged.
        case note(String)
    }

    init(id: String, date: Date, kind: Kind) {
        self.id = id
        self.date = date
        self.kind = kind
    }

    /// One `treatments` record, or nil for anything the chart doesn't draw (a
    /// reservoir change, a percent-only temp basal) or can't place in time.
    /// Same reasoning as `PumpStatus.init(record:)` for not using `Decodable`.
    init?(record: [String: Any]) {
        guard let date = NightscoutTime.date(record["created_at"])
                ?? NightscoutTime.date(record["mills"]) ?? NightscoutTime.date(record["date"])
        else { return nil }
        let eventType = record["eventType"] as? String ?? ""

        if eventType == "Temp Basal" {
            guard let minutes = PumpStatus.number(record["duration"]), minutes >= 0 else { return nil }
            let rate = PumpStatus.number(record["absolute"]) ?? PumpStatus.number(record["rate"])
            // A percent temp basal is relative to the profile, which isn't read.
            guard let rate = rate ?? (minutes == 0 ? 0 : nil), rate >= 0 else { return nil }
            kind = .tempBasal(rate: rate, minutes: minutes)
        } else if let units = PumpStatus.number(record["insulin"]), units > 0 {
            kind = .bolus(units: units)
        } else if eventType == "Announcement" || eventType == "Note",
                  let notes = (record["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !notes.isEmpty {
            kind = .note(notes)
        } else {
            return nil
        }
        self.date = date
        // Nightscout always sends an `_id`; the fallback only keeps the dedupe
        // in `ReadingStore` from merging two records that lack one.
        id = record["_id"] as? String ?? "\(eventType)@\(date.timeIntervalSince1970)"
    }

    var bolusUnits: Double? {
        if case .bolus(let units) = kind { return units }
        return nil
    }

    var noteText: String? {
        if case .note(let text) = kind { return text }
        return nil
    }

    var isTempBasal: Bool {
        if case .tempBasal = kind { return true }
        return false
    }
}

/// Nightscout's two ways of writing a time: `created_at` as an ISO 8601 string
/// (with or without milliseconds, in UTC or with an offset), and `date`/`mills`
/// as epoch milliseconds.
enum NightscoutTime {
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return (try? Date(text, strategy: withFraction)) ?? (try? Date(text, strategy: withoutFraction))
        }
        guard let ms = PumpStatus.number(value), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// The form Nightscout stores `created_at` in, so a `find[created_at]`
    /// filter compares like with like: the server compares those as strings.
    static func string(_ date: Date) -> String { date.formatted(withFraction) }

    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()
}

/// Display text for the pump values, through `String(format:)` like the
/// readings, so a dot is the decimal separator whatever the system region.
enum PumpFormat {
    static func insulin(_ units: Double) -> String { String(format: "%.2f U", units) }
    static func dailyInsulin(_ units: Double) -> String { String(format: "%.1f U", units) }
    static func rate(_ unitsPerHour: Double) -> String { String(format: "%.2f U/h", unitsPerHour) }
    static func battery(_ percent: Double) -> String { String(format: "%.0f%%", percent) }

    /// One decimal, or two for the small doses some loops give ("0.05 U").
    static func bolus(_ units: Double) -> String {
        let tenths = (units * 10).rounded()
        return abs(units * 10 - tenths) < 0.001 ? String(format: "%.1f U", units) : String(format: "%.2f U", units)
    }

    /// Whole units once there's enough left for a decimal to be noise.
    static func reservoir(_ units: Double) -> String {
        units >= 10 ? String(format: "%.0f U", units) : String(format: "%.1f U", units)
    }

    /// Time since a change, Nightscout's age-pill style: "35m", "5h", "1d 4h".
    /// Rounds down, like `ReadingStore.compactAge`.
    static func age(since date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
    }
}
