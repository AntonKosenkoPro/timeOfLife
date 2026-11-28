import Testing
import Foundation
@testable import TimeOfLife

/// Launch-gate planner preload (timer-capture-experience 12.3): with warm
/// local data the gate resolves the Today projection before the shell
/// mounts, and `PlannerViewModel.adopt` paints it without re-querying — so
/// Track's progress control shows actual counts on first paint, never a
/// 0/0 flash. A fresh view model with no adopt still starts at 0/0 (the
/// recorded pre-fix flash: nothing reloaded the planner snapshot before
/// the first tab-return, foreground return, or sync-cycle exit).
@MainActor
@Suite("Planner launch preload (timer-capture-experience 12.3)")
struct PlannerPreloadTests {

    @Test("fresh view model starts at 0/0")
    func freshStartsEmpty() async throws {
        let (vm, _) = await makeContext()
        #expect(vm.snapshot.done == 0)
        #expect(vm.snapshot.total == 0)
    }

    @Test("adopt paints actual counts without loading")
    func adoptPaintsActualCounts() async throws {
        let (vm, store) = await makeContext()
        let today = PlannerCivilDate.today()
        _ = try await store.createPlannerTask(
            id: "p1", name: "Alpha", positionKey: "500000", operationID: UUID().uuidString
        )
        _ = try await store.createPlannerTask(
            id: "p2", name: "Beta", positionKey: "500001", operationID: UUID().uuidString
        )
        _ = try await store.createPlannerTask(
            id: "p3", name: "Gamma", positionKey: "500002", operationID: UUID().uuidString
        )
        _ = try await store.completePlannerTask(
            id: "p3", completedOn: today, operationID: UUID().uuidString
        )
        // Recents and a run ride the same bundle (chips and Start gating
        // match `load()` exactly).
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Reading",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        ))
        _ = try await TimerService(store: store).startTimerDraft(
            text: "Running", categoryIDs: [], startedAt: Date()
        )

        let preloaded = try await PlannerViewModel.preload(store: store)
        vm.adopt(preloaded)

        // Actual counts on first paint — no `loadIfNeeded` ran.
        #expect(vm.snapshot.done == 1)
        #expect(vm.snapshot.total == 3)
        #expect(vm.snapshot.tasks.map(\.name) == ["Alpha", "Beta", "Gamma"])
        #expect(vm.timerActive)
        #expect(vm.chips.map(\.activityText) == ["Reading"])
        // Later reloads still converge (invalidate → load), so the gate
        // adopt never wedges the tab-return/sync-exit paths.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.snapshot.done == 1)
        #expect(vm.snapshot.total == 3)
    }

    // MARK: - Helpers

    private func makeContext() async -> (vm: PlannerViewModel, store: LocalStore) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store)
        )
        return (vm, store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-preload"))
    }
}
