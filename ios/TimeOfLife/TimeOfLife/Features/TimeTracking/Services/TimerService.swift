import Foundation

/// Orchestrates the timer against the local database (local-first-store spec).
///
/// The service is the single entry point for view models. It writes only to
/// `LocalStore` — the device is the source of truth. Remote propagation is the
/// responsibility of the background `SyncController` (the outbox row is
/// written in the same transaction as the state change), so there is no
/// remote-push path here.
@MainActor
final class TimerService: ObservableObject {
    let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    /// Starts (or rewrites) the persisted running draft for the given
    /// trimmed text and ordered category snapshot (D3/D4) so it survives a
    /// crash and is readable by widgets and lock-screen Controls.
    func startTimerDraft(text: String, categoryIDs: [String], startedAt: Date = Date()) async throws {
        try await store.saveTimerDraft(activityText: text, categoryIDs: categoryIDs, startedAt: startedAt)
    }

    /// The persisted running-timer draft, or nil when no timer is running.
    /// Read on app launch to resume the running-timer UI after a crash or
    /// relaunch (local-first-store spec).
    func runningTimerDraft() async throws -> RunningTimerDraft? {
        try await store.timerDraft()
    }

    /// Stops the running timer: saves the completed entry (with
    /// `source='manual'`, empty notes) in one transaction with its single
    /// outbox row and clears the persisted running draft. Category ids that
    /// vanished mid-run (deleted elsewhere while timing) are pruned with the
    /// remainder kept — a stop never fails on a dead tag.
    func stopTimerDraft(text: String, categoryIDs: [String], startedAt: Date, endedAt: Date = Date()) async throws {
        let existing = Set(try await store.categories().map(\.id))
        let pruned = categoryIDs.filter { existing.contains($0) }
        let entry = TimeEntry(
            id: await store.newRecordID(),
            activityText: text,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: Int(endedAt.timeIntervalSince(startedAt)),
            source: "manual",
            categoryIDs: pruned,
            notes: ""
        )
        try await store.createEntry(entry)
        try await store.clearTimerDraft()
    }
}
