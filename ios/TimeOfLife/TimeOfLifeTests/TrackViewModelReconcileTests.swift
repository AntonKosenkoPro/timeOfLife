import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TrackViewModel External Stop")
struct TrackViewModelReconcileTests {

    // MARK: - External stop reconciliation (compact-timer stop)

    @Test("load reconciles a running state whose timer was stopped elsewhere")
    func externalStopReconcilesToReady() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .running = vm.state else {
            Issue.record("expected running state")
            return
        }

        // External stop (the compact-timer path): the same service call the
        // shell makes — entry saved, timer_state cleared, Track untouched.
        let store = vm.service.store
        let persisted = try #require(try await store.timerState())
        try await vm.service.stopTimer(
            activityID: persisted.activityID ?? activity.id,
            startedAt: persisted.startedAt ?? Date(),
            endedAt: Date()
        )
        vm.elapsed = 42

        await vm.load()

        guard case let .ready(resolved) = vm.state else {
            Issue.record("expected ready state after reconcile")
            return
        }
        #expect(resolved.id == activity.id)
        #expect(vm.elapsed == 0)
        #expect(!vm.state.isRunning)
    }

    @Test("load reconciles to idle when the running activity is gone")
    func externalStopMissingActivityReconcilesToIdle() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .running = vm.state else {
            Issue.record("expected running state")
            return
        }

        // The activity is deleted while the timer row still exists: the
        // persisted timer is unresolvable, so Track must settle to idle.
        try await vm.service.store.deleteActivity(id: activity.id)

        await vm.load()

        #expect(vm.state == .idle)
        #expect(vm.elapsed == 0)
    }

    @Test("load keeps running when the persisted timer still exists")
    func loadKeepsRunning() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.load()

        guard case let .running(selected, _) = vm.state else {
            Issue.record("expected running state to survive reload")
            return
        }
        #expect(selected.id == activity.id)
        #expect(vm.state.isRunning)
    }

    @Test("load does not clobber a saved confirmation")
    func loadKeepsSaved() async {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try? await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        await vm.stop()
        guard case .saved = vm.state else {
            Issue.record("expected saved state")
            return
        }

        await vm.load()

        guard case .saved = vm.state else {
            Issue.record("expected saved state to survive reload")
            return
        }
    }

    // MARK: - Helpers

    private func makeViewModel() -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return TrackViewModel(service: service, connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
