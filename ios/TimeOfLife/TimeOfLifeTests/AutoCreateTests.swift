import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("AutoCreate")
struct AutoCreateTests {

    // MARK: - Helpers

    private func makeActivity(
        id: UUID = UUID(),
        name: String = "Activity",
        lastUsedAt: Date? = nil
    ) -> Activity {
        Activity(
            id: id,
            name: name,
            notes: nil,
            lastUsedAt: lastUsedAt,
            categoryIds: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeViewModel(
        connected: Bool = true,
        catalogActivities: [Activity] = [],
        catalogRepo: FakeCatalogRepository = FakeCatalogRepository()
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
        let syncQueue = SyncQueue(url: temporaryDirectory())
        let undoBuffer = UndoBuffer()
        let catalogService = CatalogService(
            store: catalogStore,
            repository: catalogRepo,
            syncQueue: syncQueue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )

        // Seed activities synchronously so callers can rely on them.
        for activity in catalogActivities {
            await catalogStore.upsertActivity(activity)
        }

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

    // MARK: - Tests

    @Test("selectedActivityId short-circuits auto-create")
    func selectedActivityIdShortCircuits() async throws {
        let vm = await makeViewModel()
        let activityId = UUID()
        vm.activityName = "Custom"
        vm.selectedActivityId = activityId

        // resolveActivityId should return the selected id directly.
        let resolved = try await vm.resolveActivityId()
        #expect(resolved == activityId)
    }

    @Test("case-insensitive reuse finds existing activity")
    func caseInsensitiveReuse() async throws {
        let existingId = UUID()
        let existing = makeActivity(id: existingId, name: "Reading")
        let vm = await makeViewModel(catalogActivities: [existing])

        vm.activityName = "reading" // different case
        vm.selectedActivityId = nil

        let resolved = try await vm.resolveActivityId()
        #expect(resolved == existingId)
    }

    @Test("auto-create creates an activity when no match is found")
    func autoCreateWithDefaults() async throws {
        let vm = await makeViewModel(catalogActivities: [])
        vm.activityName = "New Activity"
        vm.selectedActivityId = nil

        let resolved = try await vm.resolveActivityId()

        // Should have created a new activity — verify it exists in the store.
        let activity = await vm.catalogStore.activity(named: "New Activity")
        #expect(activity != nil)
        #expect(activity?.id == resolved)
    }

    @Test("409 activity_exists re-maps to the surviving activity id")
    func activityExistsRemapsToSurvivor() async throws {
        let survivorId = UUID()
        let survivor = makeActivity(id: survivorId, name: "Gym")
        let catalogRepo = FakeCatalogRepository()
        catalogRepo.createActivityError = CatalogError.activityExists(
            existingId: survivorId, existingName: "Gym"
        )
        catalogRepo.activityResult = survivor
        let vm = await makeViewModel(
            catalogActivities: [],
            catalogRepo: catalogRepo
        )

        vm.activityName = "Gym"
        vm.selectedActivityId = nil

        let resolved = try await vm.resolveActivityId()

        // The survivor — not the optimistic id — must be returned.
        #expect(resolved == survivorId)
        let stored = await vm.catalogStore.activity(named: "Gym")
        #expect(stored?.id == survivorId)
    }

    @Test("reuse bumps lastUsedAt on the resolved activity")
    func reuseBumpsLastUsedAt() async throws {
        let existingId = UUID()
        let existing = makeActivity(id: existingId, name: "Reading", lastUsedAt: nil)
        let vm = await makeViewModel(catalogActivities: [existing])

        vm.activityName = "reading"
        vm.selectedActivityId = nil

        _ = try await vm.resolveActivityId()

        let stored = await vm.catalogStore.activity(existingId)
        #expect(stored?.lastUsedAt != nil)
    }

    @Test("prefill sets activityName and selectedActivityId")
    func prefillSetsFields() async {
        let vm = await makeViewModel()
        let activity = makeActivity(id: UUID(), name: "Fitness")

        vm.prefill(from: activity)

        #expect(vm.activityName == "Fitness")
        #expect(vm.selectedActivityId == activity.id)
    }

    @Test("equivalent activity name edits preserve the selected activity")
    func equivalentEditsPreserveSelection() async {
        let activity = makeActivity(id: UUID(), name: "Reading")
        let vm = await makeViewModel(catalogActivities: [activity])
        await vm.refreshSuggestions()
        vm.prefill(from: activity)

        vm.activityName = " reading "

        #expect(vm.selectedActivityId == activity.id)
    }

    @Test("reset clears selectedActivityId")
    func resetClearsSelection() async {
        let vm = await makeViewModel()
        vm.selectedActivityId = UUID()
        vm.reset()

        #expect(vm.selectedActivityId == nil)
    }
}
