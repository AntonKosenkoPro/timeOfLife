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

    /// Starts a timer against the given activity, persisting the running
    /// state (D8) so it survives a crash and is readable by widgets and
    /// lock-screen Controls. The activity is created (or reused by
    /// case-insensitive name) in the same transaction as the timer state.
    func startTimer(activityName: String, startedAt: Date = Date()) async throws {
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = try await store.activity(named: name) ?? Activity(
            id: UUID().uuidString.lowercased(),
            name: name,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        if try await store.activity(id: activity.id) == nil {
            try await store.createActivity(activity)
        }
        try await store.startTimer(activityID: activity.id, activityName: activity.name, startedAt: startedAt)
    }

    /// Stops the running timer and saves the completed entry (with
    /// `source='manual'`) in one transaction with its outbox row. Clears the
    /// persisted running state.
    func stopTimer(activityID: String, activityName: String, startedAt: Date, endedAt: Date = Date()) async throws {
        let entry = TimeEntry(
            id: UUID().uuidString.lowercased(),
            activityID: activityID,
            activityName: activityName,
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
