import Testing
import Foundation
@testable import TimeOfLife

@Suite("Undo Flow")
struct UndoFlowTests {

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    private func makeActivity(
        in store: LocalStore,
        id: String = "act-1",
        name: String = "Reading"
    ) async throws -> Activity {
        let activity = CatalogTestFactory.makeActivity(
            id: id, name: name, sync: .newPending())
        try await store.upsertActivity(activity)
        return activity
    }

    private func makeCategory(
        in store: LocalStore,
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase"
    ) async throws -> Cat {
        let category = CatalogTestFactory.makeCategory(
            id: id, name: name, icon: icon, sync: .newPending())
        try await store.upsertCategory(category)
        return category
    }

    private func makeEntry(
        in store: LocalStore,
        id: String = "ent-1",
        activityId: String = "act-1",
        startedAt: Date = CatalogTestFactory.date(),
        endedAt: Date = CatalogTestFactory.date(offset: 60)
    ) async throws -> Entry {
        let entry = CatalogTestFactory.makeEntry(
            id: id, activityId: activityId,
            startedAt: startedAt, endedAt: endedAt,
            sync: .newPending())
        try await store.upsertEntry(entry)
        return entry
    }

    // MARK: - UndoHold encoding

    @Test("UndoHold encodes and decodes payload")
    func undoHoldCoding() throws {
        let hold = UndoHold(
            type: .activityWithEntries,
            targetId: "act-1",
            entryIds: ["ent-1", "ent-2"],
            categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        let payload = try hold.encodePayload()
        let decoded = try UndoHold.decodePayload(payload)
        #expect(decoded == hold)
    }

    @Test("UndoHold category joins encode")
    func undoHoldCategoryJoins() throws {
        let joins = [
            UndoHold.CategoryJoinSnapshot(activityId: "act-1", categoryId: "cat-1", position: 0),
            UndoHold.CategoryJoinSnapshot(activityId: "act-2", categoryId: "cat-1", position: 1),
        ]
        let hold = UndoHold(
            type: .category,
            targetId: "cat-1",
            entryIds: [],
            categoryJoins: joins,
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        let payload = try hold.encodePayload()
        let decoded = try UndoHold.decodePayload(payload)
        #expect(decoded.categoryJoins == joins)
    }

    // MARK: - Whole activity + entries deletion

    @Test("holdForUndo hides activity and entries")
    func holdHidesActivityAndEntries() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)
        _ = try await makeEntry(in: store, id: "ent-1")
        _ = try await makeEntry(in: store, id: "ent-2",
                                startedAt: CatalogTestFactory.date(offset: -10),
                                endedAt: CatalogTestFactory.date(offset: 50))
        let entryIds = try await store.entryIds(forActivityId: "act-1")
        #expect(entryIds.count == 2)

        let hold = UndoHold(
            type: .activityWithEntries,
            targetId: "act-1",
            entryIds: entryIds,
            categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        // Activity and entries are hidden from user-facing queries.
        let activities = try await store.activitiesSortedByLastUsedAt()
        #expect(activities.isEmpty)
        let entries = try await store.entries(forActivityId: "act-1")
        #expect(entries.isEmpty)
        // But still on disk (fetchable by id).
        let activity = try await store.activity(id: "act-1")
        #expect(activity != nil)
        #expect(activity?.sync.isUndoHidden == true)
        // The hold is persisted.
        let current = try await store.currentHold()
        #expect(current?.type == .activityWithEntries)
    }

    @Test("performUndo restores activity and entries")
    func undoRestoresActivityAndEntries() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)
        _ = try await makeEntry(in: store, id: "ent-1")
        let entryIds = try await store.entryIds(forActivityId: "act-1")
        let hold = UndoHold(
            type: .activityWithEntries,
            targetId: "act-1",
            entryIds: entryIds,
            categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        let restored = try await store.performUndo()
        #expect(restored == .activityWithEntries)

        let activities = try await store.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
        let entries = try await store.entries(forActivityId: "act-1")
        #expect(entries.count == 1)
        let activity = try await store.activity(id: "act-1")
        #expect(activity?.sync.isUndoHidden == false)
        // Hold cleared.
        #expect(try await store.currentHold() == nil)
    }

