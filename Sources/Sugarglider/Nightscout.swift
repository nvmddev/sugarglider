import Foundation

/// `sgv` is always mg/dL, Nightscout's native unit.
struct Reading {
    let sgv: Int
    let direction: String
    let date: Date

    /// Nightscout's markers for a value beyond the sensor's range, one step past each bound. Only
    /// the side is known, so its own client shows LOW and HIGH in either unit.
    enum OutOfRange: Int {
        case low = 39
        case high = 401
    }

    var outOfRange: OutOfRange? { OutOfRange(rawValue: sgv) }

    func value(in units: AppSettings.Units) -> Double { units.value(fromMgdl: sgv) }

    func text(in units: AppSettings.Units) -> String {
        switch outOfRange {
        case .low: "LOW"
        case .high: "HIGH"
        case nil: units.text(fromMgdl: sgv)
        }
    }

    /// Paired arrows for the doubles, because ⇈ and ⇊ render too thin.
    var trendArrow: String {
        switch direction {
        case "DoubleUp":      "↑↑"
        case "SingleUp":      "↑"
        case "FortyFiveUp":   "↗"
        case "Flat":          "→"
        case "FortyFiveDown": "↘"
        case "SingleDown":    "↓"
        case "DoubleDown":    "↓↓"
        default:              ""  // NONE, NOT COMPUTABLE, RATE OUT OF RANGE
        }
    }
}

nonisolated enum NightscoutError: LocalizedError, Equatable {
    case notConfigured
    case badURL
    case http(Int)
    case empty
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured:  "Not configured"
        case .badURL:         "Invalid URL"
        case .http(let code): "HTTP \(code)"
        case .empty:          "No readings"
        case .decode:         "Bad response"
        }
    }
}

enum Nightscout {
    /// The 15 s timeout keeps a stalled request from pinning the poll timer.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    private static let decoder = JSONDecoder()

    /// Decoded field by field, so one odd row can't fail the whole response: a missing
    /// direction is routine, some sites send a non-numeric sgv, and fractional mg/dL happens.
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

        var reading: Reading? {
            guard let sgv, let millis else { return nil }
            return Reading(sgv: Int(sgv.rounded()), direction: direction ?? "",
                           date: Date(timeIntervalSince1970: millis / 1000))
        }
    }

    static func fetchEntries(count: Int, since: Date? = nil,
                             baseURL: String, token: String) async throws -> [Reading] {
        var query = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let millis = Int64((since.timeIntervalSince1970 * 1000).rounded())
            query.append(URLQueryItem(name: "find[date][$gt]", value: String(millis)))
        }
        let data = try await get("/api/v1/entries/sgv.json", query: query, baseURL: baseURL, token: token)
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            throw NightscoutError.decode
        }
        let readings = entries.compactMap(\.reading).sorted { $0.date < $1.date }
        // With `since` set this is a top-up, where nothing new is the normal answer.
        guard !readings.isEmpty || since != nil else { throw NightscoutError.empty }
        return readings
    }

    /// More than one, because an uploader may spread its data over several records;
    /// `PumpStatus.mergeSpan` keeps the older ones from passing for current.
    static let deviceStatusCount = 10

    /// Nil rather than an error for a site without pump data: most only have a CGM uploading.
    static func fetchPumpStatus(baseURL: String, token: String) async throws -> PumpStatus? {
        let data = try await get("/api/v1/devicestatus.json",
                                 query: [URLQueryItem(name: "count", value: String(deviceStatusCount))],
                                 baseURL: baseURL, token: token)
        return PumpStatus.merged(try records(in: data).compactMap(PumpStatus.init(record:)))
    }

    static func fetchTreatments(since: Date, count: Int,
                                baseURL: String, token: String) async throws -> [Treatment] {
        let data = try await get("/api/v1/treatments.json", query: [
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
            URLQueryItem(name: "count", value: String(count)),
        ], baseURL: baseURL, token: token)
        return try records(in: data).compactMap(Treatment.init(record:)).sorted { $0.date < $1.date }
    }

    /// `since` is required: without a date filter, Nightscout searches only the last two days.
    static func fetchLatestEvent(_ eventType: String, since: Date,
                                 baseURL: String, token: String) async throws -> Date? {
        let data = try await get("/api/v1/treatments.json", query: [
            URLQueryItem(name: "find[eventType]", value: eventType),
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
            URLQueryItem(name: "count", value: "1"),
        ], baseURL: baseURL, token: token)
        return try records(in: data).compactMap { NightscoutTime.date($0["created_at"]) }.max()
    }

    private static func records(in data: Data) throws -> [[String: Any]] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw NightscoutError.decode
        }
        return array.compactMap { $0 as? [String: Any] }
    }

    private static func get(_ path: String, query: [URLQueryItem],
                            baseURL: String, token: String) async throws -> Data {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + path) else { throw NightscoutError.badURL }

        let token = token.trimmingCharacters(in: .whitespaces)
        components.queryItems = token.isEmpty ? query : query + [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { throw NightscoutError.badURL }

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

    static func probe(baseURL: String, token: String) async -> ProbeResult {
        do {
            _ = try await fetchEntries(count: 1, baseURL: baseURL, token: token)
            return .connected
        } catch NightscoutError.empty {
            return .connected  // the credentials work, the site just has no readings yet
        } catch NightscoutError.http(401), NightscoutError.http(403) {
            return .failed("Authentication failed — check the token")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
