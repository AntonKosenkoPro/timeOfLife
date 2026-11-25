import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("Planner view model (day-planner 3.1/3.2)")
struct PlannerViewModelTests {
    // MARK: - Composer

    @Test("submit appends one task, clears the draft, and keeps order")
    func submitAppends() async throws {
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

    @Test("invalid submissions append nothing and keep the draft")
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

    @Test("consecutive Returns append in submission order")
    func consecutiveSubmits() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "First"
        await vm.submit()
        vm.draft = "Second"
        await vm.submit()
        #expect(vm.draft.isEmpty)
        #expect(vm.snapshot.tasks.map(\.name) == ["First", "Second"])
    }

    @Test("suggestions filter newest-first and fill without submitting")
    func suggestionsFill() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        // Committed entries feed the suggestion pool (local Recents).
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
        let suggestions = vm.suggestions
        #expect(suggestions.map(\.activityText) == ["Read docs", "Reading"])
        vm.fillFromSuggestion(suggestions[0])
        #expect(vm.draft == "Read docs")
        #expect(vm.snapshot.total == 0)
        #expect(try await store.plannerTasks().isEmpty)
    }

    @Test("empty draft shows no suggestions")
    func emptyDraftNoSuggestions() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = ""
        #expect(vm.suggestions.isEmpty)
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
        let first = try #require(vm.snapshot.tasks.first)
        await vm.toggleComplete(first)
        #expect(vm.snapshot.tasks.map(\.name) == ["A", "B"])
        #expect(vm.snapshot.done == 1)
        await vm.toggleComplete(try #require(vm.snapshot.tasks.first))
        #expect(vm.snapshot.done == 0)
        #expect(vm.snapshot.tasks.map(\.name) == ["A", "B"])
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
        let keysBefore = Dictionary(uniqueKeysWithValues: vm.snapshot.tasks.map { ($0.name, $0.positionKey) })
        // Move C (index 2) to the top (index 0).
        await vm.move(from: IndexSet(integer: 2), to: 0)
        #expect(vm.snapshot.tasks.map(\.name) == ["C", "A", "B"])
        // A and B kept their keys; only C moved.
        for task in vm.snapshot.tasks where task.name != "C" {
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
        let outboxBefore = try await store.outboxRowCount()
        await vm.delete(at: IndexSet(integer: 0))
        #expect(vm.snapshot.tasks.map(\.name) == ["B"])
        // Buffered: no outbox row yet.
        #expect(try await store.outboxRowCount() == outboxBefore)
        await vm.performUndo()
        #expect(vm.snapshot.tasks.map(\.name) == ["A", "B"])
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
        #expect(await vm.startTask(vm.snapshot.tasks[0]))
        // The second task's Start starts nothing and keeps the checklist usable.
        #expect(await vm.startTask(vm.snapshot.tasks[1]) == false)
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "A")
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
