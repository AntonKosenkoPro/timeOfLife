import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncQueue")
struct SyncQueueTests {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SyncQueueTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Builds a real store + queue (temp dir) and a fake repo + connectivity.
    private func makeCollaborators(connected: Bool = true)
    -> (SyncQueue, CatalogStore, FakeCatalogRepository, MockConnectivity) {
        let dir = tempDir()
        let queue = SyncQueue(url: dir)
        let store = CatalogStore(directory: dir)
        let repo = FakeCatalogRepository()
        let connectivity = MockConnectivity(connected: connected)
        return (queue, store, repo, connectivity)
    }

    @Test("enqueue persists across a new instance")
    func enqueuePersists() async throws {
        let dir = tempDir()
        let queue = SyncQueue(url: dir)
        let activity = TestCatalogFactory.activity()
        try await queue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        let reopened = SyncQueue(url: dir)
        let pending = await reopened.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.resource == .activity)
        #expect(pending.first?.method == .create)
    }

    @Test("replay success removes the entry and adopts the canonical record")
    func replaySuccess() async throws {
        let (queue, store, repo, connectivity) = makeCollaborators()
        let activity = TestCatalogFactory.activity(name: "Gym")
        try await queue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        let stored = await store.activity(activity.id)
        #expect(stored != nil)
        #expect(stored?.name == "Gym")
        #expect(repo.calls.contains(.createActivity(activity)))
    }

    @Test("idempotent POST replay (same id) is success, no error surfaced")
    func idempotentPost() async throws {
        let (queue, store, repo, connectivity) = makeCollaborators()
        let activity = TestCatalogFactory.activity()
        // The fake returns the activity (the server's idempotent 200 on same id).
        try await queue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        #expect(await store.activity(activity.id) != nil)
    }

    @Test("409 conflict adopts the server version and removes the entry")
    func conflictKeepsLatest() async throws {
        let (queue, store, repo, connectivity) = makeCollaborators()
        let activity = TestCatalogFactory.activity(name: "Gym")
        let serverVersion = TestCatalogFactory.activity(
            id: activity.id, name: "Gym (server)", updatedAt: Date(timeIntervalSince1970: 999)
        )
        repo.updateActivityError = CatalogError.conflict(
            serverUpdatedAt: CatalogDateCoding.decode("2026-07-27T09:00:00Z")
        )
        repo.activityResult = serverVersion
        try await queue.enqueue(
            .update(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        let stored = await store.activity(activity.id)
        #expect(stored?.name == "Gym (server)")
        #expect(repo.calls.contains(.getActivity(activity.id)))
    }

    @Test("409 activity_exists re-maps to the surviving id and removes the entry")
    func activityExistsRemaps() async throws {
        let (queue, store, repo, connectivity) = makeCollaborators()
        let oldId = UUID.v7()
        let survivorId = UUID.v7()
        let activity = TestCatalogFactory.activity(id: oldId, name: "Gym")
        let survivor = TestCatalogFactory.activity(id: survivorId, name: "Gym")
        repo.createActivityError = CatalogError.activityExists(
            existingId: survivorId, existingName: "Gym"
        )
        repo.activityResult = survivor
        try await queue.enqueue(
            .create(resource: .activity, resourceId: oldId,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        #expect(await store.activity(survivorId) != nil)
        #expect(await store.activity(oldId) == nil)
    }

    @Test("404 on DELETE is treated as success and removes the entry")
    func deleteNotFoundIsSuccess() async throws {
        let (queue, store, repo, connectivity) = makeCollaborators()
        let id = UUID.v7()
        repo.deleteActivityError = CatalogError.notFound
        try await queue.enqueue(.delete(resource: .activity, resourceId: id, updatedAt: Date()))

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
    }

    @Test("offline mid-replay stops and leaves the remaining entries")
    func offlineStopsReplay() async throws {
        let (queue, _, repo, connectivity) = makeCollaborators(connected: true)
        repo.createActivityError = CatalogError.offline
        for _ in 0..<3 {
            let a = TestCatalogFactory.activity()
            try await queue.enqueue(
                .create(resource: .activity, resourceId: a.id,
                        payload: JSONEncoder().encode(a), updatedAt: a.updatedAt)
            )
        }

        await queue.replay(using: repo, store: CatalogStore(directory: tempDir()), connectivity: connectivity)

        #expect(await queue.pending().count == 3)
    }

    @Test("offline guard skips replay entirely")
    func offlineGuardSkips() async throws {
        let (queue, _, repo, connectivity) = makeCollaborators(connected: false)
        let a = TestCatalogFactory.activity()
        try await queue.enqueue(
            .create(resource: .activity, resourceId: a.id,
                    payload: JSONEncoder().encode(a), updatedAt: a.updatedAt)
        )

        await queue.replay(using: repo, store: CatalogStore(directory: tempDir()), connectivity: connectivity)

        #expect(await queue.pending().count == 1)
        #expect(repo.calls.isEmpty)
    }
}
