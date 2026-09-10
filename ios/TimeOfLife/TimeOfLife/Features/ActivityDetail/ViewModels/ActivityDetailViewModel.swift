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
    private let undoBuffer: UndoBufferStore
    private let nowProvider: () -> Date

    init(
        store: LocalStore,
        activityID: String,
        undoBuffer: UndoBufferStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.activityID = activityID
        self.undoBuffer = undoBuffer ?? UndoBufferStore(store: store)
        self.nowProvider = now
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
                // Committed entries only (edit-entry-from-activity-detail):
                // in-progress sessions (no end time) never appear here and
                // never contribute to the total.
                .filter { $0.endedAt != nil }
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

    // MARK: - Entry undo (shake → default confirmation → single restore)

    /// Registers the newest restorable entry deletion with the system Undo
    /// manager, so shaking surfaces the DEFAULT Undo confirmation and
    /// confirming restores exactly one entry (the most recent buffer row).
    /// Previous registrations are cleared first, so one shake+confirm can
    /// never restore two deletions. Offers nothing when the buffer holds
    /// no non-expired entry deletion — including when the newest row
    /// belongs to another surface (U7 supersession: an entry delete
    /// followed by a category delete leaves only the category undoable
    /// here). After the registered undo runs, re-registers when a further
    /// entry deletion is still restorable (one more shake restores one
    /// more), otherwise the surface offers no Undo.
    func registerSystemUndo(with undoManager: UndoManager?) async {
        guard let undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        guard let recent = try? await undoBuffer.mostRecent(),
              (try? await store.entryDeletionSnapshot(bufferID: recent.id)) != nil,
              !recent.isExpired(now: nowProvider()) else { return }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
            Task { @MainActor in
                await target.performUndo()
                await target.registerSystemUndo(with: undoManager)
            }
        }
        // Names the undoable action so the DEFAULT system confirmation
        // states what Confirm will restore (without this the prompt's
        // action slot is empty). Reuses the existing localized Delete
        // string — no new strings, EN+RU already covered (U4).
        undoManager.setActionName(L10n.entryDelete.text)
    }

    /// Restores the most recent entry deletion within the 30 s wall-clock
    /// window (U7). Only entry deletions are restored here — buffer rows
    /// owned by other surfaces are left for their owners. An expired row
    /// commits on the spot so the list never shows a restorable-but-dead
    /// deletion. No toast is shown in this change; the shake gesture is the
    /// only affordance, and one shake restores at most one deletion.
    func performUndo() async {
        do {
            guard let recent = try await undoBuffer.mostRecent() else { return }
            guard try await store.entryDeletionSnapshot(bufferID: recent.id) != nil else { return }
            let now = nowProvider()
            if recent.isExpired(now: now) {
                try? await undoBuffer.commitExpired(now: now)
                await load()
                return
            }
            if try await store.undoEntryDeletion(bufferID: recent.id) != nil {
                await load()
            }
        } catch {
            // Keep the last good snapshot; a transient failure must not
            // blank the sheet (same philosophy as load()).
        }
    }
}
