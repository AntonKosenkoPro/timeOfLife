import Foundation

/// Orchestrates local storage and remote sync for time entries.
///
/// The service is the single entry point for view models. It stores entries
/// locally first, then attempts remote persistence, and finally marks the
/// entry synced. If the remote call fails, the entry remains queued for later
/// sync when connectivity returns.
///
/// POST-at-Stop strategy: the entry is created locally with `endedAt` set and
/// POSTed to the backend as a completed entry (no PATCH-stop needed for the
/// basic flow). The `stop(id:endedAt:updatedAt:)` path is for the running-entry
/// case (Epic 2).
@MainActor
final class TimerService: ObservableObject {
    let store: TimerStoring
    private let repository: EntriesRepository
    private let connectivity: Connectivity

    init(
        store: TimerStoring,
        repository: EntriesRepository,
        connectivity: Connectivity
    ) {
        self.store = store
        self.repository = repository
        self.connectivity = connectivity
    }

    /// Saves a completed time entry. Local persistence is always attempted.
    /// Remote persistence is attempted only when online; offline entries stay
    /// queued for `syncUnsyncedEntries()`.
    func saveEntry(activityId: UUID, duration: TimeInterval, startedAt: Date) async throws {
        let endedAt = startedAt.addingTimeInterval(duration)
        let entry = TimeEntry(
            id: UUID.v7(),
            activityId: activityId,
            startedAt: startedAt,
            endedAt: endedAt,
            synced: false
        )
        try await store.save(entry)
        guard connectivity.isConnected else { return }
        try await repository.create(entry)
        try await store.markSynced(entry)
    }

    /// Replays any unsynced entries to the remote repository.
    func syncUnsyncedEntries() async throws {
        guard connectivity.isConnected else { return }
        let unsynced = await store.unsyncedEntries()
        for entry in unsynced {
            try await repository.create(entry)
            try await store.markSynced(entry)
        }
    }
}
