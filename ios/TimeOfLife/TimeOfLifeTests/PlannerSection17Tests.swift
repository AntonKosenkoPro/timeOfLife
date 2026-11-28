import Testing
import Foundation
@testable import TimeOfLife

/// Day-planner §17: the isolated staged chip renders selected, completed
/// taps never open the editor, the running linked task is never deletable,
/// and submit/chip taps play their haptics. The view consumes
/// `isSelectedChip`, the `deleteDisabled` row modifier, and the conditional
/// swipe button — SwiftUI rendering itself is not unit-testable, so these
/// tests pin the view-model helpers and gates behind them (the
/// `PlannerStartSlot` precedent). Haptic generators never fire headless,
/// so the wiring is verified through the injected `playHaptic` seam.
@MainActor
@Suite("Planner section 17 (selected chip, guards, haptics)")
struct PlannerSection17Tests {
    // MARK: - Selected chip (17.1)

    @Test("the isolated staged chip alone reads selected")
    func isolatedChipReadsSelected() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "gym"
        for recent in vm.chips { #expect(vm.isSelectedChip(recent) == false) }
        let selected = try #require(vm.chips.first { $0.activityText == "Gym" })
        vm.fillFromChip(selected)
        #expect(vm.chips.map(\.activityText) == ["Gym"])
        #expect(vm.isSelectedChip(selected))
    }

    @Test("typing past the staged text drops the selected style")
    func typingResumesUnselected() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        vm.draft = "Gymn"
        for recent in vm.chips { #expect(vm.isSelectedChip(recent) == false) }
    }

    @Test("a retap moves the selection to the new chip")
    func retapMovesSelection() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        let first = try #require(vm.chips.first { $0.activityText == "Gym" })
        let second = try #require(vm.chips.first { $0.activityText == "Gymnastics" })
        vm.fillFromChip(first)
        #expect(vm.isSelectedChip(first))
        vm.fillFromChip(second)
        #expect(vm.isSelectedChip(second))
        #expect(vm.isSelectedChip(first) == false)
    }

    // MARK: - Guards (17.2)

    @Test("tapping a completed task never opens the editor")
    func completedTapIsNoOp() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "Read"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        // The open control: tapping edits.
        vm.beginEdit(task)
        #expect(vm.editingTask?.id == task.id)
        vm.cancelEdit()
        await vm.toggleComplete(task)
        let completed = try #require(vm.snapshot.tasks.first)
        #expect(completed.completedOn != nil)
        let sheetBefore = vm.sheetName
        // The guard: a completed tap leaves the sheet closed with the
        // drafts untouched.
        vm.beginEdit(completed)
        #expect(vm.editingTask == nil)
        #expect(vm.sheetName == sheetBefore)
    }

    @Test("deleting every row spares the running linked task")
    func deleteSkipsRunningLinkedTask() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "First"
        await vm.submit()
        vm.draft = "Second"
        await vm.submit()
        #expect(vm.snapshot.tasks.count == 2)
        let running = try #require(vm.snapshot.tasks.first { $0.name == "First" })
        #expect(await vm.startTask(running))
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.linkedTaskID == running.id)
        // A delete-all gesture (swipe-all plus Edit-mode all) removes
        // everything except the running linked task.
        await vm.delete(at: IndexSet(integersIn: 0 ..< vm.snapshot.tasks.count))
        #expect(vm.snapshot.tasks.map(\.id) == [running.id])
    }

    // MARK: - Haptics (17.3)

    @Test("a chip tap plays the selection haptic")
    func chipTapPlaysSelection() async throws {
        let (vm, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        #expect(recorded.events == [.selection])
    }

    @Test("a valid submit plays the success haptic")
    func validSubmitPlaysSuccess() async throws {
        let (vm, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "Read"
        await vm.submit()
        #expect(recorded.events == [.success])
        #expect(vm.snapshot.tasks.count == 1)
    }

    @Test("an invalid submit plays nothing and keeps the draft")
    func invalidSubmitPlaysNothing() async throws {
        let (vm, recorded) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "   "
        await vm.submit()
        #expect(recorded.events.isEmpty)
        #expect(vm.snapshot.tasks.isEmpty)
        #expect(vm.draft == "   ")
    }

    // MARK: - Helpers

    /// A haptic recorder standing in for the generators (17.3): the
    /// injected `playHaptic` seam appends here instead of firing.
    private final class HapticRecorder {
        var events: [PlannerHaptic] = []
    }

    private func makeContext() async -> (vm: PlannerViewModel, recorded: HapticRecorder) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        _ = try? await store.createCategory(Category(id: "c1", name: "Gym", icon: CatalogIcon.tag.rawValue))
        // Newest-first pool: "Gymnastics" (bare) sorts before "Gym"
        // (tagged c1), so the "gym" prefix matches both.
        _ = try? await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            categoryIDs: ["c1"]
        ))
        _ = try? await store.createEntry(TimeEntry(
            id: "e2", activityText: "Gymnastics",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 2_600), durationSeconds: 600
        ))
        let recorded = HapticRecorder()
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store)
        ) { recorded.events.append($0) }
        return (vm, recorded)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-s17"))
    }
}
