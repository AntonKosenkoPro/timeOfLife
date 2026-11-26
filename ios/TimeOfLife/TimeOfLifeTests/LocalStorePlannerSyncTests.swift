import Testing
import Foundation
@testable import TimeOfLife

@Suite("Planner stop link + feed cursor (day-planner 2.3)")
struct LocalStorePlannerSyncTests {
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
            throw PlannerStoreSyncTestError.createFailed
        }
        return task
    }

    // MARK: - Draft link + atomic Stop

    @Test("claimTimerDraft gates a second Start at the boundary")
    func draftClaim() async throws {
        let store = try makeStore()
        #expect(try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: "task-1"
        ))
        #expect(!(try await store.claimTimerDraft(
            activityText: "Other", categoryIDs: [], startedAt: Date(), plannerTaskID: "task-2"
        )))
        let draft = try #require(try await store.timerDraft())
        #expect(draft.activityText == "Read")
        #expect(draft.plannerTaskID == "task-1")
    }

    @Test("Atomic Stop completes exactly the linked task")
    func linkedStop() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        let outboxBefore = try await store.outboxRowCount()
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: task.id
        )
        let entry = TimeEntry(
            id: UUID().uuidString, activityText: "Read",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(),
            durationSeconds: 60, notes: "n"
        )
        let link = LocalStore.PlannerStopLink(
            taskID: task.id, operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        let mutation = try await store.stopRunningTimer(entry, plannerLink: link)
        guard case .created = mutation else {
            Issue.record("stop failed: \(mutation)"); return
        }
        // Entry saved, task completed, both outbox rows queued, draft cleared.
        #expect(try await store.entry(id: entry.id) != nil)
        #expect(try await store.plannerTask(id: task.id)?.completedOn == "2026-11-25")
        #expect(try await store.outboxRowCount() == outboxBefore + 2)
        #expect(try await store.timerDraft() == nil)
    }

    @Test("Stop replay never reruns completion after reopen")
    func stopReplayAfterReopen() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: task.id
        )
        let entry = TimeEntry(
            id: UUID().uuidString, activityText: "Read",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        let link = LocalStore.PlannerStopLink(
            taskID: task.id, operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        guard case .created = try await store.stopRunningTimer(entry, plannerLink: link) else {
            Issue.record("first stop failed"); return
        }
        // User reopens the task, then the same logical Stop retries.
        _ = try await store.reopenPlannerTask(id: task.id, operationID: UUID().uuidString)
        guard case .created = try await store.stopRunningTimer(entry, plannerLink: link) else {
            Issue.record("replay stop failed"); return
        }
        #expect(try await store.plannerTask(id: task.id)?.completedOn == nil)
    }

    @Test("Stop with missing/deleted/completed task saves the entry alone")
    func stopLinkNoops() async throws {
        let store = try makeStore()
        // Missing task.
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: "ghost"
        )
        let entry = TimeEntry(
            id: UUID().uuidString, activityText: "Read",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        let outboxBefore = try await store.outboxRowCount()
        let link = LocalStore.PlannerStopLink(
            taskID: "ghost", operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        guard case .created = try await store.stopRunningTimer(entry, plannerLink: link) else {
            Issue.record("stop failed"); return
        }
        #expect(try await store.entry(id: entry.id) != nil)
        // Only the entry create was queued — no phantom planner row or op.
        #expect(try await store.outboxRowCount() == outboxBefore + 1)

        // Already-completed task: no second completion op.
        let task = try await makeTask(store, name: "Done", key: "500001")
        _ = try await store.completePlannerTask(id: task.id, completedOn: "2026-11-25", operationID: UUID().uuidString)
        let before2 = try await store.outboxRowCount()
        _ = try await store.claimTimerDraft(
            activityText: "Done", categoryIDs: [], startedAt: Date(), plannerTaskID: task.id
        )
        let entry2 = TimeEntry(
            id: UUID().uuidString, activityText: "Done",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        let link2 = LocalStore.PlannerStopLink(
            taskID: task.id, operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        guard case .created = try await store.stopRunningTimer(entry2, plannerLink: link2) else {
            Issue.record("stop 2 failed"); return
        }
        #expect(try await store.outboxRowCount() == before2 + 1)

    }

    @Test("Stop with a deleted task saves the entry alone")
    func stopLinkDeletedNoop() async throws {
        let store = try makeStore()
        let doomed = try await makeTask(store, name: "Doomed", key: "500002")
        _ = try await store.deletePlannerTaskUndoable(id: doomed.id)
        _ = try await store.claimTimerDraft(
            activityText: "Doomed", categoryIDs: [], startedAt: Date(), plannerTaskID: doomed.id
        )
        let entry = TimeEntry(
            id: UUID().uuidString, activityText: "Doomed",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        let link = LocalStore.PlannerStopLink(
            taskID: doomed.id, operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        let before = try await store.outboxRowCount()
        guard case .created = try await store.stopRunningTimer(entry, plannerLink: link) else {
            Issue.record("stop failed"); return
        }
        // Entry saved, deleted task stays deleted, only the entry queued.
        #expect(try await store.plannerTask(id: doomed.id) == nil)
        #expect(try await store.outboxRowCount() == before + 1)
    }

    @Test("Failed Stop rolls back the task completion too")
    func stopFailureRollsBack() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: task.id
        )
        // Invalid entry text: the whole transaction must roll back.
        let bad = TimeEntry(
            id: UUID().uuidString, activityText: "   ",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        let link = LocalStore.PlannerStopLink(
            taskID: task.id, operationID: UUID().uuidString, completedOn: "2026-11-25"
        )
        let outboxBefore = try await store.outboxRowCount()
        let mutation = try await store.stopRunningTimer(bad, plannerLink: link)
        guard case .invalid = mutation else {
            Issue.record("expected invalid, got \(mutation)"); return
        }
        #expect(try await store.plannerTask(id: task.id)?.completedOn == nil)
        #expect(try await store.outboxRowCount() == outboxBefore)
        #expect(try await store.timerDraft() != nil)
    }

    // MARK: - Feed page / cursor

    @Test("Feed pages apply atomically with their cursor")
    func feedPageCursor() async throws {
        let store = try makeStore()
        #expect(try await store.plannerRevisionCursor() == 0)
        let local = try await makeTask(store, name: "Local", key: "500000")

        // A page carrying a remote task and a rename of the local task...
        // the local rename is pending, so the feed must not clobber it.
        _ = try await store.renamePlannerTask(id: local.id, name: "Local v2", operationID: UUID().uuidString)
        let remote = PlannerTask(
            id: UUID().uuidString, name: "Remote", positionKey: "500001",
            createdAt: Date(), updatedAt: Date()
        )
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: PlannerTask(
                id: local.id, name: "Local remote", positionKey: "500000",
                createdAt: local.createdAt, updatedAt: Date()
            ), deleted: false, revision: 5),
            PlannerFeedChange(task: remote, deleted: false, revision: 6),
        ], cursor: 6)
        #expect(try await store.plannerRevisionCursor() == 6)
        // Pending local intent stayed visible; the remote row merged.
        #expect(try await store.plannerTask(id: local.id)?.name == "Local v2")
        #expect(try await store.plannerTask(id: remote.id)?.name == "Remote")

        // A terminal marker for a task with a pending rename wins: the
        // pending intent is dropped and the row converges to deleted.
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: local, deleted: true, revision: 7),
        ], cursor: 7)
        #expect(try await store.plannerTask(id: local.id) == nil)
        #expect(try await store.outboxRows().contains {
            $0.resource == "planner_task" && $0.recordID == local.id && $0.op != "delete"
        } == false)
        #expect(try await store.plannerRevisionCursor() == 7)
    }

    @Test("Buffered and drain-deleted tasks are invisible to the feed")
    func deleteWinsOverFeed() async throws {
        let store = try makeStore()
        let task = try await makeTask(store, name: "Read", key: "500000")
        _ = try await store.deletePlannerTaskUndoable(id: task.id)
        // A racing remote rename must not resurrect the buffered deletion.
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: PlannerTask(
                id: task.id, name: "Renamed remotely", positionKey: "500000",
                createdAt: task.createdAt, updatedAt: Date()
            ), deleted: false, revision: 3),
        ], cursor: 3)
        #expect(try await store.plannerTask(id: task.id) == nil)
        #expect(try await store.plannerRevisionCursor() == 3)
    }

    @Test("Feed pages carry the ordered set and delete wins over a pending retag")
    func feedPageCarriesCategories() async throws {
        let store = try makeStore()
        let local = try await makeTask(store, name: "Local", key: "500000")
        // A pending local retag stays visible when the feed carries an
        // older remote state for the same task.
        _ = try await store.retagPlannerTask(
            id: local.id, categoryIDs: ["c-local"], operationID: UUID().uuidString
        )
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: PlannerTask(
                id: local.id, name: "Local", positionKey: "500000",
                categoryIDs: ["c-remote"],
                createdAt: local.createdAt, updatedAt: Date()
            ), deleted: false, revision: 5),
        ], cursor: 5)
        #expect(try await store.plannerTask(id: local.id)?.categoryIDs == ["c-local"])
        // A fresh tagged row merges with its set intact.
        let remote = PlannerTask(
            id: UUID().uuidString, name: "Remote",
            positionKey: "500001", categoryIDs: ["c1", "c2"],
            createdAt: Date(), updatedAt: Date()
        )
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: remote, deleted: false, revision: 6),
        ], cursor: 6)
        #expect(try await store.plannerTask(id: remote.id)?.categoryIDs == ["c1", "c2"])
        // A terminal marker wins over the pending retag: the row converges
        // to deleted and the queued intent is dropped.
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: local, deleted: true, revision: 7),
        ], cursor: 7)
        #expect(try await store.plannerTask(id: local.id) == nil)
        #expect(try await store.outboxRows().contains {
            $0.resource == "planner_task" && $0.recordID == local.id && $0.op != "delete"
        } == false)
        #expect(try await store.plannerTask(id: remote.id)?.categoryIDs == ["c1", "c2"])
    }
}

enum PlannerStoreSyncTestError: Error {
    case createFailed
}
