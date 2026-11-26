import Testing
import Foundation
@testable import TimeOfLife

@Suite("Planner store (day-planner 2.3)")
struct LocalStorePlannerTests {
    private func makeStore(userID: String = "planner-u1") throws -> LocalStore {
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

    // MARK: - CRUD + validation

    @Test("Create validates names with the shared timer-name rule")
    func createValidation() async throws {
        let store = try makeStore()
        let badKey = try #require(PlannerPositionKey.allocate(before: nil, after: nil))
        #expect(badKey == "500000")
        let empty = try await store.createPlannerTask(
            id: UUID().uuidString, name: "  ", positionKey: "500000",
            operationID: UUID().uuidString
        )
        guard case .invalid = empty else {
            Issue.record("empty name must be invalid, got \(empty)")
            return
        }
        let long = try await store.createPlannerTask(
            id: UUID().uuidString, name: String(repeating: "x", count: 61),
            positionKey: "500000", operationID: UUID().uuidString
        )
        guard case .invalid = long else {
            Issue.record("61-char name must be invalid, got \(long)")
            return
        }
        let badPosition = try await store.createPlannerTask(
            id: UUID().uuidString, name: "Read", positionKey: "abc",
            operationID: UUID().uuidString
        )
        #expect(badPosition == .failure)
    }

    @Test("Duplicate names are separate identities")
    func duplicateNames() async throws {
        let store = try makeStore()
        let first = try await makeTask(store, name: "Read", key: "500000")
        let second = try await makeTask(store, name: "Read", key: "500001")
        #expect(first.id != second.id)
        // Editing one leaves the other untouched.
        let renamed = try await store.renamePlannerTask(
            id: first.id, name: "Read books", operationID: UUID().uuidString
        )
        guard case .saved = renamed else {
            Issue.record("rename failed: \(renamed)")
            return
        }
        #expect(try await store.plannerTask(id: first.id)?.name == "Read books")
        #expect(try await store.plannerTask(id: first.id)?.positionKey == "500000")
        let untouched = try #require(try await store.plannerTask(id: second.id))
        #expect(untouched.name == "Read")
    }

    @Test("Rename/move/complete/reopen keep position and enqueue field intents")
    func fieldIntents() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        let before = try await store.outboxRowCount()

        let renamed = try await store.renamePlannerTask(
            id: task.id, name: "Read books", operationID: UUID().uuidString
        )
        guard case let .saved(r1) = renamed else {
            Issue.record("rename failed: \(renamed)"); return
        }
        #expect(r1.name == "Read books")
        #expect(r1.positionKey == "500000")

        let moved = try await store.movePlannerTask(
            id: task.id, positionKey: "500000.5", operationID: UUID().uuidString
        )
        guard case let .saved(r2) = moved else {
            Issue.record("move failed: \(moved)"); return
        }
        #expect(r2.positionKey == "500000.5")
        #expect(r2.name == "Read books")

        let done = try await store.completePlannerTask(
            id: task.id, completedOn: "2026-11-25", operationID: UUID().uuidString
        )
        guard case let .saved(r3) = done else {
            Issue.record("complete failed: \(done)"); return
        }
        #expect(r3.completedOn == "2026-11-25")
        #expect(r3.positionKey == "500000.5")

        let open = try await store.reopenPlannerTask(id: task.id, operationID: UUID().uuidString)
        guard case let .saved(r4) = open else {
            Issue.record("reopen failed: \(open)"); return
        }
        #expect(r4.completedOn == nil)
        #expect(r4.name == "Read books")
        #expect(try await store.outboxRowCount() == before + 4)

        // Missing tasks report .missing on every verb.
        #expect(try await store.renamePlannerTask(id: "nope", name: "X", operationID: UUID().uuidString) == .missing)
        #expect(try await store.movePlannerTask(id: "nope", positionKey: "500001", operationID: UUID().uuidString) == .missing)
        #expect(try await store.completePlannerTask(id: "nope", completedOn: "2026-11-25", operationID: UUID().uuidString) == .missing)
        #expect(try await store.reopenPlannerTask(id: "nope", operationID: UUID().uuidString) == .missing)
        #expect(try await store.retagPlannerTask(id: "nope", categoryIDs: ["c1"], operationID: UUID().uuidString) == .missing)
    }

