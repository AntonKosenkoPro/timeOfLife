import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("Planner view model (day-planner 3.1/3.2)")
struct PlannerViewModelTests {
    // MARK: - Composer

    @Test("submit prepends one task, clears the draft, and keeps order")
    func submitPrepends() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "Read"
        await vm.submit()
        #expect(vm.draft.isEmpty)
        #expect(vm.snapshot.tasks.map(\.name) == ["Read"])
        #expect(vm.snapshot.total == 1)
        #expect(vm.snapshot.done == 0)
        #expect(try await store.plannerTasks().count == 1)
    }

    @Test("invalid submissions prepend nothing and keep the draft")
    func invalidSubmitKeepsDraft() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "   "
        await vm.submit()
        #expect(vm.draft == "   ")
        #expect(try await store.plannerTasks().isEmpty)
        vm.draft = String(repeating: "x", count: 61)
        await vm.submit()
        #expect(try await store.plannerTasks().isEmpty)
    }

    @Test("consecutive Returns prepend in reverse submission order")
    func consecutiveSubmits() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "First"
        await vm.submit()
        vm.draft = "Second"
        await vm.submit()
        #expect(vm.draft.isEmpty)
        #expect(vm.snapshot.tasks.map(\.name) == ["Second", "First"])
        // The top row holds the smallest key (the projection sorts by
        // `(positionKey, id)`), so prepending stays on top after reloads.
        let keys = vm.snapshot.tasks.map(\.positionKey)
        #expect(keys == keys.sorted())
    }

    // MARK: - Chips (8.2: a single line above the keyboard — tap fills)

    @Test("chips filter newest-first and fill without submitting")
    func chipsFill() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        // Committed entries feed the chip pool (local Recents).
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Reading",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        ))
        _ = try await store.createEntry(TimeEntry(
            id: "e2", activityText: "Read docs",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 2_600), durationSeconds: 600
        ))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.draft = "read"
        let chips = vm.chips
        #expect(chips.map(\.activityText) == ["Read docs", "Reading"])
        vm.fillFromChip(chips[0])
        #expect(vm.draft == "Read docs")
        #expect(vm.snapshot.total == 0)
        #expect(try await store.plannerTasks().isEmpty)
    }

    @Test("empty draft shows the full capped strip")
    func emptyDraftShowsFullStrip() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        for index in 0..<7 {
            _ = try await store.createEntry(TimeEntry(
                id: "e\(index)", activityText: "Entry \(index)",
                startedAt: Date(timeIntervalSinceReferenceDate: Double(1_000 + index * 100)),
                endedAt: Date(timeIntervalSinceReferenceDate: Double(1_600 + index * 100)), durationSeconds: 600
            ))
        }
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.draft = ""
        // Newest-first, capped at the display cap even with no filter.
        #expect(vm.chips.map(\.activityText) == (2...6).reversed().map { "Entry \($0)" })
        #expect(vm.chips.count == PlannerViewModel.chipDisplayCap)
        vm.draft = "   "
        #expect(vm.chips.map(\.activityText) == (2...6).reversed().map { "Entry \($0)" })
    }

    // MARK: - Checklist

    @Test("toggle completes in place and reopens at the same position")
    func toggleComplete() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        vm.draft = "B"
        await vm.submit()
        // Prepend order: the newest ("B") sits on top.
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
        let first = try #require(vm.snapshot.tasks.first)
        await vm.toggleComplete(first)
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
        #expect(vm.snapshot.done == 1)
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        #expect(vm.snapshot.done == 0)
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
    }

    @Test("rename keeps position and empty renames revert")
    func renameKeepsPosition() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        vm.beginRename(task)
        vm.editText = "Zed"
        await vm.commitRename(task)
        #expect(vm.snapshot.tasks.map(\.name) == ["Zed"])
        #expect(try await store.plannerTask(id: task.id)?.positionKey == task.positionKey)
        // Empty commits revert with no write.
        let before = try await store.outboxRowCount()
        vm.beginRename(try #require(vm.snapshot.tasks.first))
        vm.editText = "   "
        await vm.commitRename(try #require(vm.snapshot.tasks.first))
        #expect(vm.snapshot.tasks.map(\.name) == ["Zed"])
        #expect(try await store.outboxRowCount() == before)
    }

    @Test("identical names stay independent through edits")
    func duplicateNamesIndependent() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "Read"
        await vm.submit()
        vm.draft = "Read"
        await vm.submit()
        #expect(vm.snapshot.tasks.count == 2)
        await vm.toggleComplete(vm.snapshot.tasks[1])
        #expect(vm.snapshot.tasks[0].completedOn == nil)
        #expect(vm.snapshot.tasks[1].completedOn != nil)
    }

    @Test("move reallocates between visible neighbors without rewriting others")
    func moveReorders() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        for name in ["A", "B", "C"] {
            vm.draft = name
            await vm.submit()
        }
        // Prepend order: newest on top.
        #expect(vm.snapshot.tasks.map(\.name) == ["C", "B", "A"])
        let keysBefore = Dictionary(uniqueKeysWithValues: vm.snapshot.tasks.map { ($0.name, $0.positionKey) })
        // Move A (index 2) to the top (index 0).
        await vm.move(from: IndexSet(integer: 2), to: 0)
        #expect(vm.snapshot.tasks.map(\.name) == ["A", "C", "B"])
        // C and B kept their keys; only A moved.
        for task in vm.snapshot.tasks where task.name != "A" {
            #expect(task.positionKey == keysBefore[task.name])
        }
        let moved = try #require(vm.snapshot.tasks.first)
        #expect(moved.positionKey < (try await store.plannerTask(id: vm.snapshot.tasks[1].id)?.positionKey ?? ""))
    }

    @Test("delete buffers and undo restores at the same position")
    func deleteUndo() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        vm.draft = "B"
        await vm.submit()
        // Prepend order: newest on top.
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
        let outboxBefore = try await store.outboxRowCount()
        await vm.delete(at: IndexSet(integer: 0))
        #expect(vm.snapshot.tasks.map(\.name) == ["A"])
        // Buffered: no outbox row yet.
        #expect(try await store.outboxRowCount() == outboxBefore)
        await vm.performUndo()
        #expect(vm.snapshot.tasks.map(\.name) == ["B", "A"])
        #expect(try await store.outboxRowCount() == outboxBefore)
    }

    // MARK: - One-tap Start

    @Test("start copies the name and inherits exact-text categories")
    func startInherits() async throws {
        let (vm, store) = await makeContext(categories: [("c1", "Work")])
        await vm.loadIfNeeded()
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Read",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            categoryIDs: ["c1"]
        ))
        vm.invalidate()
        await vm.loadIfNeeded()
        vm.draft = "Read"
        await vm.submit()
        let started = await vm.startTask(try #require(vm.snapshot.tasks.first))
        #expect(started)
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "Read")
        #expect(draft.categoryIDs == ["c1"])
        #expect(draft.plannerTaskID == vm.snapshot.tasks.first?.id)
    }

    @Test("a second Start never replaces an active run")
    func secondStartRefused() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        vm.draft = "B"
        await vm.submit()
        // Prepend order: the newest ("B") sits on top and starts first.
        #expect(await vm.startTask(vm.snapshot.tasks[0]))
        // The second task's Start starts nothing and keeps the checklist usable.
        #expect(await vm.startTask(vm.snapshot.tasks[1]) == false)
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "B")
        #expect(vm.snapshot.tasks.count == 2)
    }

    @Test("starting a completed task does nothing")
    func startCompletedNoop() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        #expect(await vm.startTask(try #require(vm.snapshot.tasks.first)) == false)
    }

    // MARK: - Helpers

    private func makeContext(
        categories: [(id: String, name: String)] = []
    ) async -> (vm: PlannerViewModel, store: LocalStore) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        for (id, name) in categories {
            _ = try? await store.createCategory(Category(id: id, name: name, icon: CatalogIcon.tag.rawValue))
        }
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
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-vm"))
    }
}
