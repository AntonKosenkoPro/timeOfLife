import Foundation
import Combine

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
    private let retryDelay: TimeInterval
    private var connectivityCancellable: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var isSyncing = false
    private var syncRequested = false

    init(
        store: TimerStoring,
        repository: EntriesRepository,
        connectivity: Connectivity,
        retryDelay: TimeInterval = 5
    ) {
        self.store = store
        self.repository = repository
        self.connectivity = connectivity
        self.retryDelay = retryDelay
        connectivityCancellable = connectivity.$isConnected
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in
                    try? await self?.syncUnsyncedEntries()
                }
            }
        if connectivity.isConnected {
            Task { @MainActor [weak self] in
                try? await self?.syncUnsyncedEntries()
            }
        }
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
        do {
            try await repository.create(entry)
            try await store.markSynced(entry)
        } catch {
            scheduleRetry()
            throw error
        }
    }

    /// Replays any unsynced entries to the remote repository.
    func syncUnsyncedEntries() async throws {
        guard connectivity.isConnected else { return }
        guard !isSyncing else {
            syncRequested = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncRequested = false
            let unsynced = await store.unsyncedEntries()
            var shouldRetry = false
            for entry in unsynced {
                do {
                    try await repository.create(entry)
                    try await store.markSynced(entry)
                } catch {
                    shouldRetry = true
                    continue
                }
            }
            if shouldRetry { scheduleRetry() }
        } while syncRequested && connectivity.isConnected
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.retryDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.retryTask = nil
            try? await self.syncUnsyncedEntries()
        }
    }

    deinit {
        retryTask?.cancel()
    }
}
