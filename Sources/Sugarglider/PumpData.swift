import Foundation

/// The pump as the newest device statuses describe it. Insulin in U, rates in U/h, glucose in
/// mg/dL; a field is nil when the uploader doesn't report it.
struct PumpStatus: Equatable {
    /// Creation time of the newest contributing record, so it dates the data, not the fetch.
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
        /// CamAPS FX's temporary modes. `until` is the end time the status text gives, if any.
        case boost(until: String?)
        case easeOff(until: String?)
        /// An uploader's own status text, shown verbatim.
        case other(String)

        var label: String {
            switch self {
            case .auto: String(localized: "Auto mode")
            case .off: String(localized: "Auto mode off")
            case .boost(let until): until.map { String(localized: "Boost until \($0)") } ?? String(localized: "Boost")
            case .easeOff(let until): until.map { String(localized: "Ease-off until \($0)") } ?? String(localized: "Ease-off")
            case .other(let text): text
            }
        }

        var isStatusText: Bool {
            if case .other = self { true } else { false }
        }
    }

    var hasData: Bool { self != PumpStatus(date: date) }

    /// How much older than the newest record another may be and still fill in its fields: a
    /// stopped uploader's values must not pass for current.
    static let mergeSpan: TimeInterval = 15 * 60

    /// Each field from the newest record within `mergeSpan` that has it; nil when no record has data.
    static func merged(_ records: [PumpStatus]) -> PumpStatus? {
        let newestFirst = records.filter(\.hasData).sorted { $0.date > $1.date }
        guard let newest = newestFirst.first else { return nil }
        let recent = newestFirst.filter { newest.date.timeIntervalSince($0.date) <= mergeSpan }
        func latest<Value>(_ field: KeyPath<PumpStatus, Value?>) -> Value? {
            recent.lazy.compactMap { $0[keyPath: field] }.first
        }
        return PumpStatus(date: newest.date,
                          insulinOnBoard: latest(\.insulinOnBoard),
                          reservoir: latest(\.reservoir),
                          batteryPercent: latest(\.batteryPercent),
                          mode: latest(\.mode),
                          deliveryRate: latest(\.deliveryRate),
                          insulinToday: latest(\.insulinToday),
                          insulinYesterday: latest(\.insulinYesterday),
                          averageToday: latest(\.averageToday),
                          averageYesterday: latest(\.averageYesterday))
    }

    /// CamAPS FX's flags win, but the status text is still searched: it's the only place a
    /// Boost's end time appears ("Boost bis 15:04"). Without flags, the text is the mode.
    static func mode(autoMode: Bool?, boost: Bool?, easeOff: Bool?, statusText: String?) -> Mode? {
        let text = statusText?.trimmingCharacters(in: .whitespaces) ?? ""
        let until = text.firstMatch(of: #/\b(?:[01]?\d|2[0-3]):[0-5]\d\b/#).map { String($0.output) }
        if boost == true { return .boost(until: until) }
        if easeOff == true { return .easeOff(until: until) }
        if let autoMode { return autoMode ? .auto : .off }
        return text.isEmpty ? nil : .other(text)
    }
}

extension PumpStatus {
    /// One `devicestatus` record. Not `Decodable`: the shape differs by uploader (`camaps` is the
    /// block a CamAPS FX uploader adds), and a strict decode would drop a record over one odd field.
    init?(record: [String: Any]) {
        guard let date = NightscoutTime.date(record["created_at"]) ?? NightscoutTime.date(record["mills"])
        else { return nil }
        self.init(date: date)
        let pump = record.object("pump")
        let camaps = record.object("camaps")

        let pumpIOB = pump?.object("iob")
        // OpenAPS sends one object or an array of forecast points, the first being now.
        let openapsIOB = record.object("openaps")?["iob"]
        let openapsNow = (openapsIOB as? [String: Any]) ?? (openapsIOB as? [[String: Any]])?.first
        insulinOnBoard = pumpIOB?.number("iob") ?? pumpIOB?.number("bolusiob")
            ?? record.object("loop")?.object("iob")?.number("iob") ?? openapsNow?.number("iob")

        reservoir = pump?.number("reservoir")
        batteryPercent = pump?.object("battery")?.number("percent")
        mode = Self.mode(autoMode: camaps?.bool("auto_mode"), boost: camaps?.bool("boost"),
                         easeOff: camaps?.bool("ease_off"), statusText: pump?.object("status")?.string("status"))
        deliveryRate = camaps?.number("delivery_rate")
        insulinToday = camaps?.number("insulin_today")
        insulinYesterday = camaps?.number("insulin_yesterday")
        averageToday = camaps?.number("glucose_mean_today_mmol").map(AppSettings.Units.mmol.mgdl)
        averageYesterday = camaps?.number("glucose_mean_yesterday_mmol").map(AppSettings.Units.mmol.mgdl)
    }
}

