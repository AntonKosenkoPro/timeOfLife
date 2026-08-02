import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("CatalogService")
struct CatalogServiceTests {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CatalogServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeService(connected: Bool = true)
    -> (CatalogService, CatalogStore, FakeCatalogRepository, SyncQueue, UndoBuffer, MockConnectivity) {
        let dir = tempDir()
        let store = CatalogStore(directory: dir)
        let repo = FakeCatalogRepository()
        let queue = SyncQueue(url: dir)
        let undo = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: connected)
        let service = CatalogService(store: store, repository: repo, syncQueue: queue, undoBuffer: undo, connectivity: connectivity)
        return (service, store, repo, queue, undo, connectivity)
    }

    @Test("createActivity applies optimistically and drains the queue online")
    func createOptimisticAndDrain() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: true)
        let activity = TestCatalogFactory.activity(name: "Gym")

        try await service.createActivity(activity)

        #expect(await store.activity(activity.id) != nil)
        #expect(await queue.pending().isEmpty)
        #expect(repo.calls.contains(.createActivity(activity)))
    }

    @Test("updateActivity applies optimistically and syncs")
    func updateOptimistic() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: true)
        let activity = TestCatalogFactory.activity(name: "Gym")
        try await service.createActivity(activity)

        let renamed = TestCatalogFactory.activity(id: activity.id, name: "Lifting")
        try await service.updateActivity(renamed)

        #expect(await store.activity(activity.id)?.name == "Lifting")
        #expect(await queue.pending().isEmpty)
        #expect(repo.calls.contains(.updateActivity(renamed)))
    }

    @Test("deleteActivity holds in the undo buffer; store keeps it while held")
    func deleteHolds() async throws {
        let (service, store, _, queue, undo, _) = makeService(connected: true)
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)

        try await service.deleteActivity(activity)

        // Not committed to the store or enqueued while held (AC #6).
        #expect(await store.activity(activity.id) != nil)
        #expect(await queue.pending().isEmpty)
        let isHolding: Bool = if case .holding = undo.state { true } else { false }
        #expect(isHolding)
    }

    @Test("after the 30s window, the deletion commits locally and enqueues exactly one DELETE")
    func deleteCommitsAfterWindow() async throws {
        let (service, store, _, queue, undo, _) = makeService(connected: true)
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)

        try await service.deleteActivity(activity)
        // Simulate the undo window elapsing (the scheduler is `.none`).
        await undo.commit(now: Date().addingTimeInterval(31))

        #expect(await store.activity(activity.id) == nil)
        let pending = await queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.method == .delete)
        #expect(pending.first?.resource == .activity)
        #expect(undo.state == .empty)
    }

    @Test("undo within the window re-inserts and does not enqueue a DELETE")
    func undoRestores() async throws {
        let (service, store, _, queue, undo, _) = makeService(connected: true)
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)

        try await service.deleteActivity(activity)
        let restored = await service.undo()

        #expect(restored == .activity(activity))
        #expect(undo.state == .empty)
        #expect(await store.activity(activity.id) != nil)
        #expect(await queue.pending().isEmpty)
    }

    @Test("entry-only delete commits locally and enqueues an entry DELETE after the window")
    func entryOnlyDeleteCommits() async throws {
        let dir = tempDir()
        let entryStore = LocalTimerStore(url: dir.appendingPathComponent("timerQueue.json"))
        let store = CatalogStore(directory: dir)
        let repo = FakeCatalogRepository()
        let queue = SyncQueue(url: dir)
        let undo = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: true)
        let entriesRepo = FakeEntriesRepository()
        let service = CatalogService(
            store: store, repository: repo, syncQueue: queue, undoBuffer: undo,
            connectivity: connectivity, entryStore: entryStore, entriesRepository: entriesRepo
        )
        let activity = TestCatalogFactory.activity()
        let entry = TimeEntry(
            id: UUID.v7(), activityId: activity.id, startedAt: Date(), endedAt: Date(), synced: true
        )
        try await entryStore.save(entry)

        undo.record(.entryOnly(entry))
        await undo.commit(now: Date().addingTimeInterval(31))

        #expect(await entryStore.entryCount(forActivityId: activity.id) == 0)
        let pending = await queue.pending()
        #expect(pending.contains { $0.resource == .entry && $0.method == .delete })
    }

    @Test("undo restores the deleted entry in the local timer store")
    func entryOnlyUndoRestores() async throws {
        let dir = tempDir()
        let entryStore = LocalTimerStore(url: dir.appendingPathComponent("timerQueue.json"))
        let store = CatalogStore(directory: dir)
        let repo = FakeCatalogRepository()
        let queue = SyncQueue(url: dir)
        let undo = UndoBuffer(scheduler: .manual)
        let service = CatalogService(
            store: store, repository: repo, syncQueue: queue, undoBuffer: undo,
            connectivity: MockConnectivity(connected: true), entryStore: entryStore
        )
        let activity = TestCatalogFactory.activity()
        let entry = TimeEntry(
            id: UUID.v7(), activityId: activity.id, startedAt: Date(), endedAt: Date(), synced: true
        )
        try await entryStore.save(entry)
        try await entryStore.delete(id: entry.id)
        #expect(await entryStore.entryCount(forActivityId: activity.id) == 0)

        undo.record(.entryOnly(entry))
        let restored = await service.undo()

        #expect(restored == .entryOnly(entry))
        #expect(await entryStore.entryCount(forActivityId: activity.id) == 1)
    }

    @Test("caseInsensitiveReuse returns an existing activity by trimmed, lowercased name")
    func caseInsensitiveReuse() async throws {
        let (service, store, _, _, _, _) = makeService(connected: true)
        await store.upsertActivity(TestCatalogFactory.activity(name: "Gym"))

        let reuse = await service.caseInsensitiveReuse(named: "  gym ")
        #expect(reuse?.name == "Gym")
        #expect(await service.caseInsensitiveReuse(named: "Read") == nil)
    }

    @Test("seedCategories writes to the store and enqueues a POST per category")
    func seedCategories() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: true)
        let seeds = (0..<3).map { TestCatalogFactory.category(name: "C\($0)") }

        try await service.seedCategories(seeds)

        #expect(await store.loadCategories().count == 3)
        #expect(await queue.pending().isEmpty)
        #expect(repo.calls.filter { if case .createCategory = $0 { true } else { false } }.count == 3)
    }

    @Test("offline create applies optimistically but keeps the mutation queued")
    func offlineCreate() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: false)
        let activity = TestCatalogFactory.activity()

        try await service.createActivity(activity)

        #expect(await store.activity(activity.id) != nil)
        #expect(await queue.pending().count == 1)
        #expect(!repo.calls.contains(.createActivity(activity)))
    }

    @Test("offline category create remains queued until connectivity returns")
    func offlineCategoryCreate() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: false)
        let category = TestCatalogFactory.category()

        try await service.createCategory(category)

        #expect(await store.category(category.id) == category)
        let pending = await queue.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.resource == .category)
        #expect(pending.first?.method == .create)
        #expect(!repo.calls.contains(.createCategory(category)))
    }

    @Test("transient category create failure keeps its durable mutation")
    func transientCategoryFailureRemainsQueued() async throws {
        let (service, store, repo, queue, _, _) = makeService(connected: true)
        let category = TestCatalogFactory.category()
        repo.createCategoryError = APIError.transport(underlying: "connection reset")

        try await service.createCategory(category)

        #expect(await store.category(category.id) == category)
        #expect(await queue.pending().count == 1)
    }

    @Test("reconnect drains the queue (syncOnReconnect)")
    func syncOnReconnect() async throws {
        let (service, _, repo, queue, _, connectivity) = makeService(connected: false)
        let activity = TestCatalogFactory.activity()
        try await service.createActivity(activity)
        #expect(await queue.pending().count == 1)

        // Flip connectivity → the subscription spawns a replay.
        connectivity.isConnected = true
        for _ in 0..<40 {
            if await queue.pending().isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(await queue.pending().isEmpty)
        #expect(repo.calls.contains(.createActivity(activity)))
    }
}
