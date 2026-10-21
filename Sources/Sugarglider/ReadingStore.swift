import Foundation

/// Live state behind the status item and the dropdown; nothing is persisted. `init` has no
/// side effects, so tests can build a store freely; the app calls `start()` once.
@Observable
final class ReadingStore {
    var lastReading: Reading?
    var previousReading: Reading?
    var lastError: String?
    /// The chart's history, oldest first.
    var readings: [Reading] = []

    var pumpStatus: PumpStatus?
    /// The chart's treatments, oldest first.
    var treatments: [Treatment] = []
    var reservoirChanged: Date?
    var batteryChanged: Date?

    /// Start of the window the last full fetch requested, which is what the cache covers.
    @ObservationIgnored private(set) var historyWindowStart: Date?
    @ObservationIgnored private(set) var treatmentsWindowStart: Date?
    @ObservationIgnored private(set) var timer: Timer?

    private enum Part { case history, pumpStatus, treatments, changeDates }
    @ObservationIgnored private var fetchedAt: [Part: Date] = [:]
    /// Bumped by `reconnect()`. Responses to earlier requests are dropped, so a slow answer
    /// from the previous site can't repopulate the store.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reconnectDebounce: Task<Void, Never>?
    @ObservationIgnored private var coverageDebounce: Task<Void, Never>?

    private let settings: AppSettings

