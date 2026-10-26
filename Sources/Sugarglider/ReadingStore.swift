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

    var pumpStatus: PumpStatus? {
        didSet { reportedPumpExtras.formUnion(pumpStatus?.extras ?? []) }
    }
    /// Every `PumpStatus.Extra` the site has sent, which the Pump tab offers switches for. Collected, so a
    /// value the uploader leaves out of one status doesn't take its switch along.
    private(set) var reportedPumpExtras: Set<PumpStatus.Extra> = []
    /// The chart's treatments, oldest first.
    var treatments: [Treatment] = []
    var reservoirChanged: Date?
    var batteryChanged: Date?

    /// What ages and the stale check are measured against, so the views redraw as time passes even when
    /// no value changes. They can't keep time themselves: a `TimelineView` hangs a `MenuBarExtra` label.
    private(set) var now = Date.now

    /// Start of the window the last full fetch requested, which is what the cache covers.
    @ObservationIgnored private(set) var historyWindowStart: Date?
    @ObservationIgnored private(set) var treatmentsWindowStart: Date?

    private enum Part { case history, pumpStatus, treatments, changeDates }
    @ObservationIgnored private var fetchedAt: [Part: Date] = [:]
    /// Bumped by `reconnect()`. Responses to earlier requests are dropped, so a slow answer
    /// from the previous site can't repopulate the store.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var reconnecting: Task<Void, Never>?
    @ObservationIgnored private var widening: Task<Void, Never>?

    private let settings: AppSettings
    private let session: URLSession

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

    init(settings: AppSettings, session: URLSession = Nightscout.sharedSession) {
        self.settings = settings
        self.session = session
    }

    private var site: Nightscout {
        Nightscout(baseURL: settings.baseURL, token: settings.token, session: session)
    }

    /// Polls, keeps the clock and follows the settings the fetches depend on, for the app's lifetime.
    func start() {
        Task {
            for await seconds in Observations({ self.settings.pollIntervalSeconds }) { poll(every: seconds) }
        }
        Task {
            for await _ in Observations({ (self.settings.baseURL, self.settings.token) }).dropFirst() { reconnect() }
        }
        Task {
            for await _ in Observations({ self.settings.rangeHours }).dropFirst() { ensureHistoryCoverage() }
        }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
                tick()
            }
        }
    }

    func tick() {
        now = .now
    }

    private func poll(every seconds: Int) {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(seconds) / 2)
            }
        }
    }

    /// Fetches the two newest entries: the older one is what the delta is taken against.
    func refresh() async {
        guard settings.isConfigured else { return }
        let (site, generation) = (site, generation)
        do {
            let latest = try await site.entries(count: 2)
            guard generation == self.generation else { return }
            showNewest(of: latest)
            if Self.joinsUp(latest, with: readings) { merge(latest) }
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }

    /// Whether polled entries add to the history without a dropout. Entries beyond one stay
    /// out, so the next top-up starts at its near edge and fills it.
    static func joinsUp(_ polled: [Reading], with history: [Reading]) -> Bool {
        guard let newestCached = history.last?.date,
              let firstNew = polled.first(where: { $0.date > newestCached }) else { return false }
        return firstNew.date.timeIntervalSince(newestCached) <= ChartMath.dropoutThreshold
    }

    /// Fetches the window once, then only what arrived after the newest cached entry.
    func refreshHistory(force: Bool) async {
        guard settings.isConfigured, force || !fetchedRecently(.history) else { return }
        let start = windowStart
        let covered = Self.covers(historyWindowStart, from: start)
        // Never nil, not even for a covered but empty cache: that would be an unfiltered request.
        let since = (covered ? readings.last?.date : nil) ?? start
        let count = Self.historyCount(forRangeHours: settings.rangeHours)
        guard let fetched = await fetch({ try await $0.entries(count: count, since: since) }) else { return }
        fetchedAt[.history] = .now
        if !covered { historyWindowStart = start }
        merge(fetched)
    }

    /// A cap, not a selector: the date filter picks the window, this only bounds a site that
    /// uploads every minute instead of every five.
    static func historyCount(forRangeHours hours: Int) -> Int {
        min(hours * 60 + 60, 2880)
    }

    /// Goes by the window that was requested, not by the oldest reading received: a site with
    /// only a few hours of data would otherwise refetch its whole window on every call.
    static func covers(_ requested: Date?, from start: Date) -> Bool {
        requested.map { $0 <= start } ?? false
    }

    /// Fetches what a widened range is missing, the treatments too once they've been fetched at
    /// all. Debounced, since a slider drag walks through every step, and unthrottled, since the
    /// gap shows in the chart.
    func ensureHistoryCoverage() {
        guard settings.isConfigured else { return }
        let start = windowStart
        let needsHistory = !Self.covers(historyWindowStart, from: start)
        let needsTreatments = settings.needsTreatments && fetchedAt[.treatments] != nil
            && !Self.covers(treatmentsWindowStart, from: start)
        guard needsHistory || needsTreatments else { return }
        widening?.cancel()
        widening = Task {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            if needsHistory { await refreshHistory(force: true) }
            if needsTreatments { await refreshTreatments(force: true) }
        }
    }

    /// Fetches each part only while a switch shows it. The throttle is per part, so one just
    /// switched on is fetched on the next open.
    func refreshDetails(force: Bool) async {
        async let status: Void = refreshPumpStatus(force: force)
        async let treatments: Void = refreshTreatments(force: force)
        async let changes: Void = refreshChangeDates(force: force)
        _ = await (status, treatments, changes)
    }

    /// The Pump tab asks `evenIfSwitchedOff`: it offers a switch for each `PumpStatus.Extra` the site
    /// sends, so it has to know before any is on.
    func refreshPumpStatus(force: Bool, evenIfSwitchedOff: Bool = false) async {
        guard settings.isConfigured, evenIfSwitchedOff || settings.needsPumpStatus,
              force || !fetchedRecently(.pumpStatus) else { return }
        guard let status = await fetch({ try await $0.pumpStatus() }) else { return }
        fetchedAt[.pumpStatus] = .now
        pumpStatus = status
    }

    func refreshTreatments(force: Bool) async {
        guard settings.isConfigured, settings.needsTreatments,
              force || !fetchedRecently(.treatments) else { return }
        let start = windowStart
        let covered = Self.covers(treatmentsWindowStart, from: start)
        let since = Self.treatmentsSince(windowStart: start, covered: covered,
                                         newestCached: treatments.last?.date)
        let count = Self.historyCount(forRangeHours: settings.rangeHours)
        guard let fetched = await fetch({ try await $0.treatments(count: count, since: since) }) else { return }
        fetchedAt[.treatments] = .now
        if !covered { treatmentsWindowStart = start }
        treatments = Self.merged(treatments, with: fetched)
    }

    static func treatmentsSince(windowStart: Date, covered: Bool, newestCached: Date?) -> Date {
        let wholeWindow = windowStart.addingTimeInterval(-tempBasalLookback)
        guard covered, let newestCached else { return wholeWindow }
        return max(newestCached.addingTimeInterval(-treatmentOverlap), wholeWindow)
    }

    private func refreshChangeDates(force: Bool) async {
        guard settings.isConfigured, settings.needsChangeDates,
              force || !fetchedRecently(.changeDates) else { return }
        let since = Date.now.addingTimeInterval(-Self.changeLookback)
        let (showsReservoir, showsBattery) = (settings.showReservoir, settings.showPumpBattery)
        guard let dates = await fetch({ site in
            async let reservoir = showsReservoir ? site.latestEvent(Self.reservoirChangeEvent, since: since) : nil
            async let battery = showsBattery ? site.latestEvent(Self.batteryChangeEvent, since: since) : nil
            return try await (reservoir: reservoir, battery: battery)
        }) else { return }
        fetchedAt[.changeDates] = .now
        reservoirChanged = dates.reservoir
        batteryChanged = dates.battery
    }

    /// The result of a request to the current site, or nil when it failed or the site changed
    /// meanwhile; either way the values already shown stay. A nil the request returns is an
    /// answer (no pump on the site, no change on record) and comes back as `.some(nil)`.
    private func fetch<Value>(_ request: (Nightscout) async throws -> Value) async -> Value? {
        let generation = generation
        guard let value = try? await request(site), generation == self.generation else { return nil }
        return value
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
        reportedPumpExtras = []
        treatments = []
        reservoirChanged = nil
        batteryChanged = nil
        historyWindowStart = nil
        treatmentsWindowStart = nil
        fetchedAt = [:]
        widening?.cancel()
        reconnecting?.cancel()
        reconnecting = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await refresh()
            await refreshHistory(force: true)
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
        tick()
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
        return delta.formatted(.number.precision(.fractionLength(units == .mmol ? 1 : 0)).sign(strategy: .always()))
    }

    var isStale: Bool {
        guard let lastReading else { return false }
        return now.timeIntervalSince(lastReading.date) > settings.staleThreshold
    }
}

extension Date {
    /// "13m", "1d 4h": the time from this date to `now` in at most `units` units, rounded down so an age
    /// never overstates.
    func age(at now: Date, units: Int = 1) -> String {
        Duration.seconds(max(0, now.timeIntervalSince(self))).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow,
                   maximumUnitCount: units, fractionalPart: .hide(rounded: .down)))
    }

    /// "3 minutes ago", "this minute", "yesterday".
    func relative(to now: Date) -> String {
        var style = Date.AnchoredRelativeFormatStyle(anchor: self, presentation: .named, unitsStyle: .wide)
        style.allowedFields = [.minute, .hour, .day]
        return style.format(now)
    }
}
