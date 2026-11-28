import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TimerService")
struct TimerServiceTests {

    @Test("stopTimerDraft saves the entry with the final tags and clears the draft")
    func stopSavesEntryAndClearsDraft() async throws {
        let service = makeService()
        let store = service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: ["c1"], startedAt: startedAt)

        let endedAt = startedAt.addingTimeInterval(600)
        try await service.stopTimerDraft(
            text: "Gym",
            categoryIDs: ["c1"],
            startedAt: startedAt,
            endedAt: endedAt,
            notes: "evening session"
        )

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.activityText == "Gym")
        #expect(entries.first?.categoryIDs == ["c1"])
        #expect(entries.first?.notes == "evening session")
        #expect(entries.first?.durationSeconds == 600)
        #expect(try await store.outboxRows().filter { $0.resource == "entry" }.count == 1)
        #expect(try await service.runningTimerDraft() == nil)
    }

    @Test("startTimerDraft persists the running draft for crash recovery")
    func startPersistsDraft() async throws {
        let service = makeService()
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)

        try await service.startTimerDraft(text: "  Gym  ", categoryIDs: ["c2", "c1"], startedAt: startedAt)

        let draft = try await service.runningTimerDraft()
        #expect(draft?.activityText == "Gym")
        #expect(draft?.categoryIDs == ["c2", "c1"])
        #expect(draft?.status == "running")
    }

    @Test("in-progress drafts never enter the outbox")
    func draftsNeverSync() async throws {
        let service = makeService()
        try await service.startTimerDraft(text: "Work", categoryIDs: [], startedAt: Date())

        #expect(try await service.store.outboxRows().isEmpty)
    }

    @Test("updateTimerDraftNotes rewrites the persisted notes snapshot")
    func updateNotesPersists() async throws {
        let service = makeService()
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: Date())

        try await service.updateTimerDraftNotes("mid-run thought")

        let draft = try await service.runningTimerDraft()
        #expect(draft?.notes == "mid-run thought")
        #expect(draft?.activityText == "Gym")
    }

    @Test("updateTimerDraftStartedAt rewrites the start without touching the draft")
    func updateStartPersists() async throws {
        let service = makeService()
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: startedAt)
        let backdated = startedAt.addingTimeInterval(-600)

        try await service.updateTimerDraftStartedAt(backdated)

        let draft = try await service.runningTimerDraft()
        #expect(draft?.startedAt == backdated)
        #expect(draft?.activityText == "Gym")
        // The draft is never synced — Stop enqueues the single entry create.
        #expect(try await service.store.outboxRows().isEmpty)
    }

    @Test("updateTimerDraftStartedAt re-anchors the Live Activity singleton")
    func updateStartReanchorsLiveActivity() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let fake = FakeLiveActivities()
        let service = TimerService(store: store, liveActivities: fake)
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: startedAt)
        let backdated = startedAt.addingTimeInterval(-600)

        try await service.updateTimerDraftStartedAt(backdated)

        #expect(fake.startChanged == [backdated])
        // The edit re-anchors in place: no re-request (no restart risk),
        // no end.
        #expect(fake.started.count == 1)
        #expect(fake.ended.isEmpty)
    }

    @Test("a throwing store write still re-anchors and rethrows")
    func updateStartReanchorsOnStoreFailure() async throws {
        // An unbound store makes every write throw: the re-anchor must
        // still fire (the Island follows the in-memory elapsed the app
        // shows) and the error must propagate (no silent success).
        let store = LocalStore()
        let fake = FakeLiveActivities()
        let service = TimerService(store: store, liveActivities: fake)
        let backdated = Date(timeIntervalSince1970: 1_600_000_000)

        await #expect(throws: LocalStore.LocalStoreError.self) {
            try await service.updateTimerDraftStartedAt(backdated)
        }
        #expect(fake.startChanged == [backdated])
        #expect(fake.started.isEmpty)
        #expect(fake.ended.isEmpty)
    }

    // MARK: - Planner-linked runs (day-planner D3/D4)

    @Test("startLinkedTask claims the draft and links the task")
    func startLinkedClaimsDraft() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let claimed = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "chapter 3", taskID: "task-1", startedAt: startedAt
        )
        #expect(claimed)
        let draft = try #require(try await store.timerDraft())
        #expect(draft.plannerTaskID == "task-1")
        // Start copies the task notes into the draft (day-planner §15).
        #expect(draft.notes == "chapter 3")
        // A second linked Start never replaces the active run.
        let second = try await service.startLinkedTask(
            name: "Other", categoryIDs: [], notes: "", taskID: "task-2", startedAt: startedAt
        )
        #expect(!second)
        let kept = try #require(try await store.timerDraft())
        #expect(kept.activityText == "Read")
        #expect(kept.plannerTaskID == "task-1")
    }

    @Test("ordinary rewrites preserve a linked run's task id")
    func ordinaryRewritePreservesLink() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        // A mid-run retag (ordinary replace path) keeps the link.
        try await service.startTimerDraft(text: "Read", categoryIDs: [], startedAt: startedAt)
        let draft = try #require(try await store.timerDraft())
        #expect(draft.plannerTaskID == "task-1")
    }

    @Test("linked Stop saves the entry and completes exactly the task")
    func linkedStopCompletesTask() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        let receipt = try await service.stopTimerDraft(
            text: "Read",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600)
        )
        #expect(!receipt.entryID.isEmpty)
        let completed = try #require(try await store.plannerTask(id: "task-1"))
        #expect(completed.completedOn == PlannerCivilDate.today())
        let plannerOps = try await store.outboxRows().filter { $0.resource == "planner_task" }
        // The setup create plus the Stop-driven completion.
        #expect(plannerOps.count == 2)
        let completions = try plannerOps
            .map { try JSONDecoder().decode(PlannerOperationPayload.self, from: Data($0.payload!.utf8)) }
            .filter { $0.intent == PlannerIntent.complete.rawValue }
        #expect(completions.count == 1)
        let op = try #require(completions.first)
        #expect(op.taskID == "task-1")
        #expect(op.completedOn == PlannerCivilDate.today())
        #expect(try await service.runningTimerDraft() == nil)
    }

    @Test("Stop replays never rerun completion after reopen")
    func linkedStopReplayAfterReopen() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        let receipt = try await service.stopTimerDraft(
            text: "Read",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            entryID: "stop-1"
        )
        _ = try await store.reopenPlannerTask(id: "task-1", operationID: UUID().uuidString)
        // The same logical Stop retried: the entry converges, the task
        // stays open.
        let replay = try await service.stopTimerDraft(
            text: "Read",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            entryID: "stop-1"
        )
        #expect(replay.entryID == receipt.entryID)
        #expect(try await store.plannerTask(id: "task-1")?.completedOn == nil)
    }

    @Test("linked Stop against a deleted task saves an ordinary entry")
    func linkedStopDeletedTask() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        _ = try await store.deletePlannerTaskUndoable(id: "task-1")
        let outboxBefore = try await store.outboxRowCount()
        _ = try await service.stopTimerDraft(
            text: "Read",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600)
        )
        // Entry saved, task stays deleted, only the entry queued.
        #expect(try await store.entries().count == 1)
        #expect(try await store.plannerTask(id: "task-1") == nil)
        #expect(try await store.outboxRowCount() == outboxBefore + 1)
    }

    @Test("Stop uses the draft name and completes the renamed task by id")
    func linkedStopAfterMidRunRename() async throws {
        let service = makeService()
        let store = service.store
        _ = try await store.createPlannerTask(
            id: "task-1", name: "Read", positionKey: "500000",
            operationID: UUID().uuidString
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try await service.startLinkedTask(
            name: "Read", categoryIDs: [], notes: "", taskID: "task-1", startedAt: startedAt
        )
        // The task is renamed mid-run: Stop keeps the draft's locked name
        // for the entry and completes the task by id without reverting it.
        _ = try await store.renamePlannerTask(id: "task-1", name: "Read books", operationID: UUID().uuidString)
        let receipt = try await service.stopTimerDraft(
            text: "Read",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600)
        )
        #expect(!receipt.entryID.isEmpty)
        let entries = try await store.entries()
        #expect(entries.first?.activityText == "Read")
        let completed = try #require(try await store.plannerTask(id: "task-1"))
        #expect(completed.name == "Read books")
        #expect(completed.completedOn == PlannerCivilDate.today())
    }

    @Test("ordinary Stop carries no planner link or op")
    func ordinaryStopUnchanged() async throws {
        let service = makeService()
        let store = service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await service.startTimerDraft(text: "Gym", categoryIDs: [], startedAt: startedAt)
        _ = try await service.stopTimerDraft(
            text: "Gym",
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600)
        )
        #expect(try await store.outboxRows().allSatisfy { $0.resource == "entry" })
    }

    // MARK: - Helpers

    private func makeService() -> TimerService {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        return TimerService(store: store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }
}
