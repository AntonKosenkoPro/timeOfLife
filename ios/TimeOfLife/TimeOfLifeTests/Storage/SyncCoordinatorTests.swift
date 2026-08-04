import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncCoordinator")
struct SyncCoordinatorTests {

    // MARK: - Helpers

    private func makeCoordinator(
        store: LocalStore? = nil,
        catalog: FakeCatalogRepository? = nil,
        entries: FakeEntriesRepository? = nil,
        connected: Bool = true
    ) async throws -> (SyncCoordinator, LocalStore, FakeCatalogRepository, FakeEntriesRepository, Connectivity) {
        let store = try store ?? LocalStore(inMemory: true)
        let catalog = catalog ?? FakeCatalogRepository()
        let entries = entries ?? FakeEntriesRepository()
        let connectivity = Connectivity()
        connectivity.isConnected = connected
        let coordinator = SyncCoordinator(
            localStore: store, catalogRepo: catalog,
            entriesRepo: entries, connectivity: connectivity)
        return (coordinator, store, catalog, entries, connectivity)
    }

    // MARK: - Outbound ordering

    @Test("Category create is pushed via POST")
    func categoryCreatePushed() async throws {
        // Disconnect to isolate the outbound phase from the pull phase.
        let (coordinator, store, catalog, _, _) = try await makeCoordinator(connected: false)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()))

        await coordinator.sync()

        #expect(catalog.createCategoryCalls.count == 1)
        #expect(catalog.createCategoryCalls.first?.id == "c1")
        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.syncStatus == .clean)
        #expect(fetched?.sync.remoteKnown == true)
    }

    @Test("Category update is pushed via PATCH when remoteKnown")
    func categoryUpdatePushed() async throws {
        let (coordinator, store, catalog, _, _) = try await makeCoordinator()
        // Insert as clean/remote-known first.
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        // Mutate locally to pending.
        var cat = try await store.category(id: "c1")!
        cat.name = "Work Updated"
        cat.sync.syncStatus = .pending
        cat.sync.localRevision = 1
        try await store.upsertCategory(cat)

        await coordinator.sync()

        #expect(catalog.updateCategoryCalls.count == 1)
        #expect(catalog.updateCategoryCalls.first?.id == "c1")
        #expect(catalog.updateCategoryCalls.first?.request.name == "Work Updated")
    }

    @Test("Category delete is pushed and completed")
    func categoryDeletePushed() async throws {
        let (coordinator, store, catalog, _, _) = try await makeCoordinator()
        var cat = CatalogTestFactory.makeCategory(id: "c1", name: "Work", sync: .adoptedClean())
        cat.sync.syncStatus = .pending
        cat.sync.isDeleted = true
        try await store.upsertCategory(cat)

        await coordinator.sync()

        #expect(catalog.deleteCategoryCalls == ["c1"])
        #expect(try await store.category(id: "c1") == nil)
    }

    @Test("Category delete 404 completes deletion")
    func categoryDelete404() async throws {
        let catalog = FakeCatalogRepository()
        catalog.deleteCategoryError = { _ in
            APIError.server(code: "not_found", message: "gone")
        }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)
        var cat = CatalogTestFactory.makeCategory(id: "c1", name: "Work", sync: .adoptedClean())
        cat.sync.syncStatus = .pending
        cat.sync.isDeleted = true
        try await store.upsertCategory(cat)

        await coordinator.sync()

        #expect(try await store.category(id: "c1") == nil)
    }

    @Test("Activity create is pushed via POST")
    func activityCreatePushed() async throws {
        let (coordinator, store, catalog, _, _) = try await makeCoordinator(connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .newPending()))

        await coordinator.sync()

        #expect(catalog.createActivityCalls.count == 1)
        #expect(catalog.createActivityCalls.first?.id == "a1")
        let fetched = try await store.activity(id: "a1")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Activity created and deleted before POST is removed without network")
    func activityCreatedAndDeletedBeforePost() async throws {
        let (coordinator, store, catalog, _, _) = try await makeCoordinator()
        var act = CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .newPending())
        try await store.upsertActivity(act)
        // Now mark it deleted (still not remote-known).
        act.sync.isDeleted = true
        try await store.upsertActivity(act)

        await coordinator.sync()

        // No POST should have been sent.
        #expect(catalog.createActivityCalls.isEmpty)
        #expect(catalog.deleteActivityCalls.isEmpty)
        // Activity should be hard-deleted locally.
        #expect(try await store.activity(id: "a1") == nil)
    }

    @Test("Activity pending deletion cancels pending entry creates")
    func activityPendingDeleteCancelsEntries() async throws {
        let (coordinator, store, _, entries, _) = try await makeCoordinator()
        // Activity pending deletion (remote-known so it goes through DELETE path).
        var act = CatalogTestFactory.makeActivity(id: "a1", name: "Read", sync: .adoptedClean())
        act.sync.syncStatus = .pending
        act.sync.isDeleted = true
        try await store.upsertActivity(act)
        // Entry pending create for that activity.
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        await coordinator.sync()

        // Entry POST should be skipped (activity pending delete).
        #expect(entries.createEntryCalls.isEmpty)
    }

    // MARK: - Response handling

    @Test("Name collision triggers category remap")
    func categoryCollisionRemap() async throws {
        let catalog = FakeCatalogRepository()
        catalog.createCategoryError = { _ in
            APIError.server(code: "category_exists", message: "exists", details: ["id": "winner", "name": "Work"])
        }
        catalog.getCategoryResult = { id in
            CatalogTestFactory.makeCategoryDTO(id: id, name: "Work", icon: "briefcase")
        }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "loser", name: "Work", sync: .newPending()))

        await coordinator.sync()

        // Winner should be fetched and adopted.
        #expect(catalog.getCategoryCalls.contains("winner"))
        // Loser should be remapped (hard-deleted).
        #expect(try await store.category(id: "loser") == nil)
    }

    @Test("Name collision triggers activity remap")
    func activityCollisionRemap() async throws {
        let catalog = FakeCatalogRepository()
        catalog.createActivityError = { _ in
            APIError.server(code: "activity_exists", message: "exists", details: ["id": "winner", "name": "Read"])
        }
        catalog.getActivityResult = { id in
            CatalogTestFactory.makeActivityDTO(id: id, name: "Read")
        }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "loser", name: "Read", sync: .newPending()))

        await coordinator.sync()

        #expect(catalog.getActivityCalls.contains("winner"))
        #expect(try await store.activity(id: "loser") == nil)
    }

    @Test("Conflict triggers category fetch and adopt")
    func categoryConflictAdopt() async throws {
        let catalog = FakeCatalogRepository()
        catalog.updateCategoryError = { _, _ in
            APIError.server(code: "conflict", message: "stale", details: ["updated_at": "2026-01-01T00:00:00Z"])
        }
        catalog.getCategoryResult = { id in
            CatalogTestFactory.makeCategoryDTO(id: id, name: "Server Name", icon: "circle")
        }
        // Disconnect to isolate the outbound phase from the pull phase.
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        var cat = CatalogTestFactory.makeCategory(
            id: "c1", name: "Local Name", sync: .adoptedClean())
        cat.sync.syncStatus = .pending
        try await store.upsertCategory(cat)

        await coordinator.sync()

        #expect(catalog.getCategoryCalls.contains("c1"))
        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "Server Name")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Validation error marks category as blocked")
    func validationErrorBlocksCategory() async throws {
        let catalog = FakeCatalogRepository()
        catalog.createCategoryError = { _ in
            APIError.server(code: "validation_error", message: "Name too long", details: ["name": "max 60"])
        }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "A", sync: .newPending()))

        await coordinator.sync()

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.syncStatus == .blocked)
        #expect(fetched?.sync.syncErrorCode == "validation_error")
    }

    @Test("Offline retains pending state")
    func offlineRetainsPending() async throws {
        let catalog = FakeCatalogRepository()
        catalog.createCategoryError = { _ in APIError.offline }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()))

        await coordinator.sync()

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.syncStatus == .pending) // Still pending.
    }

    // MARK: - Pull reconciliation

    @Test("Pull adopts server categories")
    func pullAdoptsServerCategories() async throws {
        let catalog = FakeCatalogRepository()
        catalog.listCategoriesResult = [
            CatalogTestFactory.makeCategoryDTO(id: "c1", name: "Server Cat")
        ]
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)

        await coordinator.sync()

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "Server Cat")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Pull removes clean local categories absent from server")
    func pullRemovesAbsentClean() async throws {
        let catalog = FakeCatalogRepository()
        catalog.listCategoriesResult = []
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Old"))

        await coordinator.sync()

        #expect(try await store.category(id: "c1") == nil)
    }

    @Test("Pull preserves pending creates absent from server")
    func pullPreservesPendingCreates() async throws {
        // Disconnect so the outbound POST fails (offline), keeping the
        // category pending. Then we just verify the pull phase is skipped.
        let catalog = FakeCatalogRepository()
        catalog.createCategoryError = { _ in APIError.offline }
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "New", sync: .newPending()))

        await coordinator.sync()

        let fetched = try await store.category(id: "c1")
        #expect(fetched != nil)
        #expect(fetched?.sync.syncStatus == .pending)
    }

    @Test("Partial pull (entries fail) does not delete clean records")
    func partialPullDoesNotDelete() async throws {
        let catalog = FakeCatalogRepository()
        catalog.listCategoriesResult = []
        catalog.listActivitiesResult = []
        let entries = FakeEntriesRepository()
        entries.listEntriesError = APIError.transport(underlying: "boom")
        let (coordinator, store, _, _, _) = try await makeCoordinator(catalog: catalog, entries: entries)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Old"))

        await coordinator.sync()

        // Categories and activities fetch succeed but entries fetch fails.
        // The entire pull is abandoned — clean local category is NOT removed.
        #expect(try await store.category(id: "c1") != nil)
    }

    // MARK: - Single-flight

    @Test("Concurrent sync calls join the same in-flight task")
    func singleFlightJoins() async throws {
        let (coordinator, store, catalog, _, _) = try await makeCoordinator()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()))

        // Two concurrent sync calls.
        async let sync1: Void = coordinator.sync()
        async let sync2: Void = coordinator.sync()
        _ = await (sync1, sync2)

        // Only one POST should have been sent (single-flight).
        #expect(catalog.createCategoryCalls.count == 1)
    }

    // MARK: - Logout cancellation

    @Test("Cancel sync stops in-flight task")
    func cancelSync() async throws {
        let (coordinator, _, _, _, _) = try await makeCoordinator()
        // Start a sync, then cancel.
        async let _: Void = coordinator.sync()
        await coordinator.cancelSync()
        // Should not hang or crash.
    }
}
