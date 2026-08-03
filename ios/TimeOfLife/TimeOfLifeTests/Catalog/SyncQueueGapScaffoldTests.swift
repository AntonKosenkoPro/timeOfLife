// RED-PHASE ATDD scaffold — disabled until the behavior is verified/implemented. Activate by removing .disabled() during the green phase.
import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncQueueGapScaffold")
struct SyncQueueGapScaffoldTests {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SyncQueueGapScaffoldTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Durability (1.1-UNIT-003)

    @Test("durable queue across relaunch for update/delete/category", .disabled())
    func durableAcrossRelaunch() async throws {
        // RED: the existing enqueuePersists covers only create/.activity; update/delete/category survival across a new SyncQueue instance is uncovered.
        let dir = tempDir()
        let queue = SyncQueue(url: dir)
        let activity = TestCatalogFactory.activity()
        let category = TestCatalogFactory.category()
        try await queue.enqueue(
            .update(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )
        try await queue.enqueue(.delete(resource: .activity, resourceId: activity.id, updatedAt: Date()))
        try await queue.enqueue(
            .create(resource: .category, resourceId: category.id,
                    payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
        )
        try await queue.enqueue(.delete(resource: .category, resourceId: category.id, updatedAt: Date()))

        let reopened = SyncQueue(url: dir)
        let pending = await reopened.pending()
        #expect(pending.count == 4)
        #expect(pending.contains { $0.resource == .activity && $0.method == .update && $0.resourceId == activity.id })
        #expect(pending.contains { $0.resource == .activity && $0.method == .delete && $0.resourceId == activity.id })
        #expect(pending.contains { $0.resource == .category && $0.method == .create && $0.resourceId == category.id })
        #expect(pending.contains { $0.resource == .category && $0.method == .delete && $0.resourceId == category.id })
    }

    // MARK: - FIFO ordering (1.1-UNIT-004)

    @Test("FIFO order preserved on replay", .disabled())
    func fifoOrderOnReplay() async throws {
        // RED: replay must process pending mutations in enqueue order; existing replay tests never assert call order across multiple entries.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let first = TestCatalogFactory.activity(name: "Alpha")
        let second = TestCatalogFactory.activity(name: "Beta")
        let third = TestCatalogFactory.activity(name: "Gamma")
        for activity in [first, second, third] {
            try await queue.enqueue(
                .create(resource: .activity, resourceId: activity.id,
                        payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
            )
        }

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        #expect(repo.calls == [
            .createActivity(first), .createActivity(second), .createActivity(third)
        ])
    }

    // MARK: - Attempts / retry policy (1.1-UNIT-004)

    @Test("attempts increments and drops at maxAttempts = 5", .disabled())
    func attemptsDropAtMax() async throws {
        // RED: a transiently failing mutation must accumulate attempts and be dropped once attempts >= 5 (SyncQueue.maxAttempts); the drop path is uncovered.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let activity = TestCatalogFactory.activity()
        repo.createActivityError = APIError.transport(underlying: "reset")
        try await queue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        for expectedAttempts in 1...4 {
            await queue.replay(using: repo, store: store, connectivity: connectivity)
            #expect((await queue.pending()).first?.attempts == expectedAttempts)
        }
        // Fifth failure reaches attempts == 5 >= maxAttempts → dropped.
        await queue.replay(using: repo, store: store, connectivity: connectivity)
        #expect(await queue.pending().isEmpty)
    }

    @Test("422 validation_error keeps the entry for retry, never drops silently", .disabled())
    func validationKeepsEntry() async throws {
        // RED: replayActivityCreate returns .done on CatalogError.validation (SyncQueue.swift:197-198), silently dropping the entry; the story contract says a 422 must stay pending for retry after the user fixes the payload.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let activity = TestCatalogFactory.activity()
        repo.createActivityError = CatalogError.validation(fields: ["name": "bad"])
        try await queue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: JSONEncoder().encode(activity), updatedAt: activity.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)
        #expect((await queue.pending()).count == 1)
        await queue.replay(using: repo, store: store, connectivity: connectivity)
        #expect((await queue.pending()).count == 1)

        repo.createActivityError = nil
        await queue.replay(using: repo, store: store, connectivity: connectivity)
        #expect(await queue.pending().isEmpty)
    }

    // MARK: - Category replay (1.1-UNIT-005)

