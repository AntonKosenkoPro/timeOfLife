import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("Planner sync (day-planner 2.4)")
struct SyncPlannerTests {
    // MARK: - Push: field intents, terminal deletes

    @Test("a local create pushes its intent and pulls its acknowledgement")
    func createPushPull() async throws {
        let (store, mock, controller) = makeContext()
        let created = try await createTask(store, name: "Read", key: "500000")

        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { pushed.append($0) }
        // Pre-drain pull is empty; post-drain pull delivers the ack.
        mock.plannerFeedPages = [
            PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false),
            PlannerFeedPage(
                changes: [PlannerFeedChange(task: created, deleted: false, revision: 1)],
                watermarkRevision: 1, hasMore: false
            ),
        ]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(pushed.count == 1)
        #expect(pushed.first?.intent == PlannerIntent.create.rawValue)
        #expect(pushed.first?.taskID == created.id)
        #expect(pushed.first?.name == "Read")
        #expect(pushed.first?.positionKey == "500000")
        #expect(pushed.first?.completedOn == nil)
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
        // The ack lands on the next cycle's pull (first sync never pulls
        // after its drain — same as entries).
        #expect(try await store.plannerRevisionCursor() == 0)
        await controller.syncNow(userID: "u1")
        #expect(try await store.plannerRevisionCursor() == 1)
        #expect(isIdle(controller.status))
    }

    @Test("rename sends only the name field")
    func renameIsFieldSpecific() async throws {
        let (store, mock, controller) = makeContext()
        let created = try await createTask(store, name: "Read", key: "500000")
        mock.plannerFeedPages = [
            PlannerFeedPage(
                changes: [PlannerFeedChange(task: created, deleted: false, revision: 1)],
                watermarkRevision: 1, hasMore: false
            ),
        ]
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        mock.clearLog()
        _ = try await store.renamePlannerTask(id: created.id, name: "Read books", operationID: newOpID())
        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { pushed.append($0) }
        mock.plannerFeedPages = [
            PlannerFeedPage(changes: [], watermarkRevision: 1, hasMore: false),
            PlannerFeedPage(changes: [], watermarkRevision: 2, hasMore: false),
        ]
        await controller.syncNow(userID: "u1")

        #expect(pushed.count == 1)
        #expect(pushed.first?.intent == "rename")
        #expect(pushed.first?.name == "Read books")
        #expect(pushed.first?.positionKey == nil)
        #expect(pushed.first?.completedOn == nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("a resumed pull replays from its cursor without gaps or duplicates")
    func resumedPull() async throws {
        let (store, mock, _) = makeContext()
        let t1 = PlannerTask(id: "t1", name: "A", positionKey: "500000", createdAt: Date(), updatedAt: Date())
        let t2 = PlannerTask(id: "t2", name: "B", positionKey: "500001", createdAt: Date(), updatedAt: Date())
        let t3 = PlannerTask(id: "t3", name: "C", positionKey: "500002", createdAt: Date(), updatedAt: Date())
        var seenAfter: [Int64] = []
        mock.fetchPlannerFeedHandler = { after, _ in
            seenAfter.append(after)
            if after == 0 {
                return PlannerFeedPage(
                    changes: [
                        PlannerFeedChange(task: t1, deleted: false, revision: 1),
                        PlannerFeedChange(task: t2, deleted: false, revision: 2),
                    ],
                    watermarkRevision: 5, hasMore: true
                )
            }
            return PlannerFeedPage(
                changes: [PlannerFeedChange(task: t3, deleted: false, revision: 3)],
                watermarkRevision: 5, hasMore: false
            )
        }
        let controller = makeController(store: store, mock: mock)
        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(seenAfter == [0, 2])
        #expect(try await store.plannerTasks().map(\.id).sorted() == ["t1", "t2", "t3"])
        #expect(try await store.plannerRevisionCursor() == 3)
        #expect(isIdle(controller.status))
    }

    @Test("Stop completion queued offline converges to deleted without recreating")
    func stopVsRemoteDelete() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        // A linked Stop saved the entry and queued the completion offline.
        _ = try await store.claimTimerDraft(
            activityText: "Read", categoryIDs: [], startedAt: Date(), plannerTaskID: task.id
        )
        let entry = TimeEntry(
            id: "stop-entry-1", activityText: "Read",
            startedAt: Date().addingTimeInterval(-60), endedAt: Date(), durationSeconds: 60
        )
        _ = try await store.stopRunningTimer(entry, plannerLink: LocalStore.PlannerStopLink(
            taskID: task.id, operationID: newOpID(), completedOn: "2026-11-25"
        ))
        // Meanwhile the relay deleted the task on another device.
        mock.plannerFeedPages = [
            PlannerFeedPage(
                changes: [PlannerFeedChange(task: task, deleted: true, revision: 9)],
                watermarkRevision: 9, hasMore: false
            ),
            PlannerFeedPage(changes: [], watermarkRevision: 9, hasMore: false),
        ]
        var pushedOps: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = {
            pushedOps.append($0)
            throw APIError.server(code: "planner_gone", message: "deleted")
        }
        var pushedEntries: [TimeEntry] = []
        mock.createEntryHandler = { pushedEntries.append($0) }

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        // The entry syncs normally; the task converges to deleted and its
        // pending completion never recreates it.
        #expect(pushedEntries.map(\.id) == ["stop-entry-1"])
        #expect(pushedOps.isEmpty)
        #expect(try await store.plannerTask(id: task.id) == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a terminal delete answers 410 by converging, not retrying")
    func goneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.renamePlannerTask(id: task.id, name: "Late", operationID: newOpID())
        mock.applyPlannerOperationHandler = { _ in
            throw APIError.server(code: "planner_gone", message: "deleted")
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(try await store.plannerTask(id: task.id) == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a create collision adopts the relay version from details")
    func conflictAdopts() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Local", key: "500000")
        let storedBefore = try await store.plannerTask(id: task.id)
        mock.applyPlannerOperationHandler = { _ in
            throw APIError.server(code: "planner_conflict", message: "exists", details: [
                "id": task.id,
                "name": "Relay",
                "position_key": "500007",
                "revision": "4",
                "completed_on": "2026-11-24",
                "category_ids": "c1,c2",
                "deleted": "false",
                "created_at": "2026-11-24T09:00:00.000Z",
                "updated_at": "2026-11-24T10:00:00.000Z",
            ])
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 4, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        let adopted = try await store.plannerTask(id: task.id)
        #expect(adopted?.name == "Relay")
        #expect(adopted?.positionKey == "500007")
        #expect(adopted?.completedOn == "2026-11-24")
        #expect(adopted?.categoryIDs == ["c1", "c2"])
        #expect(adopted?.updatedAt == WireDate.parse("2026-11-24T10:00:00.000Z"))
        // created_at is local-only (entries merge precedent): adoption keeps it.
        #expect(adopted?.createdAt == storedBefore?.createdAt)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a delete push answers relay-404 as success")
    func deleteNotFoundResolves() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.deletePlannerTaskUndoable(id: task.id)
        try await store.undoBufferCommitAll()
        mock.applyPlannerOperationHandler = { _ in
            throw APIError.server(code: "not_found", message: "missing")
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("an update for a relay-unknown task resurrects once as a create")
    func notFoundResurrectsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.renamePlannerTask(id: task.id, name: "Renamed", operationID: newOpID())
        // Drop the create row so the relay never saw the task (ghost relay
        // state), keeping only the rename.
        for row in try await store.outboxRows() where row.op == "create" {
            try await store.removeOutboxRow(id: row.id)
        }
        var intents: [String] = []
        mock.applyPlannerOperationHandler = { op in
            intents.append(op.intent)
            if op.intent == "rename" {
                throw APIError.server(code: "not_found", message: "missing")
            }
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(intents == ["rename", "create"])
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    // MARK: - Graceful behavior against an older relay

    @Test("a pre-planner relay leaves planner rows queued and entry sync usable")
    func olderRelayDegradesGracefully() async throws {
        let (store, mock, controller) = makeContext()
        _ = try await createTask(store, name: "Read", key: "500000")
        let entry = TimeEntry(
            id: "entry-1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        )
        _ = try await store.createEntry(entry)
        // A pre-planner relay: no feed route, no operations route.
        mock.fetchPlannerFeedHandler = { _, _ in
            throw APIError.server(code: "http_404", message: "nope")
        }
        var pushedOps = 0
        mock.applyPlannerOperationHandler = { _ in
            pushedOps += 1
            throw APIError.server(code: "http_404", message: "nope")
        }
        var pushedEntries: [TimeEntry] = []
        mock.createEntryHandler = { pushedEntries.append($0) }

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        // Ordinary sync usable: the entry converged; planner rows stayed
        // queued without wedging the cycle.
        #expect(pushedEntries.map(\.id) == ["entry-1"])
        #expect(pushedOps == 0)
        #expect(try await store.outboxRowCount() == 1)
        #expect(try await store.plannerRevisionCursor() == 0)
        #expect(isIdle(controller.status))
    }

    @Test("entry and category sync are unaffected by planner traffic")
    func entryCategorySyncUnaffected() async throws {
        let (store, mock, controller) = makeContext()
        let entry = TimeEntry(
            id: "entry-1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        )
        _ = try await store.createEntry(entry)
        _ = try await createTask(store, name: "Read", key: "500000")
        var pushedEntries: [TimeEntry] = []
        mock.createEntryHandler = { pushedEntries.append($0) }
        var pushedOps: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { pushedOps.append($0) }
        mock.entriesResult = [entry]
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(pushedEntries.map(\.id) == ["entry-1"])
        #expect(pushedOps.count == 1)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.entry(id: "entry-1") != nil)
        #expect(isIdle(controller.status))
    }

    // MARK: - Helpers

    private func createTask(_ store: LocalStore, name: String, key: String) async throws -> PlannerTask {
        let result = try await store.createPlannerTask(
            id: UUID().uuidString, name: name, positionKey: key,
            operationID: UUID().uuidString
        )
        guard case let .saved(task) = result else {
            Issue.record("create failed: \(result)")
            throw PlannerSyncTestError.createFailed
        }
        return task
    }

    private func newOpID() -> String { UUID().uuidString }

    private func makeContext() -> (store: LocalStore, mock: MockCatalogRepository, controller: SyncController) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        return (store, mock, makeController(store: store, mock: mock))
    }

    private func makeController(store: LocalStore, mock: MockCatalogRepository) -> SyncController {
        SyncController(
            store: store,
            remote: mock,
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func waitForCycle(_ controller: SyncController) async {
        await waitUntil {
            if case .syncing = controller.status { return false }
            return true
        }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func isIdle(_ status: SyncController.SyncStatus) -> Bool {
        if case .idle = status { return true }
        return false
    }
}

enum PlannerSyncTestError: Error {
    case createFailed
}