    static let contiguityThreshold = ChartMath.dropoutThreshold
    /// Treatments are fetched from this far before the window, so a temp basal already running
    /// at its left edge is drawn: loops set them for 30 minutes.
    static let tempBasalLookback: TimeInterval = 30 * 60
    /// How far a top-up reaches back past the newest cached treatment. Treatments land out of
    /// order: a bolus is dated when it was given and uploaded minutes later.
    static let treatmentOverlap: TimeInterval = 60 * 60
    /// Older reservoir and battery changes aren't worth showing an age for.
    private static let changeLookback: TimeInterval = 60 * 86_400
    private static let widestWindow = TimeInterval(AppSettings.rangeHoursLimits.upperBound) * 3600
    // Nightscout's own event types, the ones its age pills read.
    private static let reservoirChangeEvent = "Insulin Change"
    private static let batteryChangeEvent = "Pump Battery Change"

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        settings.onConnectionChanged = { [weak self] in self?.reconnect() }
        settings.onPollIntervalChanged = { [weak self] in self?.schedulePolling() }
        settings.onRangeHoursChanged = { [weak self] in self?.ensureHistoryCoverage() }
        refresh()
        schedulePolling()
    }

    private func schedulePolling() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval / 2
        // In the default mode the poll would stall while the range slider is dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Fetches the two newest entries: the older one is what the delta is taken against.
    func refresh() {
        guard settings.isConfigured else { return }
        let (baseURL, token, generation) = (settings.baseURL, settings.token, generation)
        Task {
            do {
                let latest = try await Nightscout.fetchEntries(count: 2, baseURL: baseURL, token: token)
                guard generation == self.generation else { return }
                showNewest(of: latest)
                if Self.joinsUp(latest, with: readings) { merge(latest) }
            } catch {
                guard generation == self.generation else { return }
                lastError = error.localizedDescription
            }
        }
    }

    /// Whether polled entries add to the history without a dropout. Entries beyond one stay
    /// out, so the next top-up starts at its near edge and fills it.
    static func joinsUp(_ polled: [Reading], with history: [Reading]) -> Bool {
        guard let newestCached = history.last?.date,
              let firstNew = polled.first(where: { $0.date > newestCached }) else { return false }
        return firstNew.date.timeIntervalSince(newestCached) <= contiguityThreshold
    }

    /// Fetches the window once, then only what arrived after the newest cached entry.
    func refreshHistory(force: Bool) {
        guard settings.isConfigured, force || !fetchedRecently(.history) else { return }
        let start = windowStart
        let covered = coversHistory(from: start)
        // Never nil, not even for a covered but empty cache: that would be an unfiltered request.
        let since = (covered ? readings.last?.date : nil) ?? start
        let count = Self.historyCount(forRangeHours: settings.rangeHours)
        let (baseURL, token, generation) = (settings.baseURL, settings.token, generation)
        Task {
            guard let fetched = try? await Nightscout.fetchEntries(
                    count: count, since: since, baseURL: baseURL, token: token),
                  generation == self.generation else { return }
            fetchedAt[.history] = .now
            if !covered { historyWindowStart = start }
            merge(fetched)
        }
    }

    /// A cap, not a selector: the date filter picks the window, this only bounds a site that
    /// uploads every minute instead of every five.
    static func historyCount(forRangeHours hours: Int) -> Int {
        min(hours * 60 + 60, 2880)
    }

    /// Goes by the window that was requested, not by the oldest reading received: a site with
    /// only a few hours of data would otherwise refetch its whole window on every call.
    static func historyCovers(requested: Date?, from start: Date) -> Bool {
        guard let requested else { return false }
        return requested <= start
    }

    func coversHistory(from start: Date) -> Bool {
        Self.historyCovers(requested: historyWindowStart, from: start)
    }

    /// Fetches what a widened range is missing, the treatments too once they've been fetched at
    /// all. Debounced, since a slider drag walks through every step, and unthrottled, since the
    /// gap shows in the chart.
    func ensureHistoryCoverage() {
        guard settings.isConfigured else { return }
        let start = windowStart
        let needsHistory = !coversHistory(from: start)
        let needsTreatments = settings.needsTreatments && fetchedAt[.treatments] != nil
            && !Self.historyCovers(requested: treatmentsWindowStart, from: start)
        guard needsHistory || needsTreatments else { return }
        coverageDebounce?.cancel()
        coverageDebounce = Task {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            if needsHistory { refreshHistory(force: true) }
            if needsTreatments { refreshTreatments(force: true) }
        }
    }

    /// Fetches each part only while a switch shows it. The throttle is per part, so one just
    /// switched on is fetched on the next open.
    func refreshDetails(force: Bool) {
        refreshPumpStatus(force: force)
        refreshTreatments(force: force)
        refreshChangeDates(force: force)
    }

    private func refreshPumpStatus(force: Bool) {
        guard settings.isConfigured, settings.needsPumpStatus,
              force || !fetchedRecently(.pumpStatus) else { return }
        let (baseURL, token, generation) = (settings.baseURL, settings.token, generation)
        Task {
            // Not `try?`, which would flatten the two: nil is an answer (no pump on the site),
            // a failure keeps the old status.
            let status: PumpStatus?
            do { status = try await Nightscout.fetchPumpStatus(baseURL: baseURL, token: token) } catch { return }
            guard generation == self.generation else { return }
            fetchedAt[.pumpStatus] = .now
            pumpStatus = status
        }
    }

    func refreshTreatments(force: Bool) {
        guard settings.isConfigured, settings.needsTreatments,
              force || !fetchedRecently(.treatments) else { return }
        let start = windowStart
        let covered = Self.historyCovers(requested: treatmentsWindowStart, from: start)
        let since = Self.treatmentsSince(windowStart: start, covered: covered,
                                         newestCached: treatments.last?.date)
        let count = Self.historyCount(forRangeHours: settings.rangeHours)
        let (baseURL, token, generation) = (settings.baseURL, settings.token, generation)
        Task {
            guard let fetched = try? await Nightscout.fetchTreatments(
                    since: since, count: count, baseURL: baseURL, token: token),
                  generation == self.generation else { return }
            fetchedAt[.treatments] = .now
            if !covered { treatmentsWindowStart = start }
            treatments = Self.merged(treatments, with: fetched)
        }
    }

    static func treatmentsSince(windowStart: Date, covered: Bool, newestCached: Date?) -> Date {
        let wholeWindow = windowStart.addingTimeInterval(-tempBasalLookback)
        guard covered, let newestCached else { return wholeWindow }
        return max(newestCached.addingTimeInterval(-treatmentOverlap), wholeWindow)
    }

    private func refreshChangeDates(force: Bool) {
        guard settings.isConfigured, settings.needsChangeDates,
              force || !fetchedRecently(.changeDates) else { return }
        let since = Date.now.addingTimeInterval(-Self.changeLookback)
        let (showsReservoir, showsBattery) = (settings.showReservoir, settings.showPumpBattery)
        let (baseURL, token, generation) = (settings.baseURL, settings.token, generation)
        Task {
            func latest(_ eventType: String, if shown: Bool) async throws -> Date? {
                guard shown else { return nil }
                return try await Nightscout.fetchLatestEvent(eventType, since: since,
                                                             baseURL: baseURL, token: token)
            }
            // Like the status: nil is an answer (no change on record), a failure keeps the old dates.
            let dates: (reservoir: Date?, battery: Date?)
            do {
                async let reservoir = latest(Self.reservoirChangeEvent, if: showsReservoir)
                async let battery = latest(Self.batteryChangeEvent, if: showsBattery)
                dates = try await (reservoir, battery)
            } catch { return }
            guard generation == self.generation else { return }
            fetchedAt[.changeDates] = .now
            reservoirChanged = dates.reservoir
            batteryChanged = dates.battery
        }
    }

    /// Forgets the previous site at once but debounces the re-fetch: this runs on every
    /// keystroke in the URL and token fields.
    func reconnect() {
        generation += 1
        lastReading = nil
        previousReading = nil
        lastError = nil
        readings = []
        pumpStatus = nil
        treatments = []
        reservoirChanged = nil
        batteryChanged = nil
        historyWindowStart = nil
        treatmentsWindowStart = nil
        fetchedAt = [:]
        coverageDebounce?.cancel()
        reconnectDebounce?.cancel()
        reconnectDebounce = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            refresh()
            refreshHistory(force: true)
        }
    }

    static func merged(_ cached: [Reading], with fetched: [Reading], now: Date = .now) -> [Reading] {
        merged(cached, with: fetched, by: \.date, date: \.date,
               keepingFrom: now.addingTimeInterval(-widestWindow))
    }

    static func merged(_ cached: [Treatment], with fetched: [Treatment], now: Date = .now) -> [Treatment] {
        merged(cached, with: fetched, by: \.id, date: \.date,
               keepingFrom: now.addingTimeInterval(-widestWindow - tempBasalLookback))
    }

    /// `fetched` folded into `cached`, a record delivered again replacing its cached copy.
    private static func merged<Record, Key: Hashable & Comparable>(
        _ cached: [Record], with fetched: [Record],
        by key: KeyPath<Record, Key>, date: KeyPath<Record, Date>, keepingFrom cutoff: Date
    ) -> [Record] {
        Dictionary((cached + fetched).map { ($0[keyPath: key], $0) }, uniquingKeysWith: { _, newer in newer })
            .values
            .filter { $0[keyPath: date] >= cutoff }
            // The key breaks ties, so the order never depends on the dictionary's.
            .sorted { ($0[keyPath: date], $0[keyPath: key]) < ($1[keyPath: date], $1[keyPath: key]) }
    }

    private func merge(_ fetched: [Reading]) {
        guard !fetched.isEmpty else { return }
        readings = Self.merged(readings, with: fetched)
        showNewest(of: readings)
    }

    private func showNewest(of sorted: [Reading]) {
        guard let newest = sorted.last else { return }
        lastReading = newest
        if sorted.count >= 2 { previousReading = sorted[sorted.count - 2] }
        lastError = nil
    }

    private var windowStart: Date {
        .now.addingTimeInterval(-TimeInterval(settings.rangeHours) * 3600)
    }

    private func fetchedRecently(_ part: Part) -> Bool {
        guard let fetched = fetchedAt[part] else { return false }
        return Date.now.timeIntervalSince(fetched) < 60
    }
}

