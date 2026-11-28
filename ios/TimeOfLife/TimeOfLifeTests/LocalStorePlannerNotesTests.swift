import Testing
import Foundation
@testable import TimeOfLife

/// Planner task notes + linked-run convergence (day-planner §15):
/// the `notes` field intent end-to-end at the store, and the Track↔task
/// write-through in the same chokepoint transaction. Split from
/// `LocalStorePlannerTests` (file-length rule).
@Suite("Planner notes and convergence (day-planner 15)")
struct LocalStorePlannerNotesTests {
    private func makeStore(userID: String = "planner-notes-u1") throws -> LocalStore {
        try LocalStore(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(LocalStore.databaseFileName(userID: userID)),
            userID: userID
        )
    }

    private func makeTask(
        _ store: LocalStore,
        name: String = "Read",
        key: String = "500000"
    ) async throws -> PlannerTask {
        let result = try await store.createPlannerTask(
            id: UUID().uuidString, name: name, positionKey: key,
            operationID: UUID().uuidString
        )
        guard case let .saved(task) = result else {
            Issue.record("create failed")
            throw PlannerTestError.createFailed
        }
        return task
    }

    private func linkRun(_ store: LocalStore, task: PlannerTask, categories: [String] = [], notes: String = "") async throws {
        let claimed = try await store.claimTimerDraft(
            activityText: task.name,
            categoryIDs: categories,
            startedAt: Date(),
            notes: notes,
            plannerTaskID: task.id
        )
        try #require(claimed)
    }

    private func payloadIntents(_ store: LocalStore, recordID: String) async throws -> [String] {
        try await store.outboxRows()
            .filter { $0.resource == LocalStore.plannerResource && $0.recordID == recordID }
            .compactMap { row -> String? in
                guard let payload = row.payload?.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(PlannerOperationPayload.self, from: payload).intent
            }
    }

    // MARK: - Notes intent

    @Test("notes replace the text with their own outbox row, leaving other fields")
    func notesIntentIsFieldSpecific() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        let before = try await store.outboxRowCount()

        let noted = try await store.setPlannerTaskNotes(
            id: task.id, notes: "chapter 3", operationID: UUID().uuidString
        )
        guard case let .saved(saved) = noted else {
            Issue.record("notes failed: \(noted)")
            return
        }
        #expect(saved.notes == "chapter 3")
        #expect(saved.name == task.name)
        #expect(saved.positionKey == task.positionKey)
        #expect(saved.categoryIDs == task.categoryIDs)
        #expect(try await store.outboxRowCount() == before + 1)

