import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncController")
struct SyncControllerTests {

    @Test("first sync pulls before draining outbox")
    func firstSyncPullsBeforeDrain() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Local"))

        controller.activate()
        await waitForCycle(controller)

        let pullIndex = mock.calls.firstIndex { $0.method == "fetchActivities" }
        let pushIndex = mock.calls.firstIndex { $0.method == "createActivity" }
        #expect(pullIndex != nil)
        #expect(pushIndex != nil)
        if let pullIndex, let pushIndex {
            #expect(pullIndex < pushIndex)
        }
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("delta pull advances cursor and reuses it")
    func deltaPullAdvancesCursor() async throws {
        let (store, mock, controller) = makeContext()
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        mock.activitiesResult = [Activity(id: "a1", name: "Server", updatedAt: cursor)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.lastSyncedAt(resource: "activity") == cursor)

        mock.clearLog()
        await controller.syncNow()

        let activityFetch = mock.calls.firstIndex { $0.method == "fetchActivities" }
        #expect(activityFetch != nil)
        #expect(mock.fetchedModifiedSince.first == cursor)
    }

    @Test("LWW merge applies newer server activity")
    func lwwMergeAppliesNewerServerActivity() async throws {
        let (store, mock, controller) = makeContext()
        let local = Activity(
            id: "a1", name: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try await store.createActivity(local)
        let server = Activity(
            id: "a1", name: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        mock.activitiesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Server")
    }

    @Test("LWW merge keeps newer local activity")
    func lwwMergeKeepsNewerLocalActivity() async throws {
        let (store, mock, controller) = makeContext()
        let local = Activity(
            id: "a1", name: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.createActivity(local)
        let server = Activity(
            id: "a1", name: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        mock.activitiesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Local")
    }

    @Test("outbox drain is idempotent")
    func outboxDrainIsIdempotent() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "A"))
        try await store.createActivity(Activity(id: "a2", name: "B"))

        controller.activate()
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createActivity" }
        #expect(Set(pushes.compactMap(\.id)) == Set(["a1", "a2"]))
        #expect(try await store.outboxRows().isEmpty)

        mock.clearLog()
        try await store.createActivity(Activity(id: "b1", name: "C"))
        try await store.createActivity(Activity(id: "b2", name: "D"))
        let rowsBefore = try await store.outboxRows()

        await controller.syncNow()

        let replayPushes = mock.calls.filter { $0.method == "createActivity" }
        #expect(replayPushes.map(\.id) == rowsBefore.map(\.recordID))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("conflict adopts server version")
    func conflictAdoptsServerVersion() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Local"))
        let server = Activity(id: "a1", name: "Server", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        mock.createActivityHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchActivityHandler = { id in
            #expect(id == "a1")
            return server
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Server")
    }

    @Test("activity_exists remaps references to winning id")
    func activityExistsRemapsReferences() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: Date())
        )

        mock.createActivityHandler = { _ in
            throw APIError.server(
                code: "activity_exists", message: "exists",
                details: ["id": "server-id", "name": "Gym"]
            )
        }

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityID == "server-id")

        let remaining = try await store.outboxRows()
        #expect(remaining.allSatisfy { $0.resource == "entry" && $0.op == "update" })
        #expect(isIdle(controller.status))
    }

    @Test("not_found on delete is treated as success")
    func notFoundOnDeleteIsSuccess() async throws {
        let (store, mock, controller) = makeContext()
        try await store.deleteActivity(id: "a1")

        mock.deleteActivityHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.contains(Call("deleteActivity", "activity", "a1")))
        #expect(isIdle(controller.status))
    }

    @Test("offline activation errors without network calls")
    func offlineActivationErrorsWithoutNetworkCalls() async throws {
        let (_, mock, controller) = makeContext(connected: false)
        controller.activate()
        await waitForCycle(controller)

        #expect(mock.calls.isEmpty)
        #expect(controller.status == .error("offline"))
    }

    @Test("deactivate stops sync and syncNow is a no-op")
    func deactivateStopsSync() async throws {
        let (_, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        controller.deactivate()
        #expect(controller.status == .inactive)

        mock.clearLog()
        await controller.syncNow()
        #expect(mock.calls.isEmpty)
    }

    @Test("trigger is single-flight")
    func triggerIsSingleFlight() async throws {
        let (_, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        mock.clearLog()
        controller.trigger()
        controller.trigger()
        await waitUntil { mock.calls.count == 3 }

        let fetches = mock.calls.filter { $0.method == "fetchActivities" }
        #expect(fetches.count == 1)
    }

    // MARK: - Helpers

    private func makeContext(
        connected: Bool = true
    ) -> (store: LocalStore, mock: MockCatalogRepository, controller: SyncController) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        let connectivity = MockConnectivity(connected: connected)
        let undoBuffer = UndoBufferStore(store: store)
        let controller = SyncController(
            store: store, remote: mock, connectivity: connectivity, undoBuffer: undoBuffer
        )
        return (store, mock, controller)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func waitForCycle(_ controller: SyncController) async {
        await waitUntil {
            if case .syncing = controller.status { return false }
            return true
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
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

private typealias Call = MockCatalogRepository.Call
