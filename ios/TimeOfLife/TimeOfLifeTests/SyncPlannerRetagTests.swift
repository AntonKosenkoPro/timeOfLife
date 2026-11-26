import Testing
import Foundation
@testable import TimeOfLife

/// Planner category sync (day-planner 14.1): the `retag` field intent
/// pushes only the ordered set, adopts the relay set on conflict, and a
/// `not_found` retag resurrects once as a tagged create so the relay never
/// loses the pending set. Split from `SyncPlannerTests` (file-length rule).
@MainActor
@Suite("Planner category sync (day-planner 14.1)")
struct SyncPlannerRetagTests {
    @Test("retag sends only the category set")
    func retagIsFieldSpecific() async throws {
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
        _ = try await store.retagPlannerTask(
            id: created.id, categoryIDs: ["c1", "c2"], operationID: newOpID()
        )
        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { pushed.append($0) }
        mock.plannerFeedPages = [
            PlannerFeedPage(changes: [], watermarkRevision: 1, hasMore: false),
            PlannerFeedPage(changes: [], watermarkRevision: 2, hasMore: false),
        ]
        await controller.syncNow(userID: "u1")

        #expect(pushed.count == 1)
        #expect(pushed.first?.intent == "retag")
        #expect(pushed.first?.categoryIDs == ["c1", "c2"])
        #expect(pushed.first?.name == nil)
        #expect(pushed.first?.positionKey == nil)
        #expect(pushed.first?.completedOn == nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("a retag for a relay-unknown task resurrects once as a tagged create")
    func retagResurrectCarriesCategories() async throws {
        let (store, mock, controller) = makeContext()
        let task = try await createTask(store, name: "Read", key: "500000")
        _ = try await store.retagPlannerTask(
            id: task.id, categoryIDs: ["c1", "c2"], operationID: newOpID()
        )
        // Drop the create row so the relay never saw the task (ghost relay
        // state), keeping only the retag.
        for row in try await store.outboxRows() where row.op == "create" {
            try await store.removeOutboxRow(id: row.id)
        }
        var pushed: [PlannerOperationPayload] = []
        mock.applyPlannerOperationHandler = { op in
            pushed.append(op)
            if op.intent == "retag" {
                throw APIError.server(code: "not_found", message: "missing")
            }
        }
        mock.plannerFeedPages = [PlannerFeedPage(changes: [], watermarkRevision: 0, hasMore: false)]

        controller.activate(userID: "u1")
        await waitForCycle(controller)

        #expect(pushed.map(\.intent) == ["retag", "create"])
        #expect(pushed.last?.categoryIDs == ["c1", "c2"])
        #expect(pushed.last?.name == "Read")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
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
