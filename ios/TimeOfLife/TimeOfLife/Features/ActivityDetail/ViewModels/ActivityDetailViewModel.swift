import Foundation

/// Loads one activity's identity, categories, all-time total, and complete
/// committed-entry history for the activity detail sheet
/// (activity-detail-sheet spec). Read-only data owner — presentation state
/// lives in `ActivityDetailView`.
///
/// Reuses `HistoryViewModel`'s pure static grouping/formatting helpers
/// (design D2) rather than duplicating them.
@MainActor
final class ActivityDetailViewModel: ObservableObject {
    @Published private(set) var activity: Activity?
    @Published private(set) var dayGroups: [DayGroup] = []
    @Published private(set) var totalText: String = ""
    @Published private(set) var categories: [Category] = []
    @Published private(set) var icon: String = "questionmark"
    @Published private(set) var isLoading = false
    /// The activity vanished (cascade-deleted while the sheet was open) —
    /// the view dismisses on this (design D6).
    @Published private(set) var activityIsGone = false

    private let store: LocalStore
    private let activityID: String

    init(store: LocalStore, activityID: String) {
        self.store = store
        self.activityID = activityID
    }

    /// The store, surfaced so the view can construct the stacked editor
    /// against the same source of truth.
    var editorStore: LocalStore { store }

    /// Loads identity, categories, entries, and the all-time total. Called
    /// on appear and after the stacked activity editor dismisses (design D5).
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let loaded = try await store.activity(id: activityID) else {
                activity = nil
                activityIsGone = true
                return
            }
            activity = loaded
            activityIsGone = false

            let allCategories = try await store.categories()
            let resolved = loaded.categoryIDs.compactMap { id in
                allCategories.first { $0.id == id }
            }
            categories = resolved
            icon = resolved.first.map { CatalogIcon(validated: $0.icon).displaySymbol } ?? "questionmark"

            let entries = try await store.entries(activityID: activityID)
            dayGroups = HistoryViewModel.makeDayGroups(entries: entries, now: Date())

            let totalSeconds = try await store.totalDuration(activityID: activityID)
            totalText = HistoryViewModel.detailedDuration(totalSeconds)
        } catch {
            // Keep the last good snapshot; a transient read failure should
            // not blank the sheet (only a missing activity dismisses it).
        }
    }

    // MARK: - Entry-only row presentation (no activity identity)

    /// Start–finish range: bare times when both endpoints share a calendar
    /// day, day-prefixed endpoints when the entry spans midnight
    /// ("Yesterday, 11:34 PM – Today, 0:34 AM").
    func timeRangeText(for entry: TimeEntry) -> String {
        let start = HistoryViewModel.timeText(for: entry.startedAt)
        guard let endedAt = entry.endedAt else {
            return "\(start) – \(L10n.historyInProgress.text)"
        }
        let end = HistoryViewModel.timeText(for: endedAt)
        let calendar = Calendar.current
        guard !calendar.isDate(entry.startedAt, inSameDayAs: endedAt) else {
            return "\(start) – \(end)"
        }
        let now = Date()
        let startDay = HistoryViewModel.dayLabel(for: entry.startedAt, now: now, calendar: calendar)
        let endDay = HistoryViewModel.dayLabel(for: endedAt, now: now, calendar: calendar)
        return "\(startDay), \(start) – \(endDay), \(end)"
    }

    func durationText(for entry: TimeEntry) -> String {
        let seconds = entry.durationSeconds
            ?? max(0, Int(entry.endedAt?.timeIntervalSince(entry.startedAt).rounded() ?? 0))
        return HistoryViewModel.detailedDuration(seconds)
    }

    /// Bare localized source name for the sync-icon provenance; empty for
    /// manual entries.
    func provenanceName(for entry: TimeEntry) -> String {
        EntryProvenance.name(for: entry.source)
    }
}
