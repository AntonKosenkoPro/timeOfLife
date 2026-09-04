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
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dayGroups: [DayGroup] = []
    @Published private(set) var isLoading = false

    private let store: LocalStore
    private var needsReload = true
    private var categoriesByActivityID: [String: [Category]] = [:]

    init(store: LocalStore) {
        self.store = store
    }

    /// Reloads entries, activities, and categories and rebuilds the day
    /// groups. Called on appear.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await store.entries()
            let activities = try await store.activities()
            let categories = try await store.categories()

            var byActivity: [String: [Category]] = [:]
            var categoriesByID: [String: Category] = [:]
            for category in categories {
                categoriesByID[category.id] = category
            }
            for activity in activities {
                byActivity[activity.id] = activity.categoryIDs
                    .compactMap { categoriesByID[$0] }
            }
            categoriesByActivityID = byActivity

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
    /// when the activity has no categories (D6).
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

    /// The start–end timeframe caption ("14:00 – 15:20"); an in-progress
    /// entry shows the start time followed by the in-progress indicator (D5).
    func timeframeText(for entry: TimeEntry) -> String {
        let start = Self.timeFormatter.string(from: entry.startedAt)
        if isInProgress(entry) {
            return "\(start) – \(L10n.historyInProgress.text)"
        }
        guard let endedAt = entry.endedAt else {
            return start
        }
        return "\(start) – \(Self.timeFormatter.string(from: endedAt))"
    }

    /// Natural-language duration ("1h 20m"); in-progress entries show the
    /// localized in-progress indicator instead (D5).
    func durationText(for entry: TimeEntry) -> String {
        if isInProgress(entry) {
            return L10n.historyInProgress.text
        }
        let seconds = entry.durationSeconds ?? Self.clampedSeconds(
            start: entry.startedAt,
            end: entry.endedAt
        )
        return Self.naturalDuration(seconds)
    }

    func categories(for entry: TimeEntry) -> [Category] {
        categoriesByActivityID[entry.activityID] ?? []
    }

    // MARK: - Grouping (pure, unit-tested)

    /// Groups entries by the calendar day of `startedAt` (D2): newest day
    /// first, entries within a day newest first, per-day totals (D8).
    nonisolated static func makeDayGroups(entries: [TimeEntry], now: Date, calendar: Calendar = .current) -> [DayGroup] {
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
                total: naturalDuration(dayEntries.reduce(0) { $0 + ($1.durationSeconds ?? 0) })
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

    /// Natural-language duration: `33s`, `1m 20s`, `1h 12m`, `1d 12h` (D5).
    nonisolated static func naturalDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        }
        return "\(secs)s"
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
