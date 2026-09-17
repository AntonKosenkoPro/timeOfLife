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
    }    /// Atomically creates an activity or resolves an existing identity by
    /// normalized name (unify-activity-preparation-flow spec, decision 6).
    /// The single transactional LocalStore operation replaces the previous
    /// lookup-then-insert race: uniqueness races are translated into
    /// deterministic `existing` outcomes by the store.
    func prepareActivity(
        named name: String,
        notes: String? = nil,
        categoryIDs: [String] = [],
        now: Date = Date()
    ) async throws -> LocalStore.CreateOrResolve {
        try await store.createOrResolveActivity(
            named: name,
            notes: notes,
            categoryIDs: categoryIDs,
            now: now
        )
    }

    /// Starts a timer against the given activity, persisting the running
    /// state (D8) so it survives a crash and is readable by widgets and
    /// lock-screen Controls.
    func startTimer(activityID: String, startedAt: Date = Date()) async throws {
        let activity = try await store.activity(id: activityID)
        try await store.startTimer(
            activityID: activityID,
            activityName: activity?.name ?? "",
            startedAt: startedAt
        )
    }

    /// Stops the running timer and saves the completed entry (with
    /// `source='manual'`) in one transaction with its outbox row. Clears the
    /// persisted running state.
    ///
    /// When the activity is gone (deleted on another device while the timer
    /// ran), the timer state is still cleared but no entry is saved — an
    /// entry for a deleted activity is unrenderable and unpushable — and the
    /// typed `activityDeleted` error lets the caller settle the UI instead of
    /// looping a failing save. Clearing first (rather than only after a
    /// successful save) applies to this path alone; ordinary save failures
    /// keep the existing recoverable behavior.
    func stopTimer(activityID: String, startedAt: Date, endedAt: Date = Date()) async throws {
        guard let activity = try await store.activity(id: activityID) else {
            try await store.stopTimer()
            throw TimerServiceError.activityDeleted
        }
        let entry = TimeEntry(
            id: await store.newRecordID(),
            activityID: activityID,
            activityName: activity.name,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: Int(endedAt.timeIntervalSince(startedAt)),
            source: "manual"
        )
        try await store.createEntry(entry)
        try await store.stopTimer()
    }

    /// The persisted running-timer state, or nil when no timer is running.
    /// Read on app launch to resume the running-timer UI after a crash or
    /// relaunch (local-first-store spec).
    func runningTimerState() async throws -> RunningTimerState? {
        try await store.timerState()
    }
}

/// Typed stop failures so the UI can settle correctly.
enum TimerServiceError: Error, Equatable, Sendable {
    /// The activity was deleted (on another device) while its timer ran: the
    /// session is discarded, not saved. Settling, not retrying, is correct.
    case activityDeleted
}
