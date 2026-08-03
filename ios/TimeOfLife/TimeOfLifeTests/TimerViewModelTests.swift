import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerViewModel")
struct TimerViewModelTests {

    @Test("start fails with empty activity name")
    func startFailsWhenEmpty() async {
        let vm = makeViewModel()
        vm.activityName = "   "
        await vm.start()

        #expect(vm.fieldError == L10n.timerEmptyActivityError.text)
        #expect(!vm.isRunning)
    }

    @Test("start rejects an activity name longer than the catalog limit")
    func startRejectsLongName() async {
        let vm = makeViewModel()
        vm.activityName = String(repeating: "a", count: CatalogValidator.maxName + 1)

        await vm.start()

        #expect(vm.fieldError == CatalogValidator.unifiedNameMessage(
            CatalogValidator.validateName(vm.activityName)
        ))
        #expect(!vm.isRunning)
    }

    @Test("start timer sets running and elapsed to zero")
    func startTimer() async {
        let vm = makeViewModel()
        vm.activityName = "Design"
        vm.selectedActivityId = UUID()
        await vm.start()

        #expect(vm.isRunning)
        #expect(vm.elapsed == 0)
        #expect(vm.fieldError == nil)
        vm.reset()
    }

    @Test("stop timer saves entry and resets form")
    func stopTimerSavesEntry() async {
        let vm = makeViewModel()
        let activityId = UUID()
        vm.activityName = "Coding"
        vm.selectedActivityId = activityId
        await vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        #expect(!vm.isRunning)
        #expect(vm.activityName.isEmpty)

        let unsynced = await vm.service.store.unsyncedEntries()
        #expect(unsynced.isEmpty)
    }

    @Test("offline stop leaves entry unsynced")
    func offlineStopLeavesUnsynced() async {
        let vm = makeViewModel(connected: false)
        let activityId = UUID()
        vm.activityName = "Reading"
        vm.selectedActivityId = activityId
        await vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        #expect(!vm.isRunning)
        let unsynced = await vm.service.store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(unsynced.first?.activityId == activityId)

        vm.reset()
    }

    @Test("reset clears timer state")
    func resetClearsState() async {
        let vm = makeViewModel()
        vm.activityName = "Work"
        vm.selectedActivityId = UUID()
        await vm.start()
        vm.reset()

        #expect(!vm.isRunning)
        #expect(vm.activityName.isEmpty)
        #expect(vm.elapsed == 0)
        #expect(vm.fieldError == nil)
        #expect(vm.selectedActivityId == nil)
    }

    @Test("offline entries replay when connectivity returns")
    func offlineEntriesReplayAfterReconnect() async throws {
        let connectivity = MockConnectivity(connected: false)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        let service = TimerService(store: store, repository: repository, connectivity: connectivity)

        try await service.saveEntry(activityId: UUID(), duration: 1, startedAt: Date())
        connectivity.isConnected = true

        for _ in 0..<20 where repository.calls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(repository.calls.count == 1)
        #expect((await store.unsyncedEntries()).isEmpty)
    }

    @Test("entry replay continues after a failed entry")
    func entryReplayContinuesAfterFailure() async throws {
        let connectivity = MockConnectivity(connected: false)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.transientCreateError = APIError.server(code: "not_found", message: "Not found")
        repository.createFailuresRemaining = 1
        let service = TimerService(store: store, repository: repository, connectivity: connectivity)
        let activityId = UUID()
        let first = TimeEntry(id: UUID.v7(), activityId: activityId, startedAt: Date(), endedAt: Date(), synced: false)
        let second = TimeEntry(id: UUID.v7(), activityId: activityId, startedAt: Date(), endedAt: Date(), synced: false)
        try await store.save(first)
        try await store.save(second)
        connectivity.isConnected = true

        for _ in 0..<20 where repository.calls.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(repository.calls.count == 2)
        #expect((await service.store.unsyncedEntries()).map(\.id) == [first.id])
    }

    @Test("transient entry sync failures retry while connectivity stays online")
    func entryReplayRetriesWithoutConnectivityChange() async throws {
        let connectivity = MockConnectivity(connected: true)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createFailuresRemaining = 1
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        try await store.save(entry)

        try await service.syncUnsyncedEntries()
        for _ in 0..<20 where !(await store.unsyncedEntries()).isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect((await store.unsyncedEntries()).isEmpty)
        #expect(repository.calls.count == 2)
    }

    @Test("activity collision remapping rewrites queued entries")
    func collisionRemappingRewritesQueuedEntries() async throws {
        let store = LocalTimerStore(url: temporaryStoreURL())
        let oldId = UUID()
        let newId = UUID()
        let entry = TimeEntry(id: UUID.v7(), activityId: oldId, startedAt: Date(), endedAt: Date(), synced: false)
        try await store.save(entry)

        try await store.replaceActivityId(from: oldId, to: newId)

        #expect((await store.unsyncedEntries()).first?.activityId == newId)
    }

    @Test("activity entry counter reads locally persisted entries")
    func activityEntryCounter() async throws {
        let store = LocalTimerStore(url: temporaryStoreURL())
        let activityId = UUID()
        try await store.save(
            TimeEntry(id: UUID.v7(), activityId: activityId, startedAt: Date(), endedAt: Date(), synced: true)
        )
        let counter = TimerStoreActivityEntryCounter(store: store)

        #expect(await counter.entryCount(forActivityId: activityId) == 1)
        #expect(await counter.entryCount(forActivityId: UUID()) == 0)
    }

    // MARK: - Permanent error handling

    @Test("validation_error marks entry syncFailed and does not retry")
    func validationErrorMarksFailed() async throws {
        let connectivity = MockConnectivity(connected: false)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createError = APIError.server(code: "validation_error", message: "ended_at must be after started_at")
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        try await store.save(entry)
        connectivity.isConnected = true

        for _ in 0..<20 where repository.calls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let unsynced = await store.unsyncedEntries()
        #expect(unsynced.isEmpty)
        #expect(repository.calls.count == 1)
    }

    @Test("offline error schedules retry and leaves entry unsynced")
    func offlineErrorSchedulesRetry() async throws {
        let connectivity = MockConnectivity(connected: true)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createError = APIError.offline
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        try await store.save(entry)

        try? await service.syncUnsyncedEntries()

        let unsynced = await store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(repository.calls.count == 1)
    }

    @Test("transport error schedules retry and leaves entry unsynced")
    func transportErrorSchedulesRetry() async throws {
        let connectivity = MockConnectivity(connected: true)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createError = APIError.transport(underlying: "timeout")
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        try await store.save(entry)

        try? await service.syncUnsyncedEntries()

        let unsynced = await store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(repository.calls.count == 1)
    }

    @Test("activity_not_found increments attempts and leaves entry unsynced")
    func activityNotFoundLeavesUnsynced() async throws {
        let connectivity = MockConnectivity(connected: false)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createError = APIError.server(code: "activity_not_found", message: "Activity not found")
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        try await store.save(entry)
        connectivity.isConnected = true

        for _ in 0..<20 where repository.calls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let unsynced = await store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(unsynced.first?.syncAttempts == 1)
        #expect(repository.calls.count == 1)
    }

    @Test("activity_not_found marks syncFailed after max attempts")
    func activityNotFoundMaxAttemptsFails() async throws {
        let connectivity = MockConnectivity(connected: false)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        repository.createError = APIError.server(code: "activity_not_found", message: "Activity not found")
        let service = TimerService(
            store: store, repository: repository, connectivity: connectivity, retryDelay: 0
        )
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(),
            synced: false, syncAttempts: TimeEntry.maxSyncAttempts - 1
        )
        try await store.save(entry)
        connectivity.isConnected = true

        for _ in 0..<20 where repository.calls.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let unsynced = await store.unsyncedEntries()
        #expect(unsynced.isEmpty)
        #expect(repository.calls.count == 1)
    }

    @Test("TimeEntry syncFailed defaults to false and round-trips Codable")
    func syncFailedRoundTrip() throws {
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(), synced: false
        )
        #expect(entry.syncFailed == false)
        #expect(entry.syncAttempts == 0)

        let failed = entry.markSyncFailed()
        #expect(failed.syncFailed == true)
        #expect(failed.synced == false)

        let data = try JSONEncoder().encode(failed)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: data)
        #expect(decoded.syncFailed == true)
    }

    @Test("TimeEntry syncAttempts round-trips Codable and increments")
    func syncAttemptsRoundTrip() throws {
        let entry = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(),
            synced: false, syncAttempts: 5
        )
        #expect(entry.syncAttempts == 5)

        let incremented = entry.incrementSyncAttempts()
        #expect(incremented.syncAttempts == 6)

        let data = try JSONEncoder().encode(incremented)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: data)
        #expect(decoded.syncAttempts == 6)
    }

    @Test("TimeEntry markSynced preserves syncFailed")
    func markSyncedPreservesSyncFailed() throws {
        let failed = TimeEntry(
            id: UUID.v7(), activityId: UUID(), startedAt: Date(), endedAt: Date(),
            synced: false, syncFailed: true
        )
        let synced = failed.markSynced()
        #expect(synced.synced == true)
        #expect(synced.syncFailed == true)
    }

    // MARK: - Helpers

    private func makeViewModel(connected: Bool = true) -> TimerViewModel {
        let connectivity = MockConnectivity(connected: connected)
        let store = LocalTimerStore(url: temporaryStoreURL())
        let repository = FakeEntriesRepository()
        let service = TimerService(
            store: store,
            repository: repository,
            connectivity: connectivity
        )
        let authService = AuthService(
            repository: FakeAuthRepository(),
            keychain: InMemoryKeychainStore(),
            cache: SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            sessionStore: SessionStore()
        )
        let catalogStore = CatalogStore(directory: temporaryDirectory())
        let catalogRepo = FakeCatalogRepository()
        let syncQueue = SyncQueue(url: temporaryDirectory())
        let undoBuffer = UndoBuffer()
        let catalogService = CatalogService(
            store: catalogStore,
            repository: catalogRepo,
            syncQueue: syncQueue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        return TimerViewModel(
            service: service,
            authService: authService,
            connectivity: connectivity,
            catalogStore: catalogStore,
            catalogService: catalogService
        )
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timerQueue.json")
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
    }
}
