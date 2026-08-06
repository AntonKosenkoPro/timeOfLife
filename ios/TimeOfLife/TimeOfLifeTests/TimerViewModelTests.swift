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

    @Test("start timer persists running state to the local store")
    func startTimerPersistsState() async throws {
        let vm = makeViewModel()
        vm.activityName = "Coding"
        vm.start()

        try? await Task.sleep(nanoseconds: 50_000_000)

        let state = try await vm.service.store.timerState()
        #expect(state != nil)
        #expect(state?.status == "running")
        #expect(state?.activityName == "Coding")

        vm.reset()
        try await vm.service.store.stopTimer()
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

        let entries = try? await vm.service.store.entries()
        #expect(entries?.count == 1)
        #expect(entries?.first?.source == "manual")
        #expect(entries?.first?.activityName == "Coding")
    }

    @Test("stop timer clears persisted running state")
    func stopTimerClearsState() async throws {
        let vm = makeViewModel()
        vm.activityName = "Reading"
        vm.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        let state = try await vm.service.store.timerState()
        #expect(state == nil)
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

    private func makeViewModel() -> TimerViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
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
            .appendingPathComponent("timeoflife.sqlite")
    }
}
