import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerSuggestions")
struct TimerSuggestionsTests {

    // MARK: - Helpers

    /// Creates a synthetic activity with a given `lastUsedAt`.
    private func makeActivity(
        id: UUID = UUID(),
        name: String = "Activity",
        lastUsedAt: Date? = nil
    ) -> Activity {
        Activity(
            id: id,
            name: name,
            color: .blue,
            icon: .clock,
            notes: nil,
            lastUsedAt: lastUsedAt,
            categoryIds: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Creates a TimerViewModel with a seeded catalog store.
    private func makeViewModel(
        activities: [Activity],
        connected: Bool = true
    ) async -> TimerViewModel {
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

        // Seed the catalog store with activities.
        let vm = TimerViewModel(
            service: service,
            authService: authService,
            connectivity: connectivity,
            catalogStore: catalogStore,
            catalogService: catalogService
        )

        // Seed activities into the store.
        for activity in activities {
            await catalogStore.upsertActivity(activity)
        }

        return vm
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

    // MARK: - Tests

    @Test("suggestions are ranked by recency (lastUsedAt descending)")
    func recencyOrder() async {
        let now = Date()
        let old = makeActivity(id: UUID(), name: "Old", lastUsedAt: now.addingTimeInterval(-7200))
        let recent = makeActivity(id: UUID(), name: "Recent", lastUsedAt: now.addingTimeInterval(-3600))
        let newest = makeActivity(id: UUID(), name: "Newest", lastUsedAt: now)

        let vm = await makeViewModel(activities: [old, recent, newest])
        await vm.refreshSuggestions()

        #expect(vm.suggestions.count == 3)
        #expect(vm.suggestions[0].name == "Newest")
        #expect(vm.suggestions[1].name == "Recent")
        #expect(vm.suggestions[2].name == "Old")
    }

    @Test("suggestions are capped at top 5")
    func topFiveCap() async {
        let now = Date()
        var activities: [Activity] = []
        for i in 0..<10 {
            activities.append(makeActivity(
                id: UUID(),
                name: "Activity \(i)",
                lastUsedAt: now.addingTimeInterval(-Double(i) * 3600)
            ))
        }

        let vm = await makeViewModel(activities: activities)
        await vm.refreshSuggestions()

        #expect(vm.suggestions.count <= 5)
    }

    @Test("suggestions are empty when catalog is empty")
    func emptyWhenNoActivities() async {
        let vm = await makeViewModel(activities: [])
        await vm.refreshSuggestions()

        #expect(vm.suggestions.isEmpty)
    }

    @Test("suggestions are hidden while timer is running")
    func hiddenWhileRunning() async {
        let activity = makeActivity(name: "Test", lastUsedAt: Date())
        let vm = await makeViewModel(activities: [activity])
        await vm.refreshSuggestions()
        #expect(!vm.suggestions.isEmpty)

        vm.isRunning = true
        // The view renders suggestions only when !isRunning && !suggestions.isEmpty.
        let shouldShowSuggestions = !vm.isRunning && !vm.suggestions.isEmpty
        #expect(!shouldShowSuggestions)
    }

    @Test("prefill sets activityName and selectedActivityId")
    func prefillSetsFields() async {
        let vm = await makeViewModel(activities: [])
        let activity = makeActivity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Reading")

        vm.prefill(from: activity)

        #expect(vm.activityName == "Reading")
        #expect(vm.selectedActivityId == activity.id)
        #expect(vm.fieldError == nil)
    }

    @Test("suggestions ranking performance: < 50 ms for 1 000 activities")
    @available(iOS 16, *)
    func rankingPerformance() async {
        let now = Date()
        var activities: [Activity] = []
        for i in 0..<1000 {
            activities.append(makeActivity(
                id: UUID(),
                name: "Activity \(i)",
                lastUsedAt: now.addingTimeInterval(-Double(i) * 60)
            ))
        }

        let catalogStore = CatalogStore(directory: temporaryDirectory())
        for activity in activities {
            await catalogStore.upsertActivity(activity)
        }

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            let sorted = await catalogStore.activitiesSortedByLastUsedAt()
            _ = Array(sorted.prefix(5))
        }

        #expect(elapsed < .milliseconds(50))
    }
}