/// A treatment, reduced to the kinds the chart draws.
struct Treatment: Equatable {
    let id: String
    let date: Date
    let kind: Kind

    enum Kind: Equatable {
        case bolus(units: Double)
        /// An absolute rate in U/h, held for `minutes` or until the next temp basal starts. A zero
        /// duration only ends the previous one, which is how some loops cancel a temp basal.
        case tempBasal(rate: Double, minutes: Double)
        /// An announcement or note, which is also where uploaders file pump and sensor alarms.
        case note(String)
    }

    var bolusUnits: Double? {
        if case .bolus(let units) = kind { units } else { nil }
    }

    var noteText: String? {
        if case .note(let text) = kind { text } else { nil }
    }

    var isTempBasal: Bool {
        if case .tempBasal = kind { true } else { false }
    }
}

extension Treatment {
    /// One `treatments` record, or nil for one the chart doesn't draw (a reservoir change, a
    /// percent temp basal) or can't place in time.
    init?(record: [String: Any]) {
        guard let date = NightscoutTime.date(record["created_at"])
                ?? NightscoutTime.date(record["mills"]) ?? NightscoutTime.date(record["date"])
        else { return nil }
        let eventType = record.string("eventType") ?? ""
        let kind: Kind
        if eventType == "Temp Basal" {
            guard let minutes = record.number("duration"), minutes >= 0 else { return nil }
            // Without an absolute rate it's a cancel (zero duration) or a percent of the profile,
            // which isn't read.
            let rate = record.number("absolute") ?? record.number("rate")
            guard let rate = rate ?? (minutes == 0 ? 0 : nil), rate >= 0 else { return nil }
            kind = .tempBasal(rate: rate, minutes: minutes)
        } else if let units = record.number("insulin"), units > 0 {
            kind = .bolus(units: units)
        } else if eventType == "Announcement" || eventType == "Note",
                  let notes = record.string("notes")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !notes.isEmpty {
            kind = .note(notes)
        } else {
            return nil
        }
        // Nightscout always sends an `_id`; the fallback keeps id-less records apart in the dedupe.
        self.init(id: record.string("_id") ?? "\(eventType)@\(date.timeIntervalSince1970)", date: date, kind: kind)
    }
}

/// Nightscout's two time encodings: ISO 8601 strings (`created_at`, with or without fractional
/// seconds, any UTC offset) and epoch milliseconds (`date`, `mills`).
enum NightscoutTime {
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return (try? Date(text, strategy: withFraction)) ?? (try? Date(text, strategy: withoutFraction))
        }
        guard let milliseconds = jsonNumber(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// The format Nightscout stores `created_at` in; a `find[created_at]` filter compares as strings.
    static func string(_ date: Date) -> String { date.formatted(withFraction) }

    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()
}

enum PumpFormat {
    static func insulin(_ units: Double) -> String { "\(units.formatted(digits(2))) U" }
    static func dailyInsulin(_ units: Double) -> String { "\(units.formatted(digits(1))) U" }
    static func rate(_ unitsPerHour: Double) -> String { "\(unitsPerHour.formatted(digits(2))) U/h" }
    static func battery(_ percent: Double) -> String { (percent / 100).formatted(.percent.precision(.fractionLength(0))) }

    /// Two decimals only for the finer doses some loops give ("0.05 U").
    static func bolus(_ units: Double) -> String {
        let tenths = units * 10
        return "\(units.formatted(digits(abs(tenths - tenths.rounded()) < 0.001 ? 1 : 2))) U"
    }

    static func reservoir(_ units: Double) -> String { "\(units.formatted(digits(units >= 10 ? 0 : 1))) U" }

    private static func digits(_ count: Int) -> FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(count))
    }
}

private extension [String: Any] {
    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func number(_ key: String) -> Double? { jsonNumber(self[key]) }
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
}

/// A finite JSON number, or a string holding one. No `is Bool` guard: `NSNumber` casts to `Bool`
/// whenever it holds 0 or 1, so the guard would drop every insulin on board of 0.
private func jsonNumber(_ value: Any?) -> Double? {
    let number = (value as? Double) ?? (value as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard let number, number.isFinite else { return nil }
    return number
}
