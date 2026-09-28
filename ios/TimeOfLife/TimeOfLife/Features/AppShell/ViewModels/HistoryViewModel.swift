import Foundation

/// Day-grouped view data for the History list (history-entry-list spec).
struct DayGroup: Identifiable, Equatable {
    /// Stable identifier for the calendar day (e.g. "2026-09-03").
    let id: String
    /// Relative ("Today" / "Yesterday") or absolute regional day label.
    let label: String
    /// The day's entries, newest first.
    let entries: [TimeEntry]
    /// Natural-language sum of the day's known durations (e.g. "2h 35m").
    /// Entries with no duration (in-progress) contribute zero (D8).
    let total: String
}

/// Loads committed time entries from the local store and groups them by
/// calendar day for the History list (history-entry-list spec, design D2/D6).
/// Read-only: owns data only — scroll/chrome state lives in `HistoryView`.
/// Rows resolve categories from the entry itself (remove-activities-layer):
/// entries own their ordered category set, so there is no query-time
/// resolution through any other record.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dayGroups: [DayGroup] = []
    @Published private(set) var isLoading = false

    private let store: LocalStore
    private let nowProvider: () -> Date
    private var needsReload = true
    private var categoriesByID: [String: Category] = [:]

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.nowProvider = now
    }

    /// Reloads entries and categories and rebuilds the day groups. Called on
    /// appear.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await store.entries()
            let categories = try await store.categories()
            categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

            dayGroups = Self.makeDayGroups(entries: entries, now: Date())
        } catch {
            dayGroups = []
        }
    }

    /// Reloads only when the data has not been loaded yet or the tab was
    /// left and re-entered (an entry may have been saved on Track in
    /// between). Re-entrancy safe: never runs two loads concurrently; a call
    /// arriving mid-load keeps `needsReload` set so the next appear retries.
    func loadIfNeeded() async {
        guard needsReload, !isLoading else { return }
        needsReload = false
        await load()
    }

    /// Marks the data stale so the next History appear reloads it.
    func invalidate() {
        needsReload = true
    }

    // MARK: - Row presentation (EntryRow inputs)

    /// First category's validated SF Symbol, or the `questionmark` fallback
    /// when the entry has no categories (D6).
    func icon(for entry: TimeEntry) -> String {
        guard let first = categories(for: entry).first else {
            return "questionmark"
        }
        return CatalogIcon(validated: first.icon).displaySymbol
    }

    /// Comma-separated category names; empty string when none (D6).
    func categoryNames(for entry: TimeEntry) -> String {
        categories(for: entry).map(\.name).joined(separator: ", ")
    }

    func isInProgress(_ entry: TimeEntry) -> Bool {
        entry.endedAt == nil
    }

    /// Localized "via <Source>" provenance label; empty for manual entries
    /// (entry-provenance D7).
    func viaText(for entry: TimeEntry) -> String {
        EntryProvenance.viaText(for: entry.source)
    }

    /// The start–end timeframe caption ("14:00 – 15:20"); an in-progress
    /// entry shows the start time followed by the in-progress indicator (D5).
    func timeframeText(for entry: TimeEntry) -> String {
        let start = Self.timeText(for: entry.startedAt)
        if isInProgress(entry) {
            return "\(start) – \(L10n.historyInProgress.text)"
        }
        guard let endedAt = entry.endedAt else {
            return start
        }
        return "\(start) – \(Self.timeText(for: endedAt))"
    }

    /// The entry's natural-language duration in the given locale; an
    /// in-progress entry shows the localized in-progress indicator
    /// instead (D5).
    func durationText(for entry: TimeEntry, locale: Locale = .current) -> String {
        if isInProgress(entry) {
            return L10n.historyInProgress.text
        }
        let seconds = entry.durationSeconds ?? Self.clampedSeconds(
            start: entry.startedAt,
            end: entry.endedAt
        )
        return Self.naturalDuration(seconds, locale: locale)
    }

    /// The entry's own ordered categories, position-preserved, unknown ids
    /// skipped (entries own their categories; nothing resolves elsewhere).
    func categories(for entry: TimeEntry) -> [Category] {
        entry.categoryIDs.compactMap { categoriesByID[$0] }
    }

    // MARK: - Grouping (pure, unit-tested)

    /// Groups entries by the calendar day of `startedAt` (D2): newest day
    /// first, entries within a day newest first, per-day totals (D8).
    nonisolated static func makeDayGroups(
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DayGroup] {
        let sorted = entries.sorted { $0.startedAt > $1.startedAt }
        var buckets: [String: [TimeEntry]] = [:]
        var order: [String] = []
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.startedAt)
            let key = dayKey(day, calendar: calendar)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }

        return order.map { key in
            let dayEntries = buckets[key] ?? []
            let day = dayFromKey(key, calendar: calendar)
            return DayGroup(
                id: key,
                label: dayLabel(for: day, now: now, calendar: calendar),
                entries: dayEntries,
                total: naturalDuration(
                    dayEntries.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
                    locale: locale
                )
            )
        }
    }

    /// "Today" / "Yesterday" for the two most recent calendar days, then the
    /// device-locale regional date for older days (D3).
    nonisolated static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
        switch days {
        case 0: return L10n.historyDayToday.text
        case 1: return L10n.historyDayYesterday.text
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.calendar = calendar
            return formatter.string(from: day)
        }
    }

    /// Natural-language duration in the given locale (`33s`, `1m 20s`,
    /// `1h 12m`, `1d 12h` in English; locale-correct abbreviations and
    /// plurals elsewhere, e.g. `1 ч 12 мин` in Russian) (D5). The grammar —
    /// which tiers appear — is fixed here; Foundation owns the unit words.
    nonisolated static func naturalDuration(_ seconds: Int, locale: Locale = .current) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if days > 0 {
            return hours > 0
                ? "\(day(days, locale)) \(hour(hours, locale))"
                : day(days, locale)
        }
        if hours > 0 {
            return minutes > 0
                ? "\(hour(hours, locale)) \(minute(minutes, locale))"
                : hour(hours, locale)
        }
        if minutes > 0 {
            return secs > 0
                ? "\(minute(minutes, locale)) \(second(secs, locale))"
                : minute(minutes, locale)
        }
        return second(secs, locale)
    }

    /// Locale-aware single-unit words backing `naturalDuration` (one tiny
    /// `DateComponentsFormatter` each: a whole-string formatter cannot
    /// reproduce the two-tier grammar). The calendar is fixed to Gregorian —
    /// unit words do not depend on the calendar system — with the caller's
    /// locale applied to it.
    nonisolated private static func day(_ value: Int, _ locale: Locale) -> String {
        unit(value, .day, locale)
    }

    nonisolated private static func hour(_ value: Int, _ locale: Locale) -> String {
        unit(value, .hour, locale)
    }

    nonisolated private static func minute(_ value: Int, _ locale: Locale) -> String {
        unit(value, .minute, locale)
    }

    nonisolated private static func second(_ value: Int, _ locale: Locale) -> String {
        unit(value, .second, locale)
    }

    nonisolated private static func unit(_ value: Int, _ component: Calendar.Component, _ locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.calendar = calendar
        var components = DateComponents()
        switch component {
        case .day:
            components.day = value
            formatter.allowedUnits = [.day]
        case .hour:
            components.hour = value
            formatter.allowedUnits = [.hour]
        case .minute:
            components.minute = value
            formatter.allowedUnits = [.minute]
        default:
            components.second = value
            formatter.allowedUnits = [.second]
        }
        return formatter.string(from: components) ?? "\(value)"
    }

    /// Short-time caption ("14:00").
    nonisolated static func timeText(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func clampedSeconds(start: Date, end: Date?) -> Int {
        guard let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    nonisolated private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0
        )
    }

    nonisolated private static func dayFromKey(_ key: String, calendar: Calendar) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = !parts.isEmpty ? parts[0] : 0
        comps.month = parts.count > 1 ? parts[1] : 0
        comps.day = parts.count > 2 ? parts[2] : 0
        return calendar.date(from: comps) ?? Date()
    }

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
