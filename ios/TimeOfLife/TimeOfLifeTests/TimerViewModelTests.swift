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
        vm.start()

        #expect(vm.isRunning)
        #expect(vm.elapsed == 0)
        #expect(vm.fieldError == nil)
        vm.reset()
    }

    @Test("stop timer saves entry and resets form")
    func stopTimerSavesEntry() async {
        let vm = makeViewModel()
        vm.activityName = "Coding"
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
        vm.activityName = "Reading"
        vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        #expect(!vm.isRunning)
        let unsynced = await vm.service.store.unsyncedEntries()
        #expect(unsynced.count == 1)
        #expect(unsynced.first?.activityName == "Reading")

        vm.reset()
    }

    @Test("reset clears timer state")
    func resetClearsState() {
        let vm = makeViewModel()
        vm.activityName = "Work"
        vm.start()
        vm.reset()

        #expect(!vm.isRunning)
        #expect(vm.activityName.isEmpty)
        #expect(vm.elapsed == 0)
        #expect(vm.fieldError == nil)
    }

    // MARK: - Helpers

    private func makeViewModel(connected: Bool = true) -> TimerViewModel {
        let connectivity = MockConnectivity(connected: connected)
        let service = TimerService(
            store: LocalTimerStore(url: temporaryStoreURL()),
            repository: StubTimerRepository(),
            connectivity: connectivity
        )
        let authService = AuthService(
            repository: FakeAuthRepository(),
            keychain: InMemoryKeychainStore(),
            cache: SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            sessionStore: SessionStore()
        )
        return TimerViewModel(service: service, authService: authService, connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timerQueue.json")
    }
}
