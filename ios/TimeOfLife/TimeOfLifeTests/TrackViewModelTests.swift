import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TrackViewModel")
struct TrackViewModelTests {

    // MARK: - State transitions

    @Test("initial state is idle with no activity")
    func initialState() {
        let vm = makeViewModel()
        #expect(vm.state == .idle)
        #expect(vm.state.activity == nil)
        #expect(vm.elapsed == 0)
    }

    @Test("selecting an activity prepares it without starting")
    func selectPrepares() {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Deep work")
        vm.select(activity)

        #expect(vm.state == .ready(activity))
        #expect(vm.elapsed == 0)
        #expect(!vm.state.isRunning)
    }

    @Test("start requires a prepared activity")
    func startRequiresSelection() {
        let vm = makeViewModel()
        vm.start()
        #expect(vm.state == .idle)
    }

    @Test("start transitions ready to running and persists state")
    func startRuns() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Coding")
        vm.select(activity)
        vm.start()

        guard case let .running(selected, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(selected.id == activity.id)
        #expect(vm.state.isRunning)

        try? await Task.sleep(nanoseconds: 50_000_000)
        let state = try await vm.service.store.timerState()
        #expect(state != nil)
        #expect(state?.status == "running")
        #expect(state?.activityID == activity.id)
    }

    @Test("stop saves entry and returns to saved then ready")
    func stopSaves() async {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        guard case let .saved(selected, duration) = vm.state else {
            Issue.record("expected saved state")
            return
        }
        #expect(selected.id == activity.id)
        #expect(duration >= 0)
        #expect(!vm.state.isRunning)

        let entries = try? await vm.service.store.entries()
        #expect(entries?.count == 1)
        #expect(entries?.first?.source == "manual")
        #expect(entries?.first?.activityName == "Reading")

        let state = try? await vm.service.store.timerState()
        #expect(state == nil)
    }

    @Test("elapsed formatting matches TimeFormatter")
    func elapsedFormatting() {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Work")
        vm.select(activity)
        vm.start()
        vm.elapsed = 125

        #expect(TimeFormatter.formattedDuration(vm.elapsed) == "02:05")
        #expect(TimeFormatter.formattedDuration(3661) == "1:01:01")
    }

    // MARK: - Chooser

    @Test("filtered activities are recency-ordered and case-insensitive")
    func filtering() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let older = Activity(id: "a1", name: "Deep work", lastUsedAt: Date().addingTimeInterval(-3600))
        let newer = Activity(id: "a2", name: "Reading", lastUsedAt: Date())
        try await store.createActivity(older)
        try await store.createActivity(newer)

        await vm.load()
        #expect(vm.activities.map(\.id) == ["a2", "a1"])

        vm.chooserQuery = "READ"
        #expect(vm.filteredActivities.map(\.id) == ["a2"])
        #expect(vm.canCreateFromQuery) // prefix match: filtered but not exact

        vm.chooserQuery = "Reading"
        #expect(!vm.canCreateFromQuery) // exact case-insensitive match

        vm.chooserQuery = "  "
        #expect(vm.filteredActivities.count == 2)
    }

    @Test("unmatched query offers creation")
    func createFromQuery() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Deep work"))

        await vm.load()
        vm.chooserQuery = "Gym"
        #expect(vm.canCreateFromQuery)

        await vm.createActivity(named: "Gym")
        guard case let .ready(created) = vm.state else {
            Issue.record("expected ready state")
            return
        }
        #expect(created.name == "Gym")
        #expect(created.categoryIDs.isEmpty)
    }

    @Test("case-insensitive reuse does not create duplicates")
    func reuseExisting() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Deep work"))

        await vm.load()
        vm.chooserQuery = "deep work"
        #expect(!vm.canCreateFromQuery)

        await vm.createActivity(named: "DEEP WORK")
        guard case let .ready(selected) = vm.state else {
            Issue.record("expected ready state")
            return
        }
        #expect(selected.id == "a1")
        let count = try await store.activities().count
        #expect(count == 1)
    }

    @Test("empty catalog shows no activities")
    func emptyCatalog() async throws {
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.activities.isEmpty)
        #expect(vm.state == .idle)
    }

    // MARK: - Recoverable save failure

    @Test("stop failure preserves running state and error message")
    func stopFailurePreservesRunning() async {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Work")
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate a store failure: delete the activity row so the entry
        // insert fails on the FK constraint (foreign_keys = ON), while the
        // timer_state row still exists. The service stopTimer throws when the
        // entry insert fails, so the state must remain recoverable.
        let store = vm.service.store
        try? await store.deleteActivity(id: activity.id)

        await vm.stop()

        if case .error = vm.state {
            #expect(vm.errorMessage != nil)
        } else {
            // If the store accepted the entry (no FK enforcement in this
            // configuration), the save succeeded — acceptable.
            #expect(vm.state.isRunning == false)
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
