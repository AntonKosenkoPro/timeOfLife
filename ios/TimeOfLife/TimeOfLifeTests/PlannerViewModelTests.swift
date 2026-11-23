import Testing
import Foundation
@testable import TimeOfLife

/// Day-planner view model (day-planner spec D4/D6): serialized actions,
/// loading/empty/failure states, durable-write feedback, preserved failed
/// input, retry, and account-generation fencing. Reads never ride the launch
/// `TrackSnapshot` — the VM is created lazily by the sheet.
@MainActor
@Suite("PlannerViewModel")
struct PlannerViewModelTests {

    private func makeStore(userID: String = "vm-u1") throws -> LocalStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: userID))
        return try LocalStore(url: url, userID: userID)
    }

    private func makeViewModel(store: LocalStore? = nil) throws -> (PlannerViewModel, LocalStore) {
        let resolved = try store ?? makeStore()
        return (PlannerViewModel(store: resolved), resolved)
    }

    @Test("open loads an empty checklist as loaded")
    func openLoadsEmpty() async throws {
        let (vm, _) = try makeViewModel()
        #expect(vm.phase == .loading)
        await vm.open()
        #expect(vm.phase == .loaded)
        #expect(vm.tasks.isEmpty)
        #expect(vm.canInteract)
    }

    @Test("add creates a task, clears the field, and keeps order")
    func addClearsField() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "  Gym  "
        await vm.add()
        #expect(vm.inputText.isEmpty)
        #expect(vm.tasks.map(\.text) == ["Gym"])
        vm.inputText = "Read"
        await vm.add()
        #expect(vm.tasks.map(\.text) == ["Gym", "Read"])
    }

    @Test("add allows duplicate text as independent tasks")
    func addDuplicateText() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        vm.inputText = "Gym"
        await vm.add()
        #expect(vm.tasks.count == 2)
        #expect(vm.tasks[0].id != vm.tasks[1].id)
    }

    @Test("invalid add preserves input with an explanation")
    func invalidAddPreservesInput() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "   "
        await vm.add()
        #expect(vm.inputText == "   ")
        #expect(vm.tasks.isEmpty)
        #expect(vm.errorMessage != nil)
        vm.inputText = String(repeating: "x", count: 61)
        await vm.add()
        #expect(vm.tasks.isEmpty)
        #expect(vm.errorMessage != nil)
        // A later valid add recovers without a retry round-trip.
        vm.inputText = "Gym"
        await vm.add()
        #expect(vm.tasks.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("consecutive adds keep the sheet interactive for rapid entry")
    func consecutiveAddsStayInteractive() async throws {
        // The automatable half of the Enter-keeps-focus rule (the SwiftUI
        // FocusState half needs a device): after every submit — success or
        // failure — the sheet stays loaded and interactive for the next
        // task instead of stalling in a failed or mutating state.
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        #expect(vm.phase == .loaded)
        #expect(vm.canInteract)
        #expect(vm.errorMessage == nil)
        vm.inputText = "   "
        await vm.add()
        #expect(vm.phase == .loaded)
        #expect(vm.canInteract)
        #expect(vm.inputText == "   ")
        vm.inputText = "Read"
        await vm.add()
        #expect(vm.tasks.map(\.text) == ["Gym", "Read"])
        #expect(vm.phase == .loaded)
        #expect(vm.canInteract)
    }

    @Test("toggle flips completion without reordering")
    func toggleKeepsOrder() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        vm.inputText = "Read"
        await vm.add()
        let first = vm.tasks[0]
        await vm.toggle(first)
        #expect(vm.tasks[0].id == first.id)
        #expect(vm.tasks[0].isCompleted)
        await vm.toggle(vm.tasks[0])
        #expect(!vm.tasks[0].isCompleted)
    }

    @Test("cancelled removal preserves the task")
    func cancelRemovalPreserves() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        vm.pendingRemoval = vm.tasks[0]
        vm.cancelRemoval()
        #expect(vm.pendingRemoval == nil)
        #expect(vm.tasks.count == 1)
    }

    @Test("confirmed removal deletes only that task")
    func confirmRemovalDeletesOne() async throws {
        let (vm, _) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        vm.inputText = "Read"
        await vm.add()
        await vm.confirmRemoval(vm.tasks[0])
        #expect(vm.tasks.map(\.text) == ["Read"])
        #expect(vm.pendingRemoval == nil)
    }

    @Test("open prunes prior-day completed rows before publishing")
    func openPrunesCompleted() async throws {
        let store = try makeStore()
        let old = try await store.addPlannerTask(text: "Old", expectedUserID: "vm-u1")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let yesterday = calendar.date(byAdding: .day, value: -2, to: Date())!
        _ = try await store.setPlannerTaskCompleted(
            id: old.id, completed: true, expectedUserID: "vm-u1", now: yesterday)
        _ = try await store.addPlannerTask(text: "Todo", expectedUserID: "vm-u1")
        let vm = PlannerViewModel(store: store)
        await vm.open()
        #expect(vm.phase == .loaded)
        #expect(vm.tasks.map(\.text) == ["Todo"])
    }

    @Test("suspended open fails without clearing, retry recovers after resume")
    func suspendRetryCycle() async throws {
        let (vm, store) = try makeViewModel()
        _ = try await store.addPlannerTask(text: "Gym", expectedUserID: "vm-u1")
        DatabaseSuspension.shared.noteSuspended()
        if DatabaseSuspension.shared.isSuspended {
            defer {
                if DatabaseSuspension.shared.isSuspended {
                    DatabaseSuspension.shared.noteResumed()
                }
            }
            await vm.open()
            // The last snapshot (empty on first open) stands with a retry
            // path — never a cleared list presented as success.
            #expect(vm.phase == .failed)
            #expect(vm.tasks.isEmpty)
            #expect(vm.errorMessage != nil)
            DatabaseSuspension.shared.noteResumed()
            await vm.retry()
            #expect(vm.phase == .loaded)
            #expect(vm.tasks.map(\.text) == ["Gym"])
        }
    }

    @Test("operations after account loss fail without publishing")
    func accountLossFencesMutations() async throws {
        let (vm, store) = try makeViewModel()
        await vm.open()
        vm.inputText = "Gym"
        await vm.add()
        #expect(vm.tasks.count == 1)
        // Sign-out releases the binding; the open generation is now stale.
        await store.closeAccount()
        let survivor = vm.tasks[0]
        await vm.toggle(survivor)
        #expect(vm.tasks.count == 1)
        #expect(!vm.tasks[0].isCompleted)
        #expect(vm.errorMessage != nil)
        vm.inputText = "Read"
        await vm.add()
        #expect(vm.inputText == "Read")
        #expect(vm.tasks.count == 1)
    }
}
