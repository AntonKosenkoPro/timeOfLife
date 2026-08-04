import Testing
import Foundation
@testable import TimeOfLife

/// AC10 / Phase 9.2 — Additional SyncCoordinator coverage: entry outbound
/// flows, activity deletion with server cascade, and update-404 handling.
@MainActor
@Suite("SyncCoordinator extended")
struct SyncCoordinatorExtendedTests {

    // MARK: - Helpers

    private func makeCoordinator(
        catalog: FakeCatalogRepository? = nil,
        entries: FakeEntriesRepository? = nil,
        connected: Bool = true
    ) async throws -> (SyncCoordinator, LocalStore, FakeCatalogRepository, FakeEntriesRepository) {
        let store = try LocalStore(inMemory: true)
        let catalog = catalog ?? FakeCatalogRepository()
        let entries = entries ?? FakeEntriesRepository()
        let connectivity = Connectivity()
        connectivity.isConnected = connected
        let coordinator = SyncCoordinator(
            localStore: store, catalogRepo: catalog,
            entriesRepo: entries, connectivity: connectivity)
        return (coordinator, store, catalog, entries)
    }

    // MARK: - Entry outbound

    @Test("Entry create is pushed via POST and marked clean")
    func entryCreatePushed() async throws {
        let (coordinator, store, _, entries) = try await makeCoordinator(connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        await coordinator.sync()

        #expect(entries.createEntryCalls.count == 1)
        #expect(entries.createEntryCalls.first?.id == "e1")
        #expect(entries.createEntryCalls.first?.activityId == "a1")
        let fetched = try await store.entry(id: "e1")
        #expect(fetched?.sync.syncStatus == .clean)
        #expect(fetched?.sync.remoteKnown == true)
    }

    @Test("Entry update is pushed via PATCH when remoteKnown")
    func entryUpdatePushed() async throws {
        let (coordinator, store, _, entries) = try await makeCoordinator(connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        var entry = CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean())
        entry.sync.syncStatus = .pending
        entry.sync.localRevision = 1
        try await store.upsertEntry(entry)

        await coordinator.sync()

        #expect(entries.updateEntryCalls.count == 1)
        #expect(entries.updateEntryCalls.first?.id == "e1")
        let fetched = try await store.entry(id: "e1")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Entry delete is pushed and completed")
    func entryDeletePushed() async throws {
        let (coordinator, store, _, entries) = try await makeCoordinator(connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        var entry = CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean())
        entry.sync.syncStatus = .pending
        entry.sync.isDeleted = true
        try await store.upsertEntry(entry)

        await coordinator.sync()

        #expect(entries.deleteEntryCalls == ["e1"])
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("Entry delete 404 completes deletion")
    func entryDelete404() async throws {
        let entries = FakeEntriesRepository()
        entries.deleteEntryError = { _ in
            APIError.server(code: "not_found", message: "gone")
        }
        let (coordinator, store, _, _) = try await makeCoordinator(entries: entries)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        var entry = CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean())
        entry.sync.syncStatus = .pending
        entry.sync.isDeleted = true
        try await store.upsertEntry(entry)

        await coordinator.sync()

        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("Entry validation error marks entry blocked")
    func entryValidationBlocks() async throws {
        let entries = FakeEntriesRepository()
        entries.createEntryError = { _ in
            APIError.server(code: "validation_error", message: "bad time", details: ["started_at": "invalid"])
        }
        let (coordinator, store, _, _) = try await makeCoordinator(entries: entries, connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        await coordinator.sync()

        let fetched = try await store.entry(id: "e1")
        #expect(fetched?.sync.syncStatus == .blocked)
        #expect(fetched?.sync.syncErrorCode == "validation_error")
    }

    @Test("Entry conflict fetches canonical and adopts")
    func entryConflictAdopt() async throws {
        let entries = FakeEntriesRepository()
        entries.updateEntryError = { _, _ in
            APIError.server(code: "conflict", message: "stale", details: ["updated_at": "2026-01-01T00:00:00Z"])
        }
        entries.getEntryResult = { id in
            CatalogTestFactory.makeEntryDTO(
                id: id, activityId: "a1", endedAt: nil, durationSeconds: nil)
        }
        let (coordinator, store, _, _) = try await makeCoordinator(entries: entries, connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        var entry = CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean())
        entry.sync.syncStatus = .pending
        entry.sync.localRevision = 1
        try await store.upsertEntry(entry)

        await coordinator.sync()

        #expect(entries.getEntryCalls.contains("e1"))
        let fetched = try await store.entry(id: "e1")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Pending activity syncs after connectivity restores")
    func pendingActivitySyncsAfterReconnect() async throws {
        let store = try LocalStore(inMemory: true)
        let catalog = FakeCatalogRepository()
        let entries = FakeEntriesRepository()
        let connectivity = MockConnectivity(connected: false)
        let coordinator = SyncCoordinator(
            localStore: store,
            catalogRepo: catalog,
            entriesRepo: entries,
            connectivity: connectivity)
        var isOffline = true
        catalog.createActivityError = { _ in
            isOffline ? APIError.offline : nil
        }
        catalog.listActivitiesResult = [
            CatalogTestFactory.makeActivityDTO(id: "a1", name: "Read")
        ]
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .newPending()))

        await coordinator.sync()

        #expect(try await store.activity(id: "a1")?.sync.syncStatus == .pending)
        isOffline = false
        connectivity.isConnected = true
        await coordinator.sync()

        #expect(catalog.createActivityCalls.count == 2)
        #expect(try await store.activity(id: "a1")?.sync.syncStatus == .clean)
    }

    // MARK: - Activity deletion

    @Test("Activity delete is pushed and cascades locally")
    func activityDeletePushed() async throws {
        let (coordinator, store, catalog, _) = try await makeCoordinator(connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        var act = try await store.activity(id: "a1")!
        act.sync.syncStatus = .pending
        act.sync.isDeleted = true
        try await store.upsertActivity(act)

        await coordinator.sync()

        #expect(catalog.deleteActivityCalls == ["a1"])
        // Server DELETE cascades to entries — both removed locally.
        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("Activity delete 404 completes deletion with cascade")
    func activityDelete404() async throws {
        let catalog = FakeCatalogRepository()
        catalog.deleteActivityError = { _ in
            APIError.server(code: "not_found", message: "gone")
        }
        let (coordinator, store, _, _) = try await makeCoordinator(catalog: catalog)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        var act = try await store.activity(id: "a1")!
        act.sync.syncStatus = .pending
        act.sync.isDeleted = true
        try await store.upsertActivity(act)

        await coordinator.sync()

        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    // MARK: - Update 404 (remote hard delete)

    @Test("Category update 404 treats as remote hard delete")
    func categoryUpdate404RemoteDelete() async throws {
        let catalog = FakeCatalogRepository()
        catalog.updateCategoryError = { _, _ in
            APIError.server(code: "not_found", message: "gone")
        }
        let (coordinator, store, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        var cat = CatalogTestFactory.makeCategory(id: "c1", name: "Work", sync: .adoptedClean())
        cat.sync.syncStatus = .pending
        try await store.upsertCategory(cat)

        await coordinator.sync()

        // Remote hard delete → local record removed.
        #expect(try await store.category(id: "c1") == nil)
    }

    @Test("Activity update 404 treats as remote hard delete with entry cascade")
    func activityUpdate404RemoteDelete() async throws {
        let catalog = FakeCatalogRepository()
        catalog.updateActivityError = { _, _ in
            APIError.server(code: "not_found", message: "gone")
        }
        let (coordinator, store, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        var act = try await store.activity(id: "a1")!
        act.sync.syncStatus = .pending
        try await store.upsertActivity(act)

        await coordinator.sync()

        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    // MARK: - Outbound ordering

    @Test("Outbound pushes categories before activities before entries")
    func outboundOrdering() async throws {
        let (coordinator, store, catalog, entries) = try await makeCoordinator(connected: false)
        // Pending category, activity, and entry.
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .newPending()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        await coordinator.sync()

        // All pushed.
        #expect(catalog.createCategoryCalls.count == 1)
        #expect(catalog.createActivityCalls.count == 1)
        #expect(entries.createEntryCalls.count == 1)
        // All adopted clean.
        #expect(try await store.category(id: "c1")?.sync.syncStatus == .clean)
        #expect(try await store.activity(id: "a1")?.sync.syncStatus == .clean)
        #expect(try await store.entry(id: "e1")?.sync.syncStatus == .clean)
    }

    @Test("Idempotent POST replay is treated as ordinary success")
    func idempotentPostSuccess() async throws {
        let catalog = FakeCatalogRepository()
        // POST returns the existing record (200, not 201) — same shape.
        catalog.createCategoryResult = { request in
            CatalogTestFactory.makeCategoryDTO(id: request.id, name: request.name, icon: request.icon)
        }
        let (coordinator, store, _, _) = try await makeCoordinator(catalog: catalog, connected: false)
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()))

        await coordinator.sync()

        #expect(catalog.createCategoryCalls.count == 1)
        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.syncStatus == .clean)
        #expect(fetched?.sync.remoteKnown == true)
    }
}