extension ReadingStore {
    /// Signed change since the previous reading, e.g. "+0.3"; nil when switched off, when the
    /// two readings aren't consecutive, or when either is LOW or HIGH, which have no value.
    func deltaText() -> String? {
        guard settings.deltaDisplay != .off,
              let current = lastReading, let previous = previousReading,
              current.outOfRange == nil, previous.outOfRange == nil else { return nil }
        let gap = current.date.timeIntervalSince(previous.date)
        guard gap > 0, gap < 12 * 60 else { return nil }
        let units = settings.units
        let delta = current.value(in: units) - previous.value(in: units)
        return String(format: units == .mmol ? "%+.1f" : "%+.0f", delta)
    }

    var isStale: Bool {
        guard let lastReading else { return false }
        return Date.now.timeIntervalSince(lastReading.date) > settings.staleThreshold
    }

    /// "13m", "2h", "3d". Rounds down: it must never claim more time has passed than has.
    static func compactAge(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return switch seconds {
        case ..<3600: "\(seconds / 60)m"
        case ..<86_400: "\(seconds / 3600)h"
        default: "\(seconds / 86_400)d"
        }
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<30: "just now"
        case ..<90: "1 min ago"
        case ..<3600: "\(seconds / 60) min ago"
        case ..<7200: "1 h ago"
        default: "\(seconds / 3600) h ago"
        }
    }
}
