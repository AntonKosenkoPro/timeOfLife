import Testing
import Foundation
@testable import TimeOfLife

/// Planner notes sync (day-planner 15.1): the `notes` field intent pushes
/// only the text, adopts the relay text on conflict, resurrects once as a
/// notes-carrying create on `not_found`, and merges through the feed.
/// Split from `SyncPlannerTests` (file-length rule); mirrors
/// `SyncPlannerRetagTests`.
@MainActor
@Suite("Planner notes sync (day-planner 15.1)")
struct SyncPlannerNotesTests {
    @Test("notes sends only the text field")
    func notesIsFieldSpecific() async throws {
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
        _ = try await store.setPlannerTaskNotes(
            id: created.id, notes: "chapter 3", operationID: newOpID()
        )
        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { pushed.append($0) }
        mock.plannerFeedPages = [
            PlannerFeedPage(changes: [], watermarkRevision: 1, hasMore: false),
            PlannerFeedPage(changes: [], watermarkRevision: 2, hasMore: false),
        ]
        await controller.syncNow(userID: "u1")

        #expect(pushed.count == 1)
        #expect(pushed.first?.intent == "notes")
        #expect(pushed.first?.notes == "chapter 3")
        #expect(pushed.first?.name == nil)
        #expect(pushed.first?.positionKey == nil)
        #expect(pushed.first?.completedOn == nil)
        #expect(pushed.first?.categoryIDs == nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("a notes intent for a relay-unknown task resurrects once as a notes-carrying create")
    func notesResurrectCarriesNotes() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.setPlannerTaskNotes(
            id: task.id, notes: "chapter 3", operationID: newOpID()
        )
        // Drop the create row so the relay never saw the task (ghost relay
        // state), keeping only the notes intent.
        for row in try await store.outboxRows() where row.op == "create" {
            try await store.removeOutboxRow(id: row.id)
        }
        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { op in
            pushed.append(op)
            if op.intent == "notes" {
                throw APIError.server(code: "not_found", message: "missing")
            }
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(pushed.map(\.intent) == ["notes", "create"])
        #expect(pushed.last?.notes == "chapter 3")
        #expect(pushed.last?.name == "Read")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a conflicting create adopts the relay notes")
    func conflictAdoptsNotes() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.setPlannerTaskNotes(
            id: task.id, notes: "local", operationID: newOpID()
        )
        // Drop the create row so the relay never saw the task, then have
        // the resurrect collide: the 409 details carry the server notes.
        for row in try await store.outboxRows() where row.op == "create" {
            try await store.removeOutboxRow(id: row.id)
        }
        mock.applyPlannerOperationHandler = { op in
            if op.intent == "notes" {
                throw APIError.server(code: "not_found", message: "missing")
            }
            throw APIError.server(code: "planner_conflict", message: "collision", details: [
                "id": task.id,
                "name": "Read",
                "position_key": "500000",
                "revision": "9",
                "completed_on": "",
                "category_ids": "",
                "notes": "remote",
                "deleted": "false",
                "created_at": "2026-11-25T10:00:00.000Z",
                "updated_at": "2026-11-25T10:00:00.000Z",
            ])
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(try await store.plannerTask(id: task.id)?.notes == "remote")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("cross-device notes sync converges through the feed")
    func crossDeviceNotesSync() async throws {
        let store = try makeStore()
        let local = try await createTask(store, name: "Read", key: "500000")
        // A pending local notes edit stays visible when the feed carries an
        // older remote state for the same task (field-intent parity with
        // the retag merge: pending create/update wins, terminal delete wins).
        _ = try await store.setPlannerTaskNotes(
            id: local.id, notes: "local", operationID: UUID().uuidString
        )
        var remoteTask = local
        remoteTask.notes = "remote"
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: remoteTask, deleted: false, revision: 5),
        ], cursor: 5)
        #expect(try await store.plannerTask(id: local.id)?.notes == "local")

        // A fresh remote task merges with its notes intact.
        var remote = PlannerTask(
            id: UUID().uuidString, name: "Remote", positionKey: "500001",
            createdAt: Date(), updatedAt: Date()
        )
        remote.notes = "from the other device"
        try await store.applyPlannerPage(changes: [
            PlannerFeedChange(task: remote, deleted: false, revision: 6),
        ], cursor: 6)
        #expect(try await store.plannerTask(id: remote.id)?.notes == "from the other device")
    }

    // MARK: - Helpers (SyncPlannerTests mirror)

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

    private func makeStore() throws -> LocalStore {
        // swiftlint:disable:next force_try
        try! LocalStore(url: temporaryStoreURL())
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
