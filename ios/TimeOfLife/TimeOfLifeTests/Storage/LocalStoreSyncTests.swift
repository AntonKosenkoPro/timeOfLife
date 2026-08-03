import Testing
import Foundation
@testable import TimeOfLife

@Suite("LocalStore sync")
struct LocalStoreSyncTests {

    // MARK: - Helpers

    /// Creates a fresh in-memory store for each test.
    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    // MARK: - Transactional collision remapping

    @Test("Activity ID remap rewrites entries and removes loser")
    func remapActivityId() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "loser", name: "Loser"))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "winner", name: "Winner"))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(id: "e1", activityId: "loser"))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(id: "e2", activityId: "winner"))

        try await store.remapActivityId(loserId: "loser", winnerId: "winner")

        #expect(try await store.activity(id: "loser") == nil)
        #expect(try await store.entry(id: "e1")?.activityId == "winner")
        #expect(try await store.entry(id: "e2")?.activityId == "winner")
    }

    @Test("Category ID remap deduplicates join rows")
    func remapCategoryId() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "loser", name: "Loser"))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "winner", name: "Winner"))
        // Activity tagged with both loser and winner.
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Act", categoryIds: ["loser", "winner"]))
        // Activity tagged with only loser.
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a2", name: "Act2", categoryIds: ["loser"]))

        try await store.remapCategoryId(loserId: "loser", winnerId: "winner")

        #expect(try await store.category(id: "loser") == nil)
        let a1 = try await store.activity(id: "a1")
        #expect(a1?.categoryIds == ["winner"]) // No duplicate.
        let a2 = try await store.activity(id: "a2")
        #expect(a2?.categoryIds == ["winner"])
    }

    // MARK: - Revision guard

    @Test("Adopt canonical category skips stale response")
    func adoptCanonicalCategoryStale() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work",
            sync: SyncMetadata(
                remoteKnown: false, syncStatus: .pending, isDeleted: false,
                isUndoHidden: false, localRevision: 5,
                syncErrorCode: nil, syncErrorMessage: nil
            )
        ))

        let dto = CatalogTestFactory.makeCategoryDTO(id: "c1", name: "Work")
        // expectedRevision = 3, but local is 5 → stale.
        let result = try await store.adoptCanonicalCategory(id: "c1", dto: dto, expectedRevision: 3)
        #expect(result.didOverwrite == false)
        #expect(result.model == nil)

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.localRevision == 5) // Unchanged.
    }

    @Test("Adopt canonical category overwrites when revision matches")
    func adoptCanonicalCategoryFresh() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work",
            sync: SyncMetadata(
                remoteKnown: false, syncStatus: .pending, isDeleted: false,
                isUndoHidden: false, localRevision: 3,
                syncErrorCode: nil, syncErrorMessage: nil
            )
        ))

        let dto = CatalogTestFactory.makeCategoryDTO(id: "c1", name: "Work Updated")
        let result = try await store.adoptCanonicalCategory(id: "c1", dto: dto, expectedRevision: 3)
        #expect(result.didOverwrite == true)

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "Work Updated")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    // MARK: - Mark clean / blocked

    @Test("Mark category clean clears error and sets remoteKnown")
    func markCategoryClean() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work",
            sync: SyncMetadata(
                remoteKnown: false, syncStatus: .pending, isDeleted: false,
                isUndoHidden: false, localRevision: 1,
                syncErrorCode: nil, syncErrorMessage: nil
            )
        ))

        try await store.markCategoryClean(id: "c1")

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.sync.syncStatus == .clean)
        #expect(fetched?.sync.remoteKnown == true)
    }

    @Test("Mark activity blocked stores error code and message")
    func markActivityBlocked() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))

        try await store.markActivityBlocked(id: "a1", code: "validation_error", message: "Name too long")

        let fetched = try await store.activity(id: "a1")
        #expect(fetched?.sync.syncStatus == .blocked)
        #expect(fetched?.sync.syncErrorCode == "validation_error")
        #expect(fetched?.sync.syncErrorMessage == "Name too long")
    }

    // MARK: - Full-snapshot reconciliation

    @Test("Reconciliation adopts clean records from server")
    func reconcileAdoptsClean() async throws {
        let store = try makeStore()
        // Local clean category will be overwritten by server.
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Old Name"))

        let snapshot = ServerSnapshot(
            categories: [CatalogTestFactory.makeCategoryDTO(id: "c1", name: "New Name")],
            activities: [],
            entries: []
        )
        try await store.reconcileWithSnapshot(snapshot)

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "New Name")
        #expect(fetched?.sync.syncStatus == .clean)
    }

    @Test("Reconciliation preserves dirty records")
    func reconcilePreservesDirty() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Local Edit",
            sync: .newPending()
        ))

        let snapshot = ServerSnapshot(
            categories: [CatalogTestFactory.makeCategoryDTO(id: "c1", name: "Server Name")],
            activities: [],
            entries: []
        )
        try await store.reconcileWithSnapshot(snapshot)

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "Local Edit") // Local edit preserved.
        #expect(fetched?.sync.syncStatus == .pending)
    }

    @Test("Reconciliation removes clean local records absent from server")
    func reconcileRemovesAbsentClean() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Work"))

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        #expect(try await store.category(id: "c1") == nil)
    }

    @Test("Reconciliation preserves pending creates absent from server")
    func reconcilePreservesPendingCreates() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "New Cat",
            sync: .newPending()
        ))

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        let fetched = try await store.category(id: "c1")
        #expect(fetched != nil) // Pending create preserved.
        #expect(fetched?.sync.syncStatus == .pending)
    }

    @Test("Reconciliation completes pending deletes absent from server")
    func reconcileCompletesPendingDeletes() async throws {
        let store = try makeStore()
        var pendingDelete = CatalogTestFactory.makeCategory(
            id: "c1", name: "Work",
            sync: .newPending()
        )
        pendingDelete.sync.isDeleted = true
        try await store.upsertCategory(pendingDelete)

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        #expect(try await store.category(id: "c1") == nil) // Pending delete completed.
    }

    @Test("Reconciliation cascades entry deletion when activity is absent")
    func reconcileCascadesEntriesForAbsentActivity() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(id: "e1", activityId: "a1"))

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil) // Cascaded.
    }

    @Test("Reconciliation preserves dirty entries when activity is absent")
    func reconcilePreservesDirtyEntriesForAbsentActivity() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()
        ))

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        // Activity removed (clean, absent).
        #expect(try await store.activity(id: "a1") == nil)
        // Dirty entry preserved (not cascaded).
        let entry = try await store.entry(id: "e1")
        #expect(entry != nil)
        #expect(entry?.sync.syncStatus == .pending)
    }

    // MARK: - Metadata

    @Test("Metadata set and get")
    func metadataSetGet() async throws {
        let store = try makeStore()
        try await store.setMetadataValue("done", forKey: "seeded")
        let value = try await store.metadataValue(forKey: "seeded")
        #expect(value == "done")
    }

    @Test("Metadata missing key returns nil")
    func metadataMissingKey() async throws {
        let store = try makeStore()
        let value = try await store.metadataValue(forKey: "nope")
        #expect(value == nil)
    }

    // MARK: - Undo hold

    @Test("Set and clear undo hold")
    func undoHoldLifecycle() async throws {
        let store = try makeStore()
        let hold = UndoHoldRecord(
            id: nil,
            holdType: "activity",
            payload: "{}",
            createdAt: 0,
            expiresAt: 30
        )
        try await store.setUndoHold(hold)

        let current = try await store.currentUndoHold()
        #expect(current?.holdType == "activity")

        try await store.clearUndoHold()
        #expect(try await store.currentUndoHold() == nil)
    }

    @Test("Set undo hold replaces previous")
    func undoHoldReplaces() async throws {
        let store = try makeStore()
        try await store.setUndoHold(UndoHoldRecord(
            id: nil, holdType: "activity", payload: "{}",
            createdAt: 0, expiresAt: 30
        ))
        try await store.setUndoHold(UndoHoldRecord(
            id: nil, holdType: "entry", payload: "{}",
            createdAt: 0, expiresAt: 30
        ))

        let current = try await store.currentUndoHold()
        #expect(current?.holdType == "entry")
    }
}
