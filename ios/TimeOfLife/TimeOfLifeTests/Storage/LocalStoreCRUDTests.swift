import Testing
import Foundation
@testable import TimeOfLife

@Suite("LocalStore CRUD")
struct LocalStoreCRUDTests {

    // MARK: - Helpers

    /// Creates a fresh in-memory store for each test.
    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    // MARK: - Initialization

    @Test("Initializes with empty schema")
    func initializesEmpty() async throws {
        let store = try makeStore()
        let cats = try await store.categoriesSortedByName()
        let acts = try await store.activitiesSortedByLastUsedAt()
        #expect(cats.isEmpty)
        #expect(acts.isEmpty)
    }

    // MARK: - Category CRUD

    @Test("Upsert and fetch category")
    func upsertAndFetchCategory() async throws {
        let store = try makeStore()
        let cat = CatalogTestFactory.makeCategory(id: "c1", name: "Work")
        try await store.upsertCategory(cat)

        let fetched = try await store.category(id: "c1")
        #expect(fetched == cat)

        let all = try await store.categoriesSortedByName()
        #expect(all.count == 1)
        #expect(all.first?.name == "Work")
    }

    @Test("Category sorted by name ascending")
    func categoriesSortedByName() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c2", name: "Zeta"))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Alpha"))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c3", name: "Mid"))

        let all = try await store.categoriesSortedByName()
        #expect(all.map(\.name) == ["Alpha", "Mid", "Zeta"])
    }

    @Test("Category normalized name lookup is case-insensitive")
    func categoryNormalizedName() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "  Work  "))

        let found = try await store.category(normalizedName: "work")
        #expect(found?.id == "c1")
    }

    @Test("Deleted categories are hidden from sorted-by-name")
    func deletedCategoriesHidden() async throws {
        let store = try makeStore()
        var cat = CatalogTestFactory.makeCategory(id: "c1", name: "Work")
        cat.sync.isDeleted = true
        try await store.upsertCategory(cat)

        let visible = try await store.categoriesSortedByName()
        #expect(visible.isEmpty)

        // Still fetchable by id directly.
        let fetched = try await store.category(id: "c1")
        #expect(fetched != nil)
    }

    @Test("Hard delete category removes join rows")
    func hardDeleteCategory() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Work"))
        let act = CatalogTestFactory.makeActivity(id: "a1", name: "Read", categoryIds: ["c1"])
        try await store.upsertActivity(act)

        try await store.hardDeleteCategory(id: "c1")

        let fetched = try await store.category(id: "c1")
        #expect(fetched == nil)

        // Activity still exists but its tag is gone.
        let activity = try await store.activity(id: "a1")
        #expect(activity?.categoryIds.isEmpty == true)
    }

    // MARK: - Activity CRUD

    @Test("Upsert and fetch activity with category ids")
    func upsertActivityWithTags() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Work"))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c2", name: "Hobby"))
        let act = CatalogTestFactory.makeActivity(id: "a1", name: "Read", categoryIds: ["c1", "c2"])
        try await store.upsertActivity(act)

        let fetched = try await store.activity(id: "a1")
        #expect(fetched?.categoryIds == ["c1", "c2"])
    }

    @Test("Replacing category ids overwrites previous tags")
    func replaceActivityTags() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Work"))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c2", name: "Hobby"))
        var act = CatalogTestFactory.makeActivity(id: "a1", name: "Read", categoryIds: ["c1"])
        try await store.upsertActivity(act)

        act.categoryIds = ["c2"]
        try await store.upsertActivity(act)

        let fetched = try await store.activity(id: "a1")
        #expect(fetched?.categoryIds == ["c2"])
    }

    @Test("Activities sorted by last_used_at descending with name tie-break")
    func activitiesSortedByLastUsedAt() async throws {
        let store = try makeStore()
        let base = CatalogTestFactory.date()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Beta", lastUsedAt: base
        ))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a2", name: "Alpha", lastUsedAt: base
        ))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a3", name: "Gamma", lastUsedAt: base.addingTimeInterval(100)
        ))

        let all = try await store.activitiesSortedByLastUsedAt()
        // Gamma has the latest lastUsedAt → first.
        // Alpha and Beta have the same lastUsedAt → Alpha first (name tie-break).
        #expect(all.map(\.id) == ["a3", "a2", "a1"])
    }

    @Test("Activity normalized name lookup")
    func activityNormalizedName() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "  Reading  "))

        let found = try await store.activity(normalizedName: "reading")
        #expect(found?.id == "a1")
    }

    @Test("Hard delete activity cascades to entries and join rows")
    func hardDeleteActivityCascades() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(id: "c1", name: "Work"))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read", categoryIds: ["c1"]))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(id: "e1", activityId: "a1"))

        try await store.hardDeleteActivity(id: "a1")

        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
        let cats = try await store.categoriesSortedByName()
        #expect(cats.count == 1) // Category survives; only the join row is gone.
    }

    // MARK: - Entry CRUD

    @Test("Upsert and fetch entry")
    func upsertAndFetchEntry() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        let entry = CatalogTestFactory.makeEntry(id: "e1", activityId: "a1")
        try await store.upsertEntry(entry)

        let fetched = try await store.entry(id: "e1")
        #expect(fetched == entry)
    }

    @Test("Entry count for activity excludes deleted/hidden")
    func entryCountExcludesDeleted() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(id: "e1", activityId: "a1"))
        var deleted = CatalogTestFactory.makeEntry(id: "e2", activityId: "a1")
        deleted.sync.isDeleted = true
        try await store.upsertEntry(deleted)

        let count = try await store.entryCount(forActivityId: "a1")
        #expect(count == 1)
    }

    @Test("Latest entry is deterministic by started_at DESC, id DESC")
    func latestEntryDeterministic() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        let base = CatalogTestFactory.date()
        // Same started_at — id "e2" should win (DESC).
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", startedAt: base, endedAt: nil, durationSeconds: nil
        ))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e2", activityId: "a1", startedAt: base, endedAt: nil, durationSeconds: nil
        ))
        // Newer started_at — should win over both.
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e3", activityId: "a1", startedAt: base.addingTimeInterval(50), endedAt: nil, durationSeconds: nil
        ))

        let latest = try await store.latestEntry(forActivityId: "a1")
        #expect(latest?.id == "e3")
    }

    @Test("Running entry has nil endedAt")
    func runningEntry() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        let entry = CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", endedAt: nil, durationSeconds: nil
        )
        try await store.upsertEntry(entry)

        let fetched = try await store.entry(id: "e1")
        #expect(fetched?.endedAt == nil)
        #expect(fetched?.duration == nil)
    }

    // MARK: - Pending / blocked queries

    @Test("Pending categories split into creates/updates and deletes")
    func pendingCategoriesSplit() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .newPending()
        ))
        var pendingDelete = CatalogTestFactory.makeCategory(
            id: "c2", name: "Old", sync: .newPending()
        )
        pendingDelete.sync.isDeleted = true
        try await store.upsertCategory(pendingDelete)

        let (createsUpdates, deletes) = try await store.pendingCategories()
        #expect(createsUpdates.map(\.id) == ["c1"])
        #expect(deletes.map(\.id) == ["c2"])
    }

    @Test("Blocked records are queryable")
    func blockedRecordsQueryable() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work",
            sync: SyncMetadata(
                remoteKnown: true, syncStatus: .blocked, isDeleted: false,
                isUndoHidden: false, localRevision: 2,
                syncErrorCode: "validation_error", syncErrorMessage: "bad name"
            )
        ))

        let (cats, _, _) = try await store.blockedRecords()
        #expect(cats.count == 1)
        #expect(cats.first?.sync.syncErrorCode == "validation_error")
    }
}
