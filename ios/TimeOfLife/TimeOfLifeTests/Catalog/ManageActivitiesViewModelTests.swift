import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ManageActivitiesViewModel")
struct ManageActivitiesViewModelTests {
    private final class EntryCounter: ActivityEntryCounting, @unchecked Sendable {
        var count = 0

        func entryCount(forActivityId id: UUID) async -> Int {
            _ = id
            return count
        }
    }

    private func make() -> (
        ManageActivitiesViewModel, MockCatalogStore, FakeCatalogRepository, SyncQueue, UndoBuffer, EntryCounter
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
        return (vm, store, repository, queue, undo, counter)
    }

    @Test("loads activities from the local store in recency order without a network call")
    func loadsOfflineFirst() async {
        let (vm, store, repository, _, _, _) = make()
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
        let (vm, store, _, _, _, _) = make()
        let activity = TestCatalogFactory.activity(name: "Reading")
        await store.upsertActivity(activity)
        await vm.load()

        await vm.requestDelete(activity)
        vm.performDelete(activity, scope: .all)
        #expect(vm.activities.isEmpty)

        await vm.performUndo()
        #expect(vm.activities == [activity])
    }

    @Test("scope confirmation is selected when entries exist and dismissal clears pending state")
    func scopeAndDismissal() async {
        let (vm, store, _, _, _, counter) = make()
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
        let (vm, store, _, queue, undo, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        await vm.requestDelete(activity)
        vm.performDelete(activity, scope: .all)

        await undo.commit(now: Date().addingTimeInterval(31))

        #expect(await store.activity(activity.id) == nil)
        let pending = await queue.pending()
        #expect(pending.contains { $0.method == .delete })
    }

    @Test("entry-only delete keeps the activity row and is undoable")
    func entryOnlyKeepsActivity() async {
        let (vm, store, _, _, undo, counter) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        counter.count = 2
        await vm.requestDelete(activity)
        vm.performDelete(activity, scope: .entryOnly)

        #expect(vm.activities == [activity])
        guard case .holding(.entryOnly(activity.id), expiresAt: _) = undo.state else {
            Issue.record("Expected entry-only undo item")
            return
        }
    }

    @Test("shake undo restores the held activity")
    func shakeUndo() async {
        let (vm, store, _, _, _, _) = make()
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)
        await vm.load()
        await vm.requestDelete(activity)
        vm.performDelete(activity, scope: .all)

        vm.onShake()
        for _ in 0..<10 where vm.activities.isEmpty {
            await Task.yield()
        }

        #expect(vm.activities == [activity])
    }
}
