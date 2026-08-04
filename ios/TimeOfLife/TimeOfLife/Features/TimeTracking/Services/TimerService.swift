import Foundation

/// Orchestrates local storage and sync for time entries.
///
/// The service is the single entry point for view models. It stores entries
/// locally first via `LocalStore` (GRDB), marks them pending, and triggers the
/// `SyncCoordinator` to push them to the server.
@MainActor
final class TimerService: ObservableObject {
    let localStore: LocalStore?
    let syncCoordinator: SyncCoordinator?
    let legacyStore: TimerStoring?
    private let repository: TimerRepository
    private let connectivity: Connectivity

    /// Initializes the service. The new catalog-based path uses `localStore`
    /// + `syncCoordinator`; the legacy path uses `legacyStore` + `repository`
    /// (kept for backward compatibility during the rewrite transition).
    init(
        repository: TimerRepository,
        connectivity: Connectivity,
        localStore: LocalStore? = nil,
        syncCoordinator: SyncCoordinator? = nil,
        legacyStore: TimerStoring? = nil
    ) {
        self.localStore = localStore
        self.syncCoordinator = syncCoordinator
        self.legacyStore = legacyStore
        self.repository = repository
        self.connectivity = connectivity
    }

    // MARK: - Suggestions

    /// Returns the 5 most recent activities from the local store (F5).
    func suggestions() async throws -> [Activity] {
        guard let localStore else { return [] }
        return Array(try await localStore.activitiesSortedByLastUsedAt().prefix(5))
    }

    // MARK: - Activity resolution

    /// Resolves a free-text activity name: if a `selectedActivityId` exists,
    /// reuse it; otherwise look up by normalized name (case-insensitive); if
    /// no match, auto-create a new activity (F4 / D20).
    /// When `localStore` is nil (legacy path), returns a placeholder activity.
    func resolveActivity(name: String, selectedActivityId: String?) async throws -> Activity {
        guard let localStore else {
            // Legacy path: no LocalStore. Return a placeholder activity so
            // the timer still works without catalog integration.
            return Activity(
                id: selectedActivityId ?? UUIDv7.generate(),
                name: name.trimmingCharacters(in: .whitespaces),
                notes: nil, lastUsedAt: nil,
                createdAt: Date(), updatedAt: Date(),
                categoryIds: [], sync: .adoptedClean()
            )
        }

        // If a suggestion was selected, reuse it.
        if let id = selectedActivityId, let existing = try await localStore.activity(id: id) {
            return existing
        }

        // Case-insensitive reuse.
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let existing = try await localStore.activity(normalizedName: normalized) {
            return existing
        }

        // Auto-create with UUID v7.
        let id = UUIDv7.generate()
        let now = Date()
        let activity = Activity(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            notes: nil,
            lastUsedAt: nil,
            createdAt: now,
            updatedAt: now,
            categoryIds: [],
            sync: .newPending()
        )
        try await localStore.upsertActivity(activity)
        return activity
    }

    // MARK: - Recency

    /// Bumps `last_used_at` locally. No activity PATCH is sent solely for
    /// `last_used_at` — the server updates recency on entry POST.
    func bumpRecencyLocally(activityId: String) async throws {
        guard let localStore else { return }
        guard var activity = try await localStore.activity(id: activityId) else { return }
        activity.lastUsedAt = Date()
        activity.sync.syncStatus = .pending
        activity.sync.localRevision += 1
        try await localStore.upsertActivity(activity)
    }

    // MARK: - Entry save

    /// Saves a completed time entry. Creates a local entry in the GRDB store,
    /// marks it pending, and triggers the `SyncCoordinator` (new path).
    /// Falls back to the legacy path if `localStore` is not configured.
    func saveEntry(activityId: String, duration: TimeInterval, startedAt: Date) async throws {
        let endedAt = startedAt.addingTimeInterval(duration)

        if let localStore, let syncCoordinator {
            // New path: GRDB + SyncCoordinator.
            let id = UUIDv7.generate()
            let now = Date()
            let durationSeconds = duration > 0 ? duration : nil

            let entry = Entry(
                id: id,
                activityId: activityId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                createdAt: now,
                updatedAt: now,
                sync: .newPending()
            )
            try await localStore.upsertEntry(entry)
            await syncCoordinator.sync()
        } else if let legacyStore {
            // Legacy path: TimerStoring + TimerRepository.
            let entry = TimeEntry(
                id: UUID(),
                activityName: activityId,
                startedAt: startedAt,
                endedAt: endedAt,
                synced: false
            )
            try await legacyStore.save(entry)
            guard connectivity.isConnected else { return }
            try await repository.save(entry)
            try await legacyStore.markSynced(entry)
        }
    }

    /// Replays any unsynced entries to the remote repository (legacy path only).
    func syncUnsyncedEntries() async throws {
        guard let legacyStore else { return }
        guard connectivity.isConnected else { return }
        let unsynced = await legacyStore.unsyncedEntries()
        for entry in unsynced {
            try await repository.save(entry)
            try await legacyStore.markSynced(entry)
        }
    }
}
