import Testing
import Foundation
@testable import TimeOfLife

/// Planner task sheet notes + running-task convergence (day-planner §15):
/// the editor sheet's Notes field end-to-end (Log Time order, 2000-rune
/// bound) and the sheet-to-draft write-through on the running task. Split
/// from `PlannerViewModelTests` (file-length rule).
@MainActor
@Suite("Planner task sheet (day-planner 15)")
struct PlannerTaskSheetTests {
    @Test("sheet notes-only edit sends only the notes intent")
    func sheetNotesOnlyEditSendsOnlyNotes() async throws {
        let (vm, store, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        let before = try await store.outboxRowCount()
        vm.beginEdit(task)
        #expect(vm.sheetNotes.isEmpty)
        vm.sheetNotes = "chapter 3"
        #expect(vm.isSheetSaveEnabled)
        #expect(await vm.saveSheet())
        #expect(vm.snapshot.tasks.first?.notes == "chapter 3")
        #expect(vm.snapshot.tasks.first?.name == "A")
        let rows = try await store.outboxRows()
        #expect(rows.count == before + 1)
        let payload = try #require(rows.last?.payload?.data(using: .utf8))
        let op = try JSONDecoder().decode(PlannerOperationPayload.self, from: payload)
        #expect(op.intent == PlannerIntent.notes.rawValue)
        #expect(op.notes == "chapter 3")
        #expect(op.name == nil)
        #expect(op.categoryIDs == nil)
    }

    @Test("sheet edit carries notes alongside rename and retag")
    func sheetEditCarriesNotes() async throws {
        let (vm, store, _) = await makeContext(categories: [("c1", "Work")])
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        vm.beginEdit(task)
        vm.sheetName = "Zed"
        vm.sheetCategoryIDs = ["c1"]
        vm.sheetNotes = "chapter 3"
        #expect(await vm.saveSheet())
        #expect(vm.snapshot.tasks.first?.notes == "chapter 3")
        let intents = try await store.outboxRows().compactMap { row -> String? in
            guard let payload = row.payload?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: payload).intent
        }.filter { $0 != PlannerIntent.create.rawValue }
        #expect(intents.sorted() == ["notes", "rename", "retag"])
    }

    @Test("sheet blocks over-limit notes with the draft intact")
    func sheetBlocksOverLimitNotes() async throws {
        let (vm, store, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        let before = try await store.outboxRowCount()
        vm.beginEdit(task)
        // Entry-notes parity: surrounding whitespace counts client-side
        // (strictly tighter than the relay's trimmed gate).
        vm.sheetNotes = String(repeating: "я", count: 2001)
        #expect(vm.isSheetSaveEnabled == false)
        #expect(await vm.saveSheet() == false)
        #expect(vm.editingTask != nil)
        #expect(vm.snapshot.tasks.first?.notes.isEmpty == true)
        #expect(try await store.outboxRowCount() == before)
        // Exactly at the bound saves.
        vm.sheetNotes = String(repeating: "я", count: 2000)
        #expect(vm.isSheetSaveEnabled)
        #expect(await vm.saveSheet())
        #expect(vm.snapshot.tasks.first?.notes.count == 2000)
    }

    @Test("sheet save on the running task converges the draft (task to draft)")
    func sheetSaveWritesThroughToDraft() async throws {
        let (vm, store, center) = await makeContext(categories: [("c1", "Work"), ("c2", "Gym")])
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        let token = center.addObserver(
            forName: .plannerDraftConverged, object: nil, queue: nil
        ) { _ in flag.fired = true }
        defer { center.removeObserver(token) }
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        var task = try #require(vm.snapshot.tasks.first)
        // Tag + annotate first so Start copies both into the draft.
        vm.beginEdit(task)
        vm.sheetCategoryIDs = ["c2"]
        vm.sheetNotes = "chapter 2"
        #expect(await vm.saveSheet())
        task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        var draft = try #require(try await store.timerDraft())
        #expect(draft.categoryIDs == ["c2"])
        #expect(draft.notes == "chapter 2")

        // Save category + notes changes on the running task (renaming too —
        // the locked draft name must not move).
        let startedAt = try #require(draft.startedAt)
        vm.beginEdit(task)
        vm.sheetName = "Zed"
        vm.sheetCategoryIDs = ["c1"]
        vm.sheetNotes = "chapter 3"
        #expect(await vm.saveSheet())
        draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "A")
        #expect(draft.categoryIDs == ["c1"])
        #expect(draft.notes == "chapter 3")
        #expect(draft.plannerTaskID == task.id)
        #expect(draft.startedAt == startedAt)
        // The task carries the rename; no entry changed.
        #expect(try await store.plannerTask(id: task.id)?.name == "Zed")
        #expect(try await store.entries().isEmpty)
        // The converging save tells Track to reload (a name-only save on
        // an unlinked task posts nothing — covered by the sheet-only tests
        // above staying silent on the default center).
        #expect(flag.fired)
    }

    @Test("start copies task notes into the running draft")
    func startCopiesNotes() async throws {
        let (vm, store, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "A"
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        vm.beginEdit(task)
        vm.sheetNotes = "chapter 3"
        #expect(await vm.saveSheet())
        #expect(await vm.startTask(try #require(vm.snapshot.tasks.first)))
        #expect(try await store.timerDraft()?.notes == "chapter 3")
    }

    @Test("the running task reads its link for the In progress row")
    func runningTaskExposesLink() async throws {
        let (vm, _, _) = await makeContext()
        await vm.loadIfNeeded()
        #expect(vm.linkedTaskID == nil)
        vm.draft = "A"
        await vm.submit()
        #expect(vm.linkedTaskID == nil)
        let task = try #require(vm.snapshot.tasks.first)
        #expect(await vm.startTask(task))
        // The Start leaves the projection stale until the next serialized
        // reload (the view invalidates on disappear and reloads on appear —
        // mirrored here); the reload exposes the link for the row.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.linkedTaskID == task.id)
        #expect(vm.rowCategories(for: task).isEmpty)
    }

    // MARK: - Helpers

    private func makeContext(
        categories: [(id: String, name: String)] = []
    ) async -> (vm: PlannerViewModel, store: LocalStore, center: NotificationCenter) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        for (id, name) in categories {
            _ = try? await store.createCategory(Category(id: id, name: name, icon: CatalogIcon.tag.rawValue))
        }
        // Private center (linked-stop precedent): the converging saveSheet
        // posts `.plannerDraftConverged` here, never on `.default`, so no
        // parallel Track-view-model test can observe a stray reload.
        let center = NotificationCenter()
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store),
            notifications: center
        )
        return (vm, store, center)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-sheet"))
    }
}
