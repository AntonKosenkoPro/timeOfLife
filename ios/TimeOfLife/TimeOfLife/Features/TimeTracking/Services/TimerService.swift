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

    /// Returns the activity with the given id, creating it (categoryless) if
    /// it does not exist. Used by the Track chooser's create flow.
    func ensureActivity(id: String, name: String, createdAt: Date = Date()) async throws -> Activity {
        if let existing = try await store.activity(id: id) {
            return existing
        }
        let activity = Activity(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try await store.createActivity(activity)
        return activity
    }

    /// Returns the activity with the given name, creating it (categoryless)
    /// if it does not exist. Case-insensitive reuse: an existing activity with
    /// the same trimmed name is returned instead of creating a duplicate.
    func ensureActivity(named name: String, createdAt: Date = Date()) async throws -> Activity {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try await store.activity(named: trimmed) {
            return existing
        }
        let activity = Activity(
            id: UUID().uuidString.lowercased(),
            name: trimmed,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try await store.createActivity(activity)
        return activity
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
    func stopTimer(activityID: String, startedAt: Date, endedAt: Date = Date()) async throws {
        let activity = try await store.activity(id: activityID)
        let entry = TimeEntry(
            id: UUID().uuidString.lowercased(),
            activityID: activityID,
            activityName: activity?.name ?? "",
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
