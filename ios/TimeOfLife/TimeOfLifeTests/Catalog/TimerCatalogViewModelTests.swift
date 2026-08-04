import Testing
import Foundation
@testable import TimeOfLife

/// AC10 / Phase 9.3 — TimerViewModel catalog integration tests:
/// auto-create, case-insensitive reuse, suggestions, quick-add, recency.
@MainActor
@Suite("TimerViewModel catalog")
struct TimerCatalogViewModelTests {

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    private func makeViewModel(
        store: LocalStore,
        connected: Bool = true,
        offlineSync: Bool = false
    ) async throws -> (TimerViewModel, TimerService, LocalStore) {
        let connectivity = MockConnectivity(connected: connected)
        // The catalog path in `TimerService.saveEntry` requires both the
        // localStore AND a sync coordinator. Use fakes so the entry is marked
        // pending locally and the coordinator is triggered.
        let catalog = FakeCatalogRepository()
        let entries = FakeEntriesRepository()
        if offlineSync {
            // Simulate offline: the entry POST fails so the entry stays
            // pending (durable, not dropped).
            entries.createEntryError = { _ in APIError.offline }
        }
        let coordinator = SyncCoordinator(
            localStore: store, catalogRepo: catalog,
            entriesRepo: entries, connectivity: connectivity)
        let service = TimerService(
            repository: StubTimerRepository(),
            connectivity: connectivity,
            localStore: store,
            syncCoordinator: coordinator
        )
        let authService = AuthService(
            repository: FakeAuthRepository(),
            keychain: InMemoryKeychainStore(),
            cache: SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            sessionStore: SessionStore()
        )
        let vm = TimerViewModel(
            service: service, authService: authService, connectivity: connectivity)
        return (vm, service, store)
    }

    // MARK: - Auto-create / reuse

    @Test("start with free text auto-creates a pending activity")
    func startAutoCreatesActivity() async throws {
        let store = try makeStore()
        let (vm, _, storeChecked) = try await makeViewModel(store: store)
        vm.activityName = "Meditation"

        await vm.start()

        #expect(vm.isRunning)
        let activities = try await storeChecked.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
        #expect(activities.first?.name == "Meditation")
        #expect(activities.first?.sync.syncStatus == .pending)
        #expect(activities.first?.sync.remoteKnown == false)
        // Selected activity id set.
        #expect(vm.selectedActivityId == activities.first?.id)
        vm.reset()
    }

    @Test("start reuses existing activity by case-insensitive name")
    func startReusesExisting() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Reading", sync: .adoptedClean()))
        let (vm, _, storeChecked) = try await makeViewModel(store: store)
        vm.activityName = "  READING  "

        await vm.start()

        let activities = try await storeChecked.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1) // No new activity created.
        #expect(vm.selectedActivityId == "a1")
        vm.reset()
    }

    @Test("start bumps local recency of the used activity")
    func startBumpsRecency() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Reading",
            lastUsedAt: CatalogTestFactory.date(offset: -3600),
            sync: .adoptedClean()))
        let (vm, _, _) = try await makeViewModel(store: store)
        vm.activityName = "Reading"

        await vm.start()

        let activity = try await store.activity(id: "a1")
        #expect(activity?.lastUsedAt != nil)
        // Recency is newer than the original.
        #expect(activity?.lastUsedAt ?? .distantPast > CatalogTestFactory.date(offset: -3600))
        vm.reset()
    }

    // MARK: - Suggestions

    @Test("loadSuggestions returns top 5 by last_used_at")
    func loadSuggestionsTopFive() async throws {
        let store = try makeStore()
        let base = CatalogTestFactory.date()
        for index in 0..<7 {
            try await store.upsertActivity(CatalogTestFactory.makeActivity(
                id: "a\(index)",
                name: "Activity \(index)",
                lastUsedAt: base.addingTimeInterval(TimeInterval(index)),
                sync: .adoptedClean()))
        }
        let (vm, _, _) = try await makeViewModel(store: store)

        await vm.loadSuggestions()

        #expect(vm.suggestions.count == 5)
        // Most recent first: a6, a5, a4, a3, a2.
        #expect(vm.suggestions.map(\.id) == ["a6", "a5", "a4", "a3", "a2"])
    }

    @Test("selectSuggestion prefills name and sets selected id")
    func selectSuggestionPrefills() async throws {
        let store = try makeStore()
        let (vm, _, _) = try await makeViewModel(store: store)
        let activity = CatalogTestFactory.makeActivity(id: "a1", name: "Reading")

        vm.selectSuggestion(activity)

        #expect(vm.activityName == "Reading")
        #expect(vm.selectedActivityId == "a1")
    }

    @Test("start with selected suggestion reuses that activity")
    func startUsesSelectedSuggestion() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Reading", sync: .adoptedClean()))
        let (vm, _, storeChecked) = try await makeViewModel(store: store)
        let activity = try await store.activity(id: "a1")!
        vm.selectSuggestion(activity)

        await vm.start()

        let activities = try await storeChecked.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
        #expect(vm.selectedActivityId == "a1")
        vm.reset()
    }

    // MARK: - Quick-add

    @Test("didSelectNewActivity selects the new activity on the timer")
    func didSelectNewActivity() async throws {
        let store = try makeStore()
        let (vm, _, _) = try await makeViewModel(store: store)
        let newActivity = CatalogTestFactory.makeActivity(id: "a1", name: "Yoga")

        vm.didSelectNewActivity(newActivity)

        #expect(vm.activityName == "Yoga")
        #expect(vm.selectedActivityId == "a1")
    }

    // MARK: - Stop + entry save (catalog path)

    @Test("stop saves a completed pending entry via LocalStore")
    func stopSavesEntry() async throws {
        let store = try makeStore()
        // Offline sync: the entry POST fails, so the entry must remain
        // pending and durable (never dropped).
        let (vm, _, storeChecked) = try await makeViewModel(store: store, offlineSync: true)
        vm.activityName = "Coding"
        await vm.start()
        let startedActivityId = vm.selectedActivityId
        // Let the timer run briefly so duration > 0.
        try? await Task.sleep(nanoseconds: 20_000_000)

        await vm.stop()

        #expect(vm.didSave)
        #expect(!vm.isRunning)
        let pending = try await storeChecked.pendingEntries()
        #expect(pending.createsUpdates.count == 1)
        #expect(pending.createsUpdates.first?.activityId == startedActivityId)
        // endedAt must be set (completed entry).
        #expect(pending.createsUpdates.first?.endedAt != nil)
        vm.reset()
    }

    @Test("start validation rejects empty name before any store access")
    func startRejectsEmpty() async throws {
        let store = try makeStore()
        let (vm, _, storeChecked) = try await makeViewModel(store: store)
        vm.activityName = "  "

        await vm.start()

        #expect(!vm.isRunning)
        #expect(vm.fieldError == L10n.timerEmptyActivityError.text)
        #expect(try await storeChecked.activitiesSortedByLastUsedAt().isEmpty)
    }
}