    @Test("expireUndoHold converts to pending deletion")
    func expireConvertsToPendingDeletion() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)
        _ = try await makeEntry(in: store, id: "ent-1")
        let entryIds = try await store.entryIds(forActivityId: "act-1")
        let hold = UndoHold(
            type: .activityWithEntries,
            targetId: "act-1",
            entryIds: entryIds,
            categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        let expired = try await store.expireUndoHold()
        #expect(expired == .activityWithEntries)

        // Records are now pending deletion (not visible, marked deleted+pending).
        let activity = try await store.activity(id: "act-1")
        #expect(activity?.sync.isDeleted == true)
        #expect(activity?.sync.syncStatus == .pending)
        #expect(activity?.sync.isUndoHidden == false)

        let entry = try await store.entry(id: "ent-1")
        #expect(entry?.sync.isDeleted == true)
        #expect(entry?.sync.syncStatus == .pending)

        // Hold cleared.
        #expect(try await store.currentHold() == nil)
    }

    // MARK: - Latest entry deletion

    @Test("latest entry deletion targets newest by started_at DESC, id DESC")
    func latestEntryDeletion() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)
        _ = try await makeEntry(in: store, id: "ent-old",
                                startedAt: CatalogTestFactory.date(offset: -100),
                                endedAt: CatalogTestFactory.date(offset: -40))
        _ = try await makeEntry(in: store, id: "ent-new",
                                startedAt: CatalogTestFactory.date(offset: 0),
                                endedAt: CatalogTestFactory.date(offset: 60))
        _ = try await makeEntry(in: store, id: "ent-mid",
                                startedAt: CatalogTestFactory.date(offset: -50),
                                endedAt: CatalogTestFactory.date(offset: 10))

        // The latest entry by (started_at DESC, id DESC) is "ent-new".
        let latestId = try await store.latestEntryId(forActivityId: "act-1")
        #expect(latestId == "ent-new")

        let hold = UndoHold(
            type: .latestEntry,
            targetId: "ent-new",
            entryIds: [],
            categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        // Only the latest entry is hidden; the other two remain visible.
        let entries = try await store.entries(forActivityId: "act-1")
        #expect(entries.count == 2)
        #expect(!entries.contains { $0.id == "ent-new" })

        // Undo restores it.
        _ = try await store.performUndo()
        let restored = try await store.entries(forActivityId: "act-1")
        #expect(restored.count == 3)
    }

    // MARK: - Category deletion

    @Test("category deletion hides category and removes joins")
    func categoryDeletionHidesAndRemovesJoins() async throws {
        let store = try makeStore()
        _ = try await makeCategory(in: store, id: "cat-1")
        _ = try await makeActivity(in: store, id: "act-1", name: "Reading")
        // Tag the activity with the category.
        var activity = try await store.activity(id: "act-1")!
        activity.categoryIds = ["cat-1"]
        try await store.upsertActivity(activity)

        let joins = try await store.categoryJoins(forCategoryId: "cat-1")
        #expect(joins.count == 1)

        let hold = UndoHold(
            type: .category,
            targetId: "cat-1",
            entryIds: [],
            categoryJoins: joins,
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        // Category hidden, join removed.
        let categories = try await store.categoriesSortedByName()
        #expect(categories.isEmpty)
        let joinsAfter = try await store.categoryJoins(forCategoryId: "cat-1")
        #expect(joinsAfter.isEmpty)

        // Undo restores.
        _ = try await store.performUndo()
        let restoredCats = try await store.categoriesSortedByName()
        #expect(restoredCats.count == 1)
        let restoredActivity = try await store.activity(id: "act-1")!
        #expect(restoredActivity.categoryIds == ["cat-1"])
    }

    // MARK: - Supersession

    @Test("starting a new hold supersedes the old one")
    func supersession() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store, id: "act-1")
        _ = try await makeActivity(in: store, id: "act-2", name: "Writing")

        let hold1 = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold1)

        let hold2 = UndoHold(
            type: .activityWithEntries, targetId: "act-2",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold2)

        // Only one hold exists (the most recent).
        let current = try await store.currentHold()
        #expect(current?.targetId == "act-2")

        // Undo restores only the most recent (act-2).
        let restored = try await store.performUndo()
        #expect(restored == .activityWithEntries)
        let activities = try await store.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
        #expect(activities.first?.id == "act-2")
    }

    // MARK: - Relaunch (currentHold + expiry on relaunch)

    @Test("currentHold returns persisted hold")
    func currentHoldPersists() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)
        let hold = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        try await store.holdForUndo(hold)

        let current = try await store.currentHold()
        #expect(current?.targetId == "act-1")
    }

    // MARK: - UndoService

    @Test("UndoService start sets activeHold and expire clears it")
    @MainActor
    func undoServiceLifecycle() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)

        let service = UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { CatalogTestFactory.date() },
            scheduler: { _, work in work() } // Fire immediately for the test.
        )

        let hold = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        await service.start(hold: hold)
        #expect(service.activeHold != nil)

        await service.expire()
        #expect(service.activeHold == nil)
        // After expiry, the activity is pending deletion.
        let activity = try await store.activity(id: "act-1")
        #expect(activity?.sync.isDeleted == true)
    }

    @Test("UndoService performUndo restores records")
    @MainActor
    func undoServicePerformUndo() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)

        let service = UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { CatalogTestFactory.date() },
            scheduler: { _, _ in /* no auto-fire */ }
        )

        let hold = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30))
        await service.start(hold: hold)
        #expect(service.activeHold != nil)

        await service.performUndo()
        #expect(service.activeHold == nil)

        // Activity is visible again.
        let activities = try await store.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
    }

    @Test("UndoService restoreOnLaunch expires past-due hold")
    @MainActor
    func undoServiceRestoreOnLaunchExpired() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)

        // Write a hold that's already expired.
        let hold = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(offset: -60),
            expiresAt: CatalogTestFactory.date(offset: -30)) // expired 30s ago
        try await store.holdForUndo(hold)

        let service = UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { CatalogTestFactory.date() },
            scheduler: { _, _ in }
        )

        await service.restoreOnLaunch()
        #expect(service.activeHold == nil)
        let activity = try await store.activity(id: "act-1")
        #expect(activity?.sync.isDeleted == true)
    }

    @Test("UndoService restoreOnLaunch re-arms unexpired hold")
    @MainActor
    func undoServiceRestoreOnLaunchReArms() async throws {
        let store = try makeStore()
        _ = try await makeActivity(in: store)

        let hold = UndoHold(
            type: .activityWithEntries, targetId: "act-1",
            entryIds: [], categoryJoins: [],
            createdAt: CatalogTestFactory.date(),
            expiresAt: CatalogTestFactory.date(offset: 30)) // 30s in future
        try await store.holdForUndo(hold)

        let service = UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { CatalogTestFactory.date() },
            scheduler: { _, _ in /* no auto-fire */ }
        )

        await service.restoreOnLaunch()
        #expect(service.activeHold != nil)
        #expect(service.activeHold?.targetId == "act-1")
    }
}
