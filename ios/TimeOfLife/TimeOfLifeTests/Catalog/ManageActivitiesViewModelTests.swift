import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ManageActivitiesViewModel")
struct ManageActivitiesViewModelTests {
    private final class EntryCounter: ActivityEntryCounting, @unchecked Sendable {
        var count = 0
        var latest: TimeEntry?

        func entryCount(forActivityId id: UUID) async -> Int {
            _ = id
            return count
        }

        func latestEntry(forActivityId id: UUID) async -> TimeEntry? {
            _ = id
            return latest
        }
    }

    private func make() -> (
        ManageActivitiesViewModel, MockCatalogStore, FakeCatalogRepository, SyncQueue, UndoBuffer, EntryCounter, CatalogService
    ) {
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let queue = SyncQueue(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
        let undo = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: true)
        let service = CatalogService(
            store: store, repository: repository, syncQueue: queue,
            undoBuffer: undo, connectivity: connectivity
        )
        let counter = EntryCounter()
        let vm = ManageActivitiesViewModel(
            store: store, service: service, repository: repository,
            undoBuffer: undo, entryCounter: counter
        )
        return (vm, store, repository, queue, undo, counter, service)
    }

    @Test("loads activities from the local store in recency order without a network call")
    func loadsOfflineFirst() async {
        let (vm, store, repository, _, _, _, _) = make()
        let old = TestCatalogFactory.activity(name: "Old", lastUsedAt: Date(timeIntervalSince1970: 1))
        let recent = TestCatalogFactory.activity(name: "Recent", lastUsedAt: Date(timeIntervalSince1970: 2))
        await store.upsertActivity(old)
        await store.upsertActivity(recent)

        await vm.load()

        #expect(vm.activities.map(\.name) == ["Recent", "Old"])
        #expect(repository.calls.isEmpty)
    }

    @Test("optimistically removes an activity and undo restores it")
    func deleteAndUndo() async {
        let (vm, store, _, _, _, _, _) = make()
        let activity = TestCatalogFactory.activity(name: "Reading")
        await store.upsertActivity(activity)
        await vm.load()

        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .all)
        #expect(vm.activities.isEmpty)

        await vm.performUndo()
        #expect(vm.activities == [activity])
    }

    @Test("scope confirmation is selected when entries exist and dismissal clears pending state")
    func scopeAndDismissal() async {
        let (vm, store, _, _, _, counter, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        counter.count = 3

        await vm.requestDelete(activity)
        #expect(vm.showDeleteScope)
        #expect(vm.entryCount(for: activity) == 3)
        vm.showDeleteScope = false
        #expect(vm.pendingDelete == nil)
    }

    @Test("expiry commits the deletion and enqueues a server delete")
    func expiryCommits() async {
        let (vm, store, _, queue, undo, _, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .all)

        await undo.commit(now: Date().addingTimeInterval(31))

        #expect(await store.activity(activity.id) == nil)
        let pending = await queue.pending()
        #expect(pending.contains { $0.method == .delete })
    }

    @Test("entry-only delete keeps the activity row, holds the latest entry, and is undoable")
    func entryOnlyKeepsActivity() async {
        let (vm, store, _, _, undo, counter, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        let entry = TimeEntry(
            id: UUID.v7(), activityId: activity.id, startedAt: Date(), endedAt: Date(), synced: true
        )
        counter.count = 2
        counter.latest = entry
        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .entryOnly)

        #expect(vm.activities == [activity])
        guard case let .holding(.entryOnly(held), expiresAt: _) = undo.state else {
            Issue.record("Expected entry-only undo item")
            return
        }
        #expect(held == entry)
    }

    @Test("shake undo restores the held activity")
    func shakeUndo() async {
        let (vm, store, _, _, _, _, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .all)

        vm.onShake()
        for _ in 0..<10 where vm.activities.isEmpty {
            await Task.yield()
        }

        #expect(vm.activities == [activity])
    }

    @Test("a 409 conflict on sync adopts the server version and shows the conflict banner")
    func conflictKeepLatest() async {
        let (vm, store, repository, queue, _, _, service) = make()
        let original = TestCatalogFactory.activity(name: "Old")
        let latest = TestCatalogFactory.activity(id: original.id, name: "Latest")
        await store.upsertActivity(original)
        await vm.load()
        repository.updateActivityError = CatalogError.conflict(serverUpdatedAt: latest.updatedAt)
        repository.activityResult = latest

        // Queued update that conflicts during replay.
        guard let data = try? JSONEncoder().encode(latest) else {
            Issue.record("Failed to encode")
            return
        }
        try? await queue.enqueue(
            .update(resource: .activity, resourceId: original.id,
                    payload: data, updatedAt: latest.updatedAt)
        )

        // Replay pops the mutation → conflict → adopts the server version and
        // bumps storeRevision; the VM sink refreshes the list.
        await service.syncNow()
        for _ in 0..<10 where !vm.activities.contains(where: { $0.name == "Latest" }) {
            await Task.yield()
        }

        #expect(vm.activities.contains { $0.name == "Latest" })
        #expect(vm.errorMessage == L10n.errorConflict.text)
    }

    @Test("a 404 on a queued DELETE is treated as success")
    func deleteNotFoundIsSuccess() async {
        let (vm, store, repository, queue, undo, _, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        repository.deleteActivityError = CatalogError.notFound

        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .all)
        await undo.commit(now: Date().addingTimeInterval(31))

        #expect(await store.activity(activity.id) == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test("bulk delete with entries holds the activity and restores it as a unit")
    func bulkDeleteUndoRestoresUnit() async {
        let (vm, store, _, _, undo, counter, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        counter.count = 3

        await vm.requestDelete(activity)
        await vm.performDelete(activity, scope: .all)

        guard case let .holding(.activityWithEntries(held), expiresAt: _) = undo.state else {
            Issue.record("Expected activityWithEntries undo item")
            return
        }
        #expect(held == activity)
        #expect(vm.activities.isEmpty)

        await vm.performUndo()
        #expect(vm.activities == [activity])
    }
}
