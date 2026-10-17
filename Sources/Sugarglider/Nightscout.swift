import Foundation

/// One glucose reading. `sgv` is always mg/dL, Nightscout's internal unit.
struct Reading {
    let sgv: Int
    let direction: String
    let date: Date

    func value(in units: AppSettings.Units) -> Double { units.value(fromMgdl: sgv) }
    func text(in units: AppSettings.Units) -> String { units.text(fromMgdl: sgv) }

    /// Doubles use paired single glyphs (`↑↑`) rather than `⇈`/`⇊`, which render
    /// thin and small.
    var trendArrow: String {
        switch direction {
        case "DoubleUp":      return "↑↑"
        case "SingleUp":      return "↑"
        case "FortyFiveUp":   return "↗"
        case "Flat":          return "→"
        case "FortyFiveDown": return "↘"
        case "SingleDown":    return "↓"
        case "DoubleDown":    return "↓↓"
        default:              return ""   // NONE / NOT COMPUTABLE / RATE OUT OF RANGE
        }
    }
}

enum NightscoutError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case empty
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Not configured"
        case .badURL:        return "Invalid URL"
        case .http(let c):   return "HTTP \(c)"
        case .empty:         return "No readings"
        case .decode:        return "Bad response"
        }
    }
}

/// A pure HTTP client: connection info is passed in by the caller rather than
/// read from `AppSettings` here. `@MainActor` because the only caller is;
/// the network wait itself still happens inside `URLSession`, off the main
/// thread.
@MainActor
enum Nightscout {
    /// The 15s timeout keeps a stalled request from pinning the poll timer.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: cfg)
    }()

    private static let decoder = JSONDecoder()

    /// One raw row of `entries/sgv.json`, decoded field by field so a single odd
    /// row can't fail the whole response the way a strict `Decodable` would: a
    /// missing `direction` is routine, and some sites emit a non-numeric `sgv`.
    /// `sgv` is a `Double` because fractional mg/dL happens.
    private struct Entry: Decodable {
        let sgv: Double?
        let direction: String?
        let millis: Double?

        private enum CodingKeys: String, CodingKey { case sgv, direction, date }

        init(from decoder: any Decoder) throws {
            let row = try decoder.container(keyedBy: CodingKeys.self)
            sgv = try? row.decodeIfPresent(Double.self, forKey: .sgv)
            direction = try? row.decodeIfPresent(String.self, forKey: .direction)
            millis = try? row.decodeIfPresent(Double.self, forKey: .date)
        }

        /// Nil for a row missing either field a plottable reading needs.
        var reading: Reading? {
            guard let sgv, let millis else { return nil }
            return Reading(sgv: Int(sgv.rounded()), direction: direction ?? "",
                           date: Date(timeIntervalSince1970: millis / 1000))
        }
    }

    /// Fetches up to `count` recent SGV entries, oldest-first so they plot
    /// left to right.
    ///
    /// `since` restricts the response to entries newer than that instant
    /// (Nightscout's Mongo-style `find[date][$gt]`), which is what makes topping
    /// up a cached history cheap. An empty response is an error only for a full
    /// fetch: with `since` set, "nothing new" is the expected answer.
    static func fetchEntries(count: Int, since: Date? = nil,
                             baseURL: String, token: String) async throws -> [Reading] {
        var items = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let ms = (since.timeIntervalSince1970 * 1000).rounded()
            items.append(URLQueryItem(name: "find[date][$gt]", value: String(Int64(ms))))
        }
        let data = try await get("/api/v1/entries/sgv.json", query: items, baseURL: baseURL, token: token)
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            throw NightscoutError.decode
        }
        let readings = entries.compactMap(\.reading).sorted { $0.date < $1.date }

        guard !readings.isEmpty || since != nil else { throw NightscoutError.empty }
        return readings
    }

    /// How many device statuses `fetchPumpStatus` merges. More than one,
    /// because an uploader may spread its data over several records and two
    /// uploaders may share a site; `PumpStatus.mergeSpan` keeps the older ones
    /// from passing for current.
    static let deviceStatusCount = 10

    /// The pump's current state, merged from the newest device statuses. Nil
    /// for a site that reports none, which is not an error: most only have a
    /// CGM uploading.
    static func fetchPumpStatus(baseURL: String, token: String) async throws -> PumpStatus? {
        let data = try await get("/api/v1/devicestatus.json",
                                 query: [URLQueryItem(name: "count", value: String(deviceStatusCount))],
                                 baseURL: baseURL, token: token)
        return PumpStatus.merged(try records(in: data).compactMap(PumpStatus.init(record:)))
    }

    /// Treatments created at or after `since`, oldest first, keeping only the
    /// kinds the chart draws. `count` is a cap, like `fetchEntries`'.
    static func fetchTreatments(since: Date, count: Int,
                                baseURL: String, token: String) async throws -> [Treatment] {
        let data = try await get("/api/v1/treatments.json", query: [
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
            URLQueryItem(name: "count", value: String(count)),
        ], baseURL: baseURL, token: token)
        return try records(in: data).compactMap(Treatment.init(record:)).sorted { $0.date < $1.date }
    }

    /// When the newest `eventType` treatment since `since` was created, or nil
    /// if there's none. For reservoir and battery changes, which lie days apart:
    /// a slice of the chart's window would mostly miss them, and without a date
    /// filter Nightscout searches only the last two days.
    static func fetchLatestEvent(_ eventType: String, since: Date,
                                 baseURL: String, token: String) async throws -> Date? {
        let data = try await get("/api/v1/treatments.json", query: [
            URLQueryItem(name: "find[eventType]", value: eventType),
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
            URLQueryItem(name: "count", value: "1"),
        ], baseURL: baseURL, token: token)
        return try records(in: data).compactMap { NightscoutTime.date($0["created_at"]) }.max()
    }

    /// A JSON array's objects. Anything else in the array is skipped rather
    /// than failing the whole response, same as a bad row in `Entry`.
    private static func records(in data: Data) throws -> [[String: Any]] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw NightscoutError.decode
        }
        return array.compactMap { $0 as? [String: Any] }
    }

    /// GETs `path` on the site with the token appended. Every endpoint goes
    /// through here, so trimming the URL, adding the token and checking the
    /// status can't differ between them.
    private static func get(_ path: String, query: [URLQueryItem],
                            baseURL: String, token: String) async throws -> Data {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }

        guard var comps = URLComponents(string: base + path) else { throw NightscoutError.badURL }
        var items = query
        let token = token.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        comps.queryItems = items

        guard let url = comps.url else { throw NightscoutError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NightscoutError.http(http.statusCode)
        }
        return data
    }

    enum ProbeResult: Equatable {
        case connected
        case failed(String)
    }

    /// Whether `baseURL`/`token` reach a site the token can read from. A site
    /// with no readings yet still counts as connected: the credentials work,
    /// there's just no data.
    static func probe(baseURL: String, token: String) async -> ProbeResult {
        do {
            _ = try await fetchEntries(count: 1, baseURL: baseURL, token: token)
            return .connected
        } catch NightscoutError.empty {
            return .connected
        } catch NightscoutError.http(401), NightscoutError.http(403) {
            return .failed("Authentication failed — check the token")
        } catch let error as NightscoutError {
            return .failed(error.errorDescription ?? "Connection failed")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