    @Test("Retag replaces the ordered set with its own outbox intent")
    func retagReplacesSet() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        // New tasks carry no categories.
        #expect(task.categoryIDs.isEmpty)
        #expect((try await store.plannerTask(id: task.id)?.categoryIDs ?? []).isEmpty)
        let before = try await store.outboxRowCount()

        let tagged = try await store.retagPlannerTask(
            id: task.id, categoryIDs: ["c1", "c2"], operationID: UUID().uuidString
        )
        guard case let .saved(t1) = tagged else {
            Issue.record("retag failed: \(tagged)"); return
        }
        #expect(t1.categoryIDs == ["c1", "c2"])
        // The set survives the round trip; name and position are untouched.
        #expect(try await store.plannerTask(id: task.id)?.categoryIDs == ["c1", "c2"])
        #expect(try await store.plannerTask(id: task.id)?.name == "Read")
        // Order is preserved (not sorted), duplicates collapse.
        let reordered = try await store.retagPlannerTask(
            id: task.id, categoryIDs: ["c2", "c1", "c2"], operationID: UUID().uuidString
        )
        guard case let .saved(t2) = reordered else {
            Issue.record("retag failed: \(reordered)"); return
        }
        #expect(t2.categoryIDs == ["c2", "c1"])
        // An empty set clears (full replace, not a merge).
        let cleared = try await store.retagPlannerTask(
            id: task.id, categoryIDs: [], operationID: UUID().uuidString
        )
        guard case let .saved(t3) = cleared else {
            Issue.record("retag failed: \(cleared)"); return
        }
        #expect(t3.categoryIDs.isEmpty)
        #expect(try await store.outboxRowCount() == before + 3)
        // The queued payload carries the set under its own intent.
        let rows = try await store.outboxRows()
        let payloads = try rows.compactMap { $0.payload?.data(using: .utf8) }.map {
            try JSONDecoder().decode(PlannerOperationPayload.self, from: $0)
        }
        let retags = payloads.filter { $0.intent == PlannerIntent.retag.rawValue }
        #expect(retags.count == 3)
        #expect(retags[0].categoryIDs == ["c1", "c2"])
        #expect(retags[1].categoryIDs == ["c2", "c1"])
        #expect((retags[2].categoryIDs ?? []).isEmpty)
        #expect(retags.allSatisfy { $0.name == nil && $0.positionKey == nil && $0.completedOn == nil })
    }

    @Test("Unchanged writes enqueue nothing")
    func unchangedWritesAreQuiet() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        let before = try await store.outboxRowCount()
        #expect(try await store.renamePlannerTask(id: task.id, name: "Read", operationID: UUID().uuidString)
            == .saved(try #require(try await store.plannerTask(id: task.id))))
        #expect(try await store.movePlannerTask(id: task.id, positionKey: "500000", operationID: UUID().uuidString)
            == .saved(try #require(try await store.plannerTask(id: task.id))))
        #expect(try await store.reopenPlannerTask(id: task.id, operationID: UUID().uuidString)
            == .saved(try #require(try await store.plannerTask(id: task.id))))
        #expect(try await store.retagPlannerTask(id: task.id, categoryIDs: [], operationID: UUID().uuidString)
            == .saved(try #require(try await store.plannerTask(id: task.id))))
        #expect(try await store.outboxRowCount() == before)
    }

    // MARK: - Undo

    @Test("Delete is buffered, undoable, and committable")
    func durableUndo() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        let outboxBefore = try await store.outboxRowCount()

        let deleted = try await store.deletePlannerTaskUndoable(id: task.id)
        guard case .deleted = deleted else {
            Issue.record("delete failed: \(deleted)"); return
        }
        // Buffered: row gone, no outbox row yet.
        #expect(try await store.plannerTask(id: task.id) == nil)
        #expect(try await store.outboxRowCount() == outboxBefore)

        let restored = try await store.undoPlannerTaskDeletion(bufferID: try await store.bufferedDeletions().first!.bufferID)
        #expect(restored?.id == task.id)
        #expect(try await store.plannerTask(id: task.id)?.name == "Read")
        #expect(try await store.outboxRowCount() == outboxBefore)

        // Delete again, then commit (cold-launch backstop): outbox delete row, no restore.
        _ = try await store.deletePlannerTaskUndoable(id: task.id)
        try await store.undoBufferCommitAll()
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "planner_task" && $0.recordID == task.id && $0.op == "delete" })
        #expect(try await store.plannerTask(id: task.id) == nil)
    }

    @Test("Undo restores the tagged set")
    func undoRestoresCategories() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        _ = try await store.retagPlannerTask(
            id: task.id, categoryIDs: ["c1", "c2"], operationID: UUID().uuidString
        )
        _ = try await store.deletePlannerTaskUndoable(id: task.id)
        #expect(try await store.plannerTask(id: task.id) == nil)
        let restored = try await store.undoPlannerTaskDeletion(bufferID: try await store.bufferedDeletions().first!.bufferID)
        #expect(restored?.categoryIDs == ["c1", "c2"])
        #expect(try await store.plannerTask(id: task.id)?.categoryIDs == ["c1", "c2"])
    }

    // MARK: - Projection

    @Test("Today projection filters and orders without writing")
    func todayProjection() async throws {
        let store = try makeStore()
        let a = try await makeTask(store, name: "A", key: "500001")
        _ = try await makeTask(store, name: "B", key: "500000")
        _ = try await store.completePlannerTask(id: a.id, completedOn: "2026-11-25", operationID: UUID().uuidString)
        _ = try await makeTask(store, name: "Old", key: "499999")
        let old = try await store.plannerTasks().first { $0.name == "Old" }!
        _ = try await store.completePlannerTask(id: old.id, completedOn: "2026-11-20", operationID: UUID().uuidString)

        let outboxBefore = try await store.outboxRowCount()
        let snapshot = PlannerToday.project(tasks: try await store.plannerTasks(), on: "2026-11-25")
        // Visible: unfinished B (500000), completed-today A (500001); the
        // 11-20 completion stays hidden. Shared order is kept.
        #expect(snapshot.tasks.map(\.name) == ["B", "A"])
        #expect(snapshot.done == 1)
        #expect(snapshot.total == 2)
        // Rollover is read-only: no store write happened.
        #expect(try await store.outboxRowCount() == outboxBefore)

        let nextDay = PlannerToday.project(tasks: try await store.plannerTasks(), on: "2026-11-26")
        #expect(nextDay.tasks.map(\.name) == ["B"])
        #expect(nextDay.done == 0)
    }

    // MARK: - Account isolation

    @Test("Planner state is per-account and returns with the account")
    func accountRebinding() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let storeA = try LocalStore(
            url: base.appendingPathComponent(LocalStore.databaseFileName(userID: "iso-a")), userID: "iso-a"
        )
        _ = try await LocalStorePlannerTestsHelper.create(storeA, name: "A-task", key: "500000")
        let storeB = try LocalStore(
            url: base.appendingPathComponent(LocalStore.databaseFileName(userID: "iso-b")), userID: "iso-b"
        )
        #expect(try await storeB.plannerTasks().isEmpty)
        _ = try await LocalStorePlannerTestsHelper.create(storeB, name: "B-task", key: "500000")
        // Rebinding A restores its local state untouched by B.
        #expect(try await storeA.plannerTasks().map(\.name) == ["A-task"])
        #expect(try await storeB.plannerTasks().map(\.name) == ["B-task"])
        #expect(try await storeA.outboxRows().allSatisfy { $0.resource == "planner_task" })
    }
}

enum PlannerTestError: Error {
    case createFailed
}

private enum LocalStorePlannerTestsHelper {
    static func create(_ store: LocalStore, name: String, key: String) async throws -> PlannerTask {
        let result = try await store.createPlannerTask(
            id: UUID().uuidString, name: name, positionKey: key,
            operationID: UUID().uuidString
        )
        guard case let .saved(task) = result else { throw PlannerTestError.createFailed }
        return task
    }
}
