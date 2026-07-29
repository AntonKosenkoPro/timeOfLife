import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerViewModel")
struct TimerViewModelTests {

    @Test("start fails with empty activity name")
    func startFailsWhenEmpty() {
        let vm = makeViewModel()
        vm.activityName = "   "
        vm.start()

        #expect(vm.fieldError == L10n.timerEmptyActivityError.text)
        #expect(!vm.isRunning)
    }

    @Test("start timer sets running and elapsed to zero")
    func startTimer() {
        let vm = makeViewModel()
        vm.activityName = "Design"
        vm.selectedActivityId = UUID()
        vm.start()

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
        vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        #expect(!vm.isRunning)
        #expect(vm.activityName.isEmpty)
        #expect(vm.didSave)

        let unsynced = await vm.service.store.unsyncedEntries()
        #expect(unsynced.isEmpty)
    }

    @Test("offline stop leaves entry unsynced")
    func offlineStopLeavesUnsynced() async {
        let vm = makeViewModel(connected: false)
        let activityId = UUID()
        vm.activityName = "Reading"
        vm.selectedActivityId = activityId
        vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        #expect(!vm.isRunning)
        let unsynced = await vm.service.store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(unsynced.first?.activityId == activityId)

        vm.reset()
    }

    @Test("reset clears timer state")
    func resetClearsState() {
        let vm = makeViewModel()
        vm.activityName = "Work"
        vm.selectedActivityId = UUID()
        vm.start()
        vm.reset()

        #expect(!vm.isRunning)
        #expect(vm.activityName.isEmpty)
        #expect(vm.elapsed == 0)
        #expect(vm.fieldError == nil)
        #expect(vm.selectedActivityId == nil)
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
