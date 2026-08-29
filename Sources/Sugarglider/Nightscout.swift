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
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }

        guard var comps = URLComponents(string: base + "/api/v1/entries/sgv.json") else {
            throw NightscoutError.badURL
        }
        var items = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let ms = (since.timeIntervalSince1970 * 1000).rounded()
            items.append(URLQueryItem(name: "find[date][$gt]", value: String(Int64(ms))))
        }
        let token = token.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        comps.queryItems = items

        guard let url = comps.url else { throw NightscoutError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NightscoutError.http(http.statusCode)
        }
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            throw NightscoutError.decode
        }
        let readings = entries.compactMap(\.reading).sorted { $0.date < $1.date }

        guard !readings.isEmpty || since != nil else { throw NightscoutError.empty }
        return readings
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
