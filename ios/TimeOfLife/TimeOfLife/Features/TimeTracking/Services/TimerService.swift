import Foundation
import Combine
import OSLog

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
    private static let log = Logger(subsystem: "com.timeoflife", category: "timer-sync")

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
            if !isPermanentError(error) {
                scheduleRetry()
            }
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
                    if let api = error as? APIError,
                       case let .server(code, _, _) = api,
                       code == "validation_error" {
                        Self.log.warning("marking entry \(entry.id.uuidString) syncFailed after validation_error: \(error.localizedDescription)")
                        try? await store.markSyncFailed(entry)
                        continue
                    }
                    if let api = error as? APIError,
                       case let .server(code, _, _) = api,
                       code == "activity_not_found" {
                        let attempts = entry.syncAttempts + 1
                        if attempts >= TimeEntry.maxSyncAttempts {
                            Self.log.warning("marking entry \(entry.id.uuidString) syncFailed after \(attempts) activity_not_found attempts")
                            try? await store.markSyncFailed(entry)
                        } else {
                            Self.log.warning("deferring entry \(entry.id.uuidString) after activity_not_found (attempt \(attempts)/\(TimeEntry.maxSyncAttempts)): \(error.localizedDescription)")
                            try? await store.incrementSyncAttempts(entry)
                        }
                        continue
                    }
                    if isPermanentError(error) {
                        Self.log.warning("deferring entry \(entry.id.uuidString) after permanent error: \(error.localizedDescription)")
                        continue
                    }
                    shouldRetry = true
                    continue
                }
            }
            if shouldRetry { scheduleRetry() }
        } while syncRequested && connectivity.isConnected
    }

    /// Returns true for errors that will never succeed on retry.
    private func isPermanentError(_ error: Error) -> Bool {
        if let api = error as? APIError {
            switch api {
            case .unauthorized:
                return true
            case let .server(code, _, _):
                // 404 activity_not_found: the referenced activity doesn't exist
                // server-side; wait for catalog sync to create it.
                // 422 validation_error: will never succeed.
                return code == "activity_not_found" || code == "validation_error"
            case .offline, .decoding, .transport, .invalidRequest, .unexpected:
                return false
            }
        }
        return false
    }

    /// Cancels any pending retry. Called on logout so the app stops hammering
    /// the backend without a token.
    func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
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