        let rows = try await store.outboxRows()
        let payload = try #require(rows.last?.payload?.data(using: .utf8))
        let op = try JSONDecoder().decode(PlannerOperationPayload.self, from: payload)
        #expect(op.intent == PlannerIntent.notes.rawValue)
        #expect(op.notes == "chapter 3")
        #expect(op.name == nil)
        #expect(op.positionKey == nil)
        #expect(op.completedOn == nil)
        #expect(op.categoryIDs == nil)
    }

    @Test("unchanged notes enqueue nothing; missing tasks report missing")
    func notesNoopAndMissing() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        _ = try await store.setPlannerTaskNotes(
            id: task.id, notes: "chapter 3", operationID: UUID().uuidString
        )
        let before = try await store.outboxRowCount()
        #expect(try await store.setPlannerTaskNotes(
            id: task.id, notes: "chapter 3", operationID: UUID().uuidString
        ) == .saved(try #require(try await store.plannerTask(id: task.id))))
        #expect(try await store.outboxRowCount() == before)

        #expect(try await store.setPlannerTaskNotes(
            id: "nope", notes: "x", operationID: UUID().uuidString
        ) == .missing)
    }

    @Test("the store keeps notes verbatim — the bound lives in the sheet and the relay")
    func notesStoredVerbatim() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        // Over the 2000-rune relay bound: still persists locally (the sheet
        // validity gate blocks the save; the relay 422s the push). Pinning
        // this keeps a future store-side gate from silently truncating.
        let long = String(repeating: "я", count: 2001)
        let saved = try await store.setPlannerTaskNotes(
            id: task.id, notes: "  \(long)  ", operationID: UUID().uuidString
        )
        guard case .saved = saved else {
            Issue.record("verbatim notes failed: \(saved)")
            return
        }
        #expect(try await store.plannerTask(id: task.id)?.notes == "  \(long)  ")
    }

    // MARK: - Track→task convergence (15.2)

    @Test("Track retag writes through to the linked task in one transaction")
    func trackRetagWritesThrough() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        try await linkRun(store, task: task)
        let before = try await store.outboxRowCount()

        try await store.updateRunningDraftCategories(["c1"], operationID: UUID().uuidString)

        // The draft and the task converge with a single retag row — no
        // draft-sync row, no extra intent.
        #expect(try await store.timerDraft()?.categoryIDs == ["c1"])
        #expect(try await store.plannerTask(id: task.id)?.categoryIDs == ["c1"])
        #expect(try await payloadIntents(store, recordID: task.id) == ["create", "retag"])
        #expect(try await store.outboxRowCount() == before + 1)
        // The locked text rides along untouched.
        #expect(try await store.timerDraft()?.activityText == task.name)
    }

    @Test("Track notes edit writes through to the linked task in one transaction")
    func trackNotesWriteThrough() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        try await linkRun(store, task: task)
        let before = try await store.outboxRowCount()

        try await store.updateRunningDraftNotes("mid-run thought", operationID: UUID().uuidString)

        #expect(try await store.timerDraft()?.notes == "mid-run thought")
        #expect(try await store.plannerTask(id: task.id)?.notes == "mid-run thought")
        #expect(try await payloadIntents(store, recordID: task.id) == ["create", "notes"])
        #expect(try await store.outboxRowCount() == before + 1)
        #expect(try await store.timerDraft()?.activityText == task.name)
    }

    @Test("write-through is a no-op without a draft and survives a missing task")
    func writeThroughEdgeCases() async throws {
        let store = try makeStore()
        // No draft: nothing writes, nothing queues.
        try await store.updateRunningDraftCategories(["c1"], operationID: UUID().uuidString)
        try await store.updateRunningDraftNotes("x", operationID: UUID().uuidString)
        #expect(try await store.outboxRows().isEmpty)

        // A linked-then-deleted task still rewrites the draft (time capture
        // never fails for the planner).
        let task = try await makeTask(store)
        try await linkRun(store, task: task)
        _ = try await store.deletePlannerTaskUndoable(id: task.id)
        let before = try await store.outboxRowCount()
        try await store.updateRunningDraftCategories(["c1"], operationID: UUID().uuidString)
        try await store.updateRunningDraftNotes("kept", operationID: UUID().uuidString)
        #expect(try await store.timerDraft()?.categoryIDs == ["c1"])
        #expect(try await store.timerDraft()?.notes == "kept")
        #expect(try await store.outboxRowCount() == before)
    }

    // MARK: - Sheet→draft convergence (15.2)

    @Test("sheet save on the running task converges the draft, locked name untouched")
    func sheetSaveWritesThroughToDraft() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        try await linkRun(store, task: task)
        let before = try await store.outboxRowCount()

        let outcome = try await store.savePlannerTaskSheet(
            id: task.id,
            write: PlannerSheetWrite(
                name: "Read books",
                categoryIDs: ["c1"],
                notes: "chapter 3",
                renameOperationID: UUID().uuidString,
                retagOperationID: UUID().uuidString,
                notesOperationID: UUID().uuidString
            )
        )
        guard case let .saved(saved) = outcome else {
            Issue.record("sheet save failed: \(outcome)")
            return
        }
        #expect(saved.name == "Read books")
        #expect(saved.categoryIDs == ["c1"])
        #expect(saved.notes == "chapter 3")
        // Each changed field enqueues its own intent — nothing else.
        #expect(try await payloadIntents(store, recordID: task.id).sorted() == ["create", "notes", "rename", "retag"])
        #expect(try await store.outboxRowCount() == before + 3)
        // The draft follows the live fields with the locked name and the
        // same started_at untouched.
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "Read")
        #expect(draft.categoryIDs == ["c1"])
        #expect(draft.notes == "chapter 3")
        #expect(draft.plannerTaskID == task.id)
    }

    @Test("name-only sheet edits on the running task leave the draft untouched")
    func sheetNameOnlyLeavesDraft() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        // The task already carries the live set and notes (an earlier sheet
        // save), and the draft mirrors them (Start copied them in).
        _ = try await store.retagPlannerTask(
            id: task.id, categoryIDs: ["c1"], operationID: UUID().uuidString
        )
        _ = try await store.setPlannerTaskNotes(
            id: task.id, notes: "kept", operationID: UUID().uuidString
        )
        try await linkRun(store, task: task, categories: ["c1"], notes: "kept")
        let before = try await store.outboxRowCount()
        let draftBefore = try #require(try await store.timerDraft())

        let outcome = try await store.savePlannerTaskSheet(
            id: task.id,
            write: PlannerSheetWrite(
                name: "Read books",
                categoryIDs: ["c1"],
                notes: "kept",
                renameOperationID: UUID().uuidString,
                retagOperationID: UUID().uuidString,
                notesOperationID: UUID().uuidString
            )
        )
        guard case .saved = outcome else {
            Issue.record("sheet save failed: \(outcome)")
            return
        }
        // Only the rename intent; the draft snapshot is byte-identical.
        let rows = try await store.outboxRows()
        let last = try #require(rows.last)
        let lastOp = try JSONDecoder().decode(PlannerOperationPayload.self, from: Data(last.payload!.utf8))
        #expect(lastOp.intent == PlannerIntent.rename.rawValue)
        #expect(try await store.outboxRowCount() == before + 1)
        #expect(try await store.timerDraft() == draftBefore)
    }

    @Test("sheet save without changes writes nothing")
    func sheetSaveUnchangedIsNoop() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        _ = try await store.setPlannerTaskNotes(
            id: task.id, notes: "kept", operationID: UUID().uuidString
        )
        let before = try await store.outboxRowCount()
        let stored = try #require(try await store.plannerTask(id: task.id))

        let outcome = try await store.savePlannerTaskSheet(
            id: task.id,
            write: PlannerSheetWrite(
                name: stored.name,
                categoryIDs: stored.categoryIDs,
                notes: "kept",
                renameOperationID: UUID().uuidString,
                retagOperationID: UUID().uuidString,
                notesOperationID: UUID().uuidString
            )
        )
        guard case .saved = outcome else {
            Issue.record("sheet save failed: \(outcome)")
            return
        }
        #expect(try await store.outboxRowCount() == before)
        #expect(try await store.plannerTask(id: task.id)?.updatedAt == stored.updatedAt)
    }

    @Test("sheet save validates the name and reports missing")
    func sheetSaveGuards() async throws {
        let store = try makeStore()
        let task = try await makeTask(store)
        let before = try await store.outboxRowCount()
        guard case .invalid = try await store.savePlannerTaskSheet(
            id: task.id,
            write: PlannerSheetWrite(
                name: "  ",
                categoryIDs: [],
                notes: "",
                renameOperationID: UUID().uuidString,
                retagOperationID: UUID().uuidString,
                notesOperationID: UUID().uuidString
            )
        ) else {
            Issue.record("blank sheet name must be invalid")
            return
        }
        #expect(try await store.outboxRowCount() == before)
        guard case .missing = try await store.savePlannerTaskSheet(
            id: "nope",
            write: PlannerSheetWrite(
                name: "Read",
                categoryIDs: [],
                notes: "",
                renameOperationID: UUID().uuidString,
                retagOperationID: UUID().uuidString,
                notesOperationID: UUID().uuidString
            )
        ) else {
            Issue.record("unknown sheet task must be missing")
            return
        }
    }
}