    @Test("category replay: create success adopts canonical", .disabled())
    func categoryCreateAdoptsCanonical() async throws {
        // RED: the category create replay path is uncovered; success must adopt the repository's canonical record and drain the queue.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let category = TestCatalogFactory.category(name: "Sport")
        try await queue.enqueue(
            .create(resource: .category, resourceId: category.id,
                    payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        let stored = await store.category(category.id)
        #expect(stored != nil)
        #expect(stored?.name == "Sport")
        #expect(repo.calls.contains(.createCategory(category)))
    }

    @Test("category replay: category_exists re-maps local refs", .disabled())
    func categoryExistsRemapsRefs() async throws {
        // RED: the category_exists remap path is uncovered; contract asserts activity tags rewritten to the survivor id, old category removed from store, and the queue drained (note: remapCategory currently enqueues cascaded activity updates — SyncQueue.swift:354-366 — so this stays RED until the queue-empty contract is settled).
        let (queue, store, repo, connectivity) = makeCollaborators()
        let oldId = UUID.v7()
        let survivorId = UUID.v7()
        let category = TestCatalogFactory.category(id: oldId, name: "Sport")
        repo.createCategoryError = CatalogError.categoryExists(existingId: survivorId, existingName: "Sport")
        await store.upsertActivity(TestCatalogFactory.activity(name: "A", categoryIds: [oldId]))
        try await queue.enqueue(
            .create(resource: .category, resourceId: oldId,
                    payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        let activity = await store.activity(named: "a")
        #expect(activity?.categoryIds == [survivorId])
        #expect(await store.category(oldId) == nil)
        #expect(await queue.pending().isEmpty)
    }

    @Test("category replay: conflict keep-latest via getCategory", .disabled())
    func categoryConflictKeepsLatest() async throws {
        // RED: the category 409-conflict keep-latest path (getCategory + adopt server version) is uncovered.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let category = TestCatalogFactory.category(name: "Sport")
        let serverVersion = TestCatalogFactory.category(
            id: category.id, name: "Sport (server)", updatedAt: Date(timeIntervalSince1970: 999)
        )
        repo.updateCategoryError = CatalogError.conflict(
            serverUpdatedAt: CatalogDateCoding.decode("2026-07-27T09:00:00Z")
        )
        repo.categoryResult = serverVersion
        try await queue.enqueue(
            .update(resource: .category, resourceId: category.id,
                    payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
        let stored = await store.category(category.id)
        #expect(stored?.name == "Sport (server)")
        #expect(repo.calls.contains(.getCategory(category.id)))
    }

    @Test("category replay: 404 on DELETE is success", .disabled())
    func categoryDeleteNotFoundIsSuccess() async throws {
        // RED: the category DELETE 404-as-success path is uncovered (the activity analog is covered).
        let (queue, store, repo, connectivity) = makeCollaborators()
        let id = UUID.v7()
        repo.deleteCategoryError = CatalogError.notFound
        try await queue.enqueue(.delete(resource: .category, resourceId: id, updatedAt: Date()))

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect(await queue.pending().isEmpty)
    }

    @Test("category replay: offline stops mid-replay leaving the rest", .disabled())
    func categoryOfflineStopsReplay() async throws {
        // RED: the offline mid-replay stop path is uncovered for categories (activity analog exists); remaining category mutations must stay pending with no further repo calls.
        let (queue, store, repo, connectivity) = makeCollaborators()
        repo.createCategoryError = CatalogError.offline
        for _ in 0..<2 {
            let category = TestCatalogFactory.category()
            try await queue.enqueue(
                .create(resource: .category, resourceId: category.id,
                        payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
            )
        }

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        #expect((await queue.pending()).count == 2)
        #expect(repo.calls.count == 1)
    }

    // MARK: - Remap cascade (1.1-UNIT-006)

    @Test("category remap cascades activity-update mutations without duplicates", .disabled())
    func categoryRemapCascadesActivityUpdates() async throws {
        // RED: a category_exists remap must enqueue exactly one .update .activity mutation per affected activity (categoryIds rewritten to the survivor), with no duplicate resourceId — the cascade path is uncovered.
        let (queue, store, repo, connectivity) = makeCollaborators()
        let oldId = UUID.v7()
        let survivorId = UUID.v7()
        let category = TestCatalogFactory.category(id: oldId, name: "Sport")
        repo.createCategoryError = CatalogError.categoryExists(existingId: survivorId, existingName: "Sport")
        let activityA = TestCatalogFactory.activity(name: "A", categoryIds: [oldId])
        let activityB = TestCatalogFactory.activity(name: "B", categoryIds: [oldId])
        await store.upsertActivity(activityA)
        await store.upsertActivity(activityB)
        try await queue.enqueue(
            .create(resource: .category, resourceId: oldId,
                    payload: JSONEncoder().encode(category), updatedAt: category.updatedAt)
        )

        await queue.replay(using: repo, store: store, connectivity: connectivity)

        let pending = await queue.pending()
        let updates = pending.filter { $0.resource == .activity && $0.method == .update }
        #expect(updates.count == 2)
        #expect(Set(updates.map(\.resourceId)) == [activityA.id, activityB.id])
        for mutation in updates {
            let activity = try #require(try? JSONDecoder().decode(Activity.self, from: mutation.payload))
            #expect(activity.categoryIds == [survivorId])
        }
    }

    // MARK: - Corruption quarantine (1.1-UNIT-007)

    @Test("corrupt queue file is quarantined, not lost or silently empty", .disabled())
    func corruptQueueFileIsQuarantined() async throws {
        // RED: a corrupt syncQueue.json must be moved to syncQueue.corrupted.<ts>.json on load — never silently lost, never blocking the queue; the quarantine behavior is uncovered.
        let dir = tempDir()
        let queueURL = dir.appendingPathComponent("syncQueue.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        try Data("not-json-garbage".utf8).write(to: queueURL)

        let queue = SyncQueue(url: dir)
        let pending = await queue.pending()

        #expect(pending.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("syncQueue.corrupted.") && $0.hasSuffix(".json") })
        #expect(!FileManager.default.fileExists(atPath: queueURL.path))
    }
}
