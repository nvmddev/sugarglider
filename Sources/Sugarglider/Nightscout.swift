import Foundation

/// `sgv` is always mg/dL, Nightscout's native unit.
struct Reading {
    let sgv: Int
    /// Nil when the uploader has none ("NONE", "NOT COMPUTABLE", "RATE OUT OF RANGE").
    let direction: Direction?
    let date: Date

    enum Direction: String {
        case doubleUp = "DoubleUp", singleUp = "SingleUp", fortyFiveUp = "FortyFiveUp", flat = "Flat"
        case fortyFiveDown = "FortyFiveDown", singleDown = "SingleDown", doubleDown = "DoubleDown"

        /// Paired arrows for the doubles, because ⇈ and ⇊ render too thin.
        var arrow: String {
            switch self {
            case .doubleUp: "↑↑"
            case .singleUp: "↑"
            case .fortyFiveUp: "↗"
            case .flat: "→"
            case .fortyFiveDown: "↘"
            case .singleDown: "↓"
            case .doubleDown: "↓↓"
            }
        }
    }

    /// Nightscout's markers for a value beyond the sensor's range, one step past each bound. Only
    /// the side is known, so its own client shows LOW and HIGH in either unit.
    enum OutOfRange: Int {
        case low = 39
        case high = 401
    }

    var outOfRange: OutOfRange? { OutOfRange(rawValue: sgv) }

    func value(in units: AppSettings.Units) -> Double { units.value(fromMgdl: Double(sgv)) }

    func text(in units: AppSettings.Units) -> String {
        switch outOfRange {
        case .low: "LOW"
        case .high: "HIGH"
        case nil: units.text(fromMgdl: sgv)
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
        case .notConfigured:  String(localized: "Not configured")
        case .badURL:         String(localized: "Invalid URL")
        case .http(let code): String(localized: "HTTP \(code)")
        case .empty:          String(localized: "No readings")
        case .decode:         String(localized: "Bad response")
        }
    }
}

/// A Nightscout site. `token` is empty for a site that allows unauthenticated reads.
struct Nightscout {
    var baseURL: String
    var token: String
    var session = Nightscout.sharedSession

    /// The 15 s timeout keeps a stalled request from holding up the next poll.
    static let sharedSession: URLSession = {
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
            return Reading(sgv: Int(sgv.rounded()), direction: direction.flatMap(Reading.Direction.init),
                           date: Date(timeIntervalSince1970: millis / 1000))
        }
    }

    /// Oldest first. With `since` set this is a top-up, where nothing new is a valid answer.
    func entries(count: Int, since: Date? = nil) async throws -> [Reading] {
        var query = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let millis = Int64((since.timeIntervalSince1970 * 1000).rounded())
            query.append(URLQueryItem(name: "find[date][$gt]", value: String(millis)))
        }
        let data = try await get("api/v1/entries/sgv.json", query: query)
        guard let entries = try? Self.decoder.decode([Entry].self, from: data) else {
            throw NightscoutError.decode
        }
        let readings = entries.compactMap(\.reading).sorted { $0.date < $1.date }
        guard !readings.isEmpty || since != nil else { throw NightscoutError.empty }
        return readings
    }

    /// More than one, because an uploader may spread its data over several records;
    /// `PumpStatus.mergeSpan` keeps the older ones from passing for current.
    static let deviceStatusCount = 10

    /// Nil rather than an error for a site without pump data: most only have a CGM uploading.
    func pumpStatus() async throws -> PumpStatus? {
        let data = try await get("api/v1/devicestatus.json",
                                 query: [URLQueryItem(name: "count", value: String(Self.deviceStatusCount))])
        return PumpStatus.merged(try Self.records(in: data).compactMap(PumpStatus.init(record:)))
    }

    /// Oldest first.
    func treatments(count: Int, since: Date) async throws -> [Treatment] {
        let data = try await get("api/v1/treatments.json", query: [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
        ])
        return try Self.records(in: data).compactMap(Treatment.init(record:)).sorted { $0.date < $1.date }
    }

    /// `since` is required: without a date filter, Nightscout searches only the last two days.
    func latestEvent(_ eventType: String, since: Date) async throws -> Date? {
        let data = try await get("api/v1/treatments.json", query: [
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "find[eventType]", value: eventType),
            URLQueryItem(name: "find[created_at][$gte]", value: NightscoutTime.string(since)),
        ])
        return try Self.records(in: data).compactMap { NightscoutTime.date($0["created_at"]) }.max()
    }

    private static func records(in data: Data) throws -> [[String: Any]] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw NightscoutError.decode
        }
        return array.compactMap { $0 as? [String: Any] }
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        let base = baseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["/"]))
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = token.isEmpty ? query : query + [URLQueryItem(name: "token", value: token)]
        guard let url = URL(string: base)?.appending(path: path).appending(queryItems: items) else {
            throw NightscoutError.badURL
        }

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

    func probe() async -> ProbeResult {
        do {
            _ = try await entries(count: 1)
            return .connected
        } catch NightscoutError.empty {
            return .connected  // the credentials work, the site just has no readings yet
        } catch NightscoutError.http(401), NightscoutError.http(403) {
            return .failed(String(localized: "Authentication failed. Check the token."))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
