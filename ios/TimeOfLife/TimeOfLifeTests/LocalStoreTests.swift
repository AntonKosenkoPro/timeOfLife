// swiftlint:disable file_length
import Testing
import Foundation
@testable import TimeOfLife

@Suite("LocalStore")
struct LocalStoreTests {

    // MARK: - Helpers

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeActivity(
        id: String = "act-1",
        name: String = "Coding",
        notes: String? = nil,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 2_000)
    ) -> Activity {
        Activity(
            id: id,
            name: name,
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: updatedAt
        )
    }

    private func makeCategory(
        id: String = "cat-1",
        name: String = "Work",
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 2_000)
    ) -> TimeOfLife.Category {
        TimeOfLife.Category(
            id: id,
            name: name,
            icon: "briefcase",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: updatedAt
        )
    }

    private func makeEntry(
        id: String = "entry-1",
        activityID: String = "act-1",
        source: String = "manual",
        sourceRef: String? = nil,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 3_000)
    ) -> TimeEntry {
        let startedAt = Date(timeIntervalSinceReferenceDate: 2_500)
        return TimeEntry(
            id: id,
            activityID: activityID,
            activityName: "Coding",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            source: source,
            sourceRef: sourceRef,
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: updatedAt
        )
    }

    // MARK: - Create-or-resolve (normalized identity)

    @Test("createOrResolveActivity creates a new activity with an outbox row")
    func createOrResolveCreates() async throws {
        let store = try makeStore()
        let outcome = try await store.createOrResolveActivity(named: "  Coding  ", now: Date(timeIntervalSinceReferenceDate: 5_000))

        guard case let .created(activity) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(activity.name == "Coding")
        #expect(activity.notes == nil)
        #expect(activity.categoryIDs.isEmpty)
        #expect(activity.createdAt == Date(timeIntervalSinceReferenceDate: 5_000))

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
        #expect(rows.first?.recordID == activity.id)
    }

    @Test("createOrResolveActivity reuses an existing case-insensitive match without a new outbox row")
    func createOrResolveReusesExisting() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(name: "Coding"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.createOrResolveActivity(named: "  coding  ")
        guard case let .existing(activity) = outcome else {
            Issue.record("expected existing outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "act-1")
        #expect(activity.name == "Coding")

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
        #expect(rows.first?.recordID == "act-1")
    }

    @Test("createOrResolveActivity creates with notes and categories")
    func createOrResolveWithMetadata() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        let outcome = try await store.createOrResolveActivity(
            named: "Gym",
            notes: "Leg day",
            categoryIDs: ["cat-1"]
        )

        guard case let .created(activity) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(activity.notes == "Leg day")
        #expect(activity.categoryIDs == ["cat-1"])
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs == ["cat-1"])
    }

    @Test("createOrResolveActivity rejects empty and overlong names")
    func createOrResolveValidates() async throws {
        let store = try makeStore()
        let empty = try await store.createOrResolveActivity(named: "   ")
        #expect(empty == .invalid(.empty))

        let long = try await store.createOrResolveActivity(named: String(repeating: "a", count: 61))
        #expect(long == .invalid(.tooLong))

        let rows = try await store.outboxRows()
        #expect(rows.isEmpty)
    }

    @Test("the unique index on lower(name) rejects a direct duplicate insert")
    func uniqueIndexEnforcesNormalizedUniqueness() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(name: "Coding"))
        let duplicate = makeActivity(id: "act-2", name: "coding")

        await #expect(throws: Error.self) {
            try await store.createActivity(duplicate)
        }
        let activities = try await store.activities()
        #expect(activities.count == 1)
    }

    @Test("a concurrent duplicate insert resolves to the existing activity")
    func createOrResolveCollisionResolvesToExisting() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(name: "Coding"))

        let outcome = try await store.createOrResolveActivity(named: "CODING")
        guard case let .existing(activity) = outcome else {
            Issue.record("expected existing outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "act-1")
        let activities = try await store.activities()
        #expect(activities.count == 1)
    }

    @Test("createOrResolveActivity works offline (no network dependency)")
    func createOrResolveOffline() async throws {
        let store = try makeStore()
        let outcome = try await store.createOrResolveActivity(named: "Offline work")
        guard case .created = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        let stored = try await store.activity(named: "offline work")
        #expect(stored?.name == "Offline work")
    }

    // MARK: - Pending-deletion identity

    @Test("createOrResolveActivity reports a non-expired pending deletion as restorable")
    func createOrResolveFindsPendingDeletion() async throws {
        let store = try makeStore()
        let snapshot = try makeActivitySnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(payload: payload, deletedAt: Date())

        let outcome = try await store.createOrResolveActivity(named: "coding")
        guard case let .restorableDeletion(activity) = outcome else {
            Issue.record("expected restorableDeletion outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "act-1")
        #expect(activity.name == "Coding")

        let rows = try await store.outboxRows()
        #expect(rows.isEmpty)
    }

    @Test("an expired pending deletion is not restorable and creation proceeds")
    func createOrResolveIgnoresExpiredDeletion() async throws {
        let store = try makeStore()
        let snapshot = try makeActivitySnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(
            payload: payload,
            deletedAt: Date().addingTimeInterval(-60)
        )

        let outcome = try await store.createOrResolveActivity(named: "Coding")
        guard case let .created(activity) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(activity.id != "act-1")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
    }

    @Test("restorePendingDeletionActivity restores the snapshot without an outbox row")
    func restorePendingDeletionRestores() async throws {
        let store = try makeStore()
        let snapshot = try makeActivitySnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(payload: payload, deletedAt: Date())

        let restored = try await store.restorePendingDeletionActivity(named: "  CODING  ")
        #expect(restored?.id == "act-1")
        #expect(restored?.name == "Coding")

        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Coding")
        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer == nil)
        let rows = try await store.outboxRows()
        #expect(rows.isEmpty)
    }

    @Test("restorePendingDeletionActivity returns nil for an expired or absent match")
    func restorePendingDeletionMisses() async throws {
        let store = try makeStore()
        let snapshot = try makeActivitySnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(
            payload: payload,
            deletedAt: Date().addingTimeInterval(-60)
        )

        let restored = try await store.restorePendingDeletionActivity(named: "Coding")
        #expect(restored == nil)
        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer != nil)
    }

    /// A snapshot capturing a single activity (no entries).
    private func makeActivitySnapshot() throws -> DeletionSnapshot {
        let activity = Activity(
            id: "act-1",
            name: "Coding",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        return DeletionSnapshot(records: [
            DeletionSnapshot.Record(
                resource: "activity",
                recordID: activity.id,
                data: try JSONEncoder().encode(activity)
            ),
        ])
    }

    // MARK: - Outbox atomicity

    @Test("createActivity writes the row and an outbox create row")
    func createActivityEnqueuesOutbox() async throws {
        let store = try makeStore()
        let activity = makeActivity()
        try await store.createActivity(activity)

        let stored = try await store.activity(id: activity.id)
        #expect(stored == activity)

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.resource == "activity")
        #expect(row.recordID == activity.id)
        #expect(row.op == "create")
        #expect(row.attempts == 0)
        let payload = try #require(row.payload)
        let decoded = try JSONDecoder().decode(Activity.self, from: Data(payload.utf8))
        #expect(decoded == activity)
    }

    @Test("createCategory writes the row and an outbox create row")
    func createCategoryEnqueuesOutbox() async throws {
        let store = try makeStore()
        let category = makeCategory()
        try await store.createCategory(category)

        let stored = try await store.category(id: category.id)
        #expect(stored == category)

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.resource == "category")
        #expect(row.recordID == category.id)
        #expect(row.op == "create")
        let payload = try #require(row.payload)
        let decoded = try JSONDecoder().decode(TimeOfLife.Category.self, from: Data(payload.utf8))
        #expect(decoded == category)
    }

    @Test("createEntry writes the row and an outbox create row")
    func createEntryEnqueuesOutbox() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let entry = makeEntry()
        try await store.createEntry(entry)

        let stored = try await store.entry(id: entry.id)
        #expect(stored == entry)

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        let row = try #require(rows.first { $0.resource == "entry" && $0.recordID == entry.id })
        #expect(row.resource == "entry")
        #expect(row.recordID == entry.id)
        #expect(row.op == "create")
        let payload = try #require(row.payload)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(payload.utf8))
        #expect(decoded == entry)
    }

    @Test("deleteActivity removes record and cascades, enqueues a delete outbox row")
    func deleteActivityEnqueuesDeleteOutbox() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createEntry(makeEntry())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.deleteActivity(id: "act-1")

        let activity = try await store.activity(id: "act-1")
        #expect(activity == nil)
        let entries = try await store.entries()
        #expect(entries.isEmpty)

        let rows = try await store.outboxRows()
        #expect(rows.count == 3)
        let deleteRow = try #require(rows.last)
        #expect(deleteRow.resource == "activity")
        #expect(deleteRow.recordID == "act-1")
        #expect(deleteRow.op == "delete")
        #expect(deleteRow.payload == nil)
    }

    @Test("deleteCategory removes record, enqueues a delete outbox row")
    func deleteCategoryEnqueuesDeleteOutbox() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.deleteCategory(id: "cat-1")

        let category = try await store.category(id: "cat-1")
        #expect(category == nil)

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        let deleteRow = try #require(rows.last)
        #expect(deleteRow.resource == "category")
        #expect(deleteRow.recordID == "cat-1")
        #expect(deleteRow.op == "delete")
        #expect(deleteRow.payload == nil)
    }

    @Test("deleteEntry removes record, enqueues a delete outbox row")
    func deleteEntryEnqueuesDeleteOutbox() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createEntry(makeEntry())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.deleteEntry(id: "entry-1")

        let entry = try await store.entry(id: "entry-1")
        #expect(entry == nil)

        let rows = try await store.outboxRows()
        #expect(rows.count == 3)
        let deleteRow = try #require(rows.last)
        #expect(deleteRow.resource == "entry")
        #expect(deleteRow.recordID == "entry-1")
        #expect(deleteRow.op == "delete")
        #expect(deleteRow.payload == nil)
    }

    // MARK: - LWW

    @Test("stale updateActivity returns false and changes nothing")
    func staleActivityUpdateIsRejected() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))

        let stale = makeActivity(name: "Stale", updatedAt: Date(timeIntervalSinceReferenceDate: 3_000))
        let applied = try await store.updateActivity(stale)
        #expect(!applied)

        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Coding")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
    }

    @Test("newer updateActivity returns true, updates, and enqueues an update outbox row")
    func newerActivityUpdateApplies() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let newer = makeActivity(name: "Coding+", notes: "with notes", updatedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        let applied = try await store.updateActivity(newer)
        #expect(applied)

        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Coding+")
        #expect(stored?.notes == "with notes")

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        let updateRow = try #require(rows.last)
        #expect(updateRow.resource == "activity")
        #expect(updateRow.recordID == "act-1")
        #expect(updateRow.op == "update")
        let payload = try #require(updateRow.payload)
        let decoded = try JSONDecoder().decode(Activity.self, from: Data(payload.utf8))
        #expect(decoded.name == "Coding+")
    }

    @Test("stale updateCategory returns false and changes nothing")
    func staleCategoryUpdateIsRejected() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))

        let stale = makeCategory(name: "Stale", updatedAt: Date(timeIntervalSinceReferenceDate: 3_000))
        let applied = try await store.updateCategory(stale)
        #expect(!applied)

        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "Work")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
    }

    @Test("newer updateCategory returns true, updates, and enqueues an update outbox row")
    func newerCategoryUpdateApplies() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let newer = makeCategory(name: "Deep Work", updatedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        let applied = try await store.updateCategory(newer)
        #expect(applied)

        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "Deep Work")
        #expect(stored?.icon == "briefcase")

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        let updateRow = try #require(rows.last)
        #expect(updateRow.op == "update")
        #expect(updateRow.resource == "category")
    }

    @Test("stale updateEntry returns false and changes nothing")
    func staleEntryUpdateIsRejected() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createEntry(makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))

        let stale = makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 3_000))
        let applied = try await store.updateEntry(stale)
        #expect(!applied)

        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.durationSeconds == 600)
        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
    }

    @Test("newer updateEntry returns true, updates, and enqueues an update outbox row")
    func newerEntryUpdateApplies() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createEntry(makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let newer = makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        let applied = try await store.updateEntry(newer)
        #expect(applied)

        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.durationSeconds == 600)

        let rows = try await store.outboxRows()
        #expect(rows.count == 3)
        let updateRow = try #require(rows.last)
        #expect(updateRow.op == "update")
        #expect(updateRow.resource == "entry")
        #expect(updateRow.recordID == "entry-1")
    }

    // MARK: - Idempotent create

    @Test("createActivity with the same id twice is a no-op")
    func createActivityIsIdempotent() async throws {
        let store = try makeStore()
        let activity = makeActivity()
        try await store.createActivity(activity)
        try await store.createActivity(activity)

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        let stored = try await store.activity(id: activity.id)
        #expect(stored == activity)
    }

    @Test("createCategory with the same id twice is a no-op")
    func createCategoryIsIdempotent() async throws {
        let store = try makeStore()
        let category = makeCategory()
        try await store.createCategory(category)
        try await store.createCategory(category)

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        let stored = try await store.category(id: category.id)
        #expect(stored == category)
    }

    @Test("createEntry with the same id twice is a no-op")
    func createEntryIsIdempotent() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let entry = makeEntry()
        try await store.createEntry(entry)
        try await store.createEntry(entry)

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        let stored = try await store.entry(id: entry.id)
        #expect(stored == entry)
    }

    // MARK: - Timer state persistence

    @Test("timer state survives a simulated relaunch at the same database URL")
    func timerStateSurvivesRelaunch() async throws {
        let url = temporaryStoreURL()
        let startedAt = Date(timeIntervalSinceReferenceDate: 5_000)

        let store1 = try LocalStore(url: url)
        try await store1.startTimer(activityID: "act-1", activityName: "Coding", startedAt: startedAt)

        let store2 = try LocalStore(url: url)
        let state = try await store2.timerState()
        #expect(state?.activityID == "act-1")
        #expect(state?.activityName == "Coding")
        #expect(state?.startedAt == startedAt)
        #expect(state?.status == "running")

        try await store2.stopTimer()

        let store3 = try LocalStore(url: url)
        let cleared = try await store3.timerState()
        #expect(cleared == nil)
    }

    // MARK: - Provenance

    @Test("entry provenance round-trips through entry(id:)")
    func provenanceRoundTrips() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let entry = makeEntry(source: "screentime", sourceRef: "st-callback-42")
        try await store.createEntry(entry)

        let fetched = try await store.entry(id: entry.id)
        #expect(fetched == entry)
        #expect(fetched?.source == "screentime")
        #expect(fetched?.sourceRef == "st-callback-42")
    }

    @Test("a second entry with the same (source, sourceRef) is rejected")
    func duplicateProvenanceIsRejected() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createEntry(makeEntry(source: "screentime", sourceRef: "x"))

        let duplicate = makeEntry(id: "entry-2", source: "screentime", sourceRef: "x")
        await #expect(throws: Error.self) {
            try await store.createEntry(duplicate)
        }

        let entries = try await store.entries()
        #expect(entries.count == 1)
    }

    @Test("manual entries with nil sourceRef may duplicate")
    func manualEntriesWithoutSourceRefCanDuplicate() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createEntry(makeEntry(id: "entry-1", source: "manual", sourceRef: nil))
        try await store.createEntry(makeEntry(id: "entry-2", source: "manual", sourceRef: nil))

        let entries = try await store.entries()
        #expect(entries.count == 2)
    }

    // MARK: - eraseAll

    @Test("eraseAll wipes every table")
    func eraseAllWipesEverything() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createCategory(makeCategory())
        try await store.createEntry(makeEntry())
        try await store.startTimer(activityID: "act-1", activityName: "Coding", startedAt: Date())
        try await store.setLastSyncedAt(resource: "activity", date: Date())
        try await store.undoBufferEnter(payload: Data("snapshot".utf8), deletedAt: Date())

        try await store.eraseAll()

        let activities = try await store.activities()
        #expect(activities.isEmpty)
        let categories = try await store.categories()
        #expect(categories.isEmpty)
        let entries = try await store.entries()
        #expect(entries.isEmpty)
        let state = try await store.timerState()
        #expect(state == nil)
        let outbox = try await store.outboxRows()
        #expect(outbox.isEmpty)
        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer == nil)
        let cursor = try await store.lastSyncedAt(resource: "activity")
        #expect(cursor == nil)
    }

    // MARK: - Sync state

    @Test("lastSyncedAt stores and advances per resource")
    func syncStateAdvancesCursor() async throws {
        let store = try makeStore()
        let initial = try await store.lastSyncedAt(resource: "activity")
        #expect(initial == nil)

        let first = Date(timeIntervalSinceReferenceDate: 10_000)
        let second = Date(timeIntervalSinceReferenceDate: 20_000)
        try await store.setLastSyncedAt(resource: "activity", date: first)
        let readBack = try await store.lastSyncedAt(resource: "activity")
        #expect(readBack == first)

        try await store.setLastSyncedAt(resource: "activity", date: second)
        let advanced = try await store.lastSyncedAt(resource: "activity")
        #expect(advanced == second)

        let otherResource = try await store.lastSyncedAt(resource: "category")
        #expect(otherResource == nil)
    }

    // MARK: - Outbox ordering

    @Test("outboxRows returns oldest first")
    func outboxRowsAreOldestFirst() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-a", name: "Alpha"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createCategory(makeCategory(id: "cat-b", name: "Beta"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createCategory(makeCategory(id: "cat-c", name: "Gamma"))

        let rows = try await store.outboxRows()
        #expect(rows.map(\.recordID) == ["cat-a", "cat-b", "cat-c"])
        #expect(rows[0].createdAt <= rows[1].createdAt)
        #expect(rows[1].createdAt <= rows[2].createdAt)
    }
}

@Suite("LocalStore Starter Seeding")
struct LocalStoreSeedingTests {

    private let enNames = [
        "Work", "Hobby", "Sport", "Education", "Relax", "Sleep", "Entertainment",
    ]
    private let ruNames = [
        "Работа", "Хобби", "Спорт", "Образование", "Отдых", "Сон", "Развлечения",
    ]
    private let seedIcons = [
        "briefcase", "paintbrush", "figure.run", "book",
        "cup.and.saucer", "bed.double", "tv",
    ]

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    @Test("seeding creates exactly seven localized categories with their icons and outbox rows")
    func seedsSevenCategories() async throws {
        let store = try makeStore()
        let result = try await store.seedStarterCategoriesIfNeeded(names: enNames, now: Date(timeIntervalSinceReferenceDate: 5_000))

        guard case let .seeded(seeded) = result else {
            Issue.record("expected seeded outcome")
            return
        }
        #expect(seeded.count == 7)
        #expect(seeded.map(\.name) == enNames)
        #expect(seeded.map(\.icon) == seedIcons)
        #expect(seeded.allSatisfy { $0.createdAt == Date(timeIntervalSinceReferenceDate: 5_000) })

        let stored = try await store.categories()
        #expect(stored.count == 7)
        #expect(stored.map(\.name).sorted() == enNames.sorted())

        let rows = try await store.outboxRows()
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { $0.resource == "category" && $0.op == "create" })
        #expect(try await store.categoryStartersSeeded())
    }

    @Test("seeding in Russian materializes Russian names")
    func seedsLocalizedRussian() async throws {
        let store = try makeStore()
        let result = try await store.seedStarterCategoriesIfNeeded(names: ruNames)

        guard case let .seeded(seeded) = result else {
            Issue.record("expected seeded outcome")
            return
        }
        #expect(seeded.map(\.name) == ruNames)
        #expect(seeded.map(\.icon) == seedIcons)
    }

    @Test("a second seed attempt is a no-op (retry idempotency)")
    func retryDoesNotDuplicate() async throws {
        let store = try makeStore()
        _ = try await store.seedStarterCategoriesIfNeeded(names: enNames)
        let second = try await store.seedStarterCategoriesIfNeeded(names: enNames)

        #expect(second == .alreadySeeded)
        let stored = try await store.categories()
        #expect(stored.count == 7)
        let rows = try await store.outboxRows()
        #expect(rows.count == 7)
    }

    @Test("deleting every starter category does not re-seed")
    func noReseedAfterDeletion() async throws {
        let store = try makeStore()
        _ = try await store.seedStarterCategoriesIfNeeded(names: enNames)
        let seeded = try await store.categories()

        for category in seeded {
            try await store.deleteCategory(id: category.id)
        }
        #expect(try await store.categories().isEmpty)

        let retry = try await store.seedStarterCategoriesIfNeeded(names: enNames)
        #expect(retry == .alreadySeeded)
        #expect(try await store.categories().isEmpty)
    }

    @Test("eraseAll clears the seed marker so a new dataset seeds again")
    func reseedsAfterErase() async throws {
        let store = try makeStore()
        _ = try await store.seedStarterCategoriesIfNeeded(names: enNames)
        try await store.eraseAll()

        #expect(try await store.categories().isEmpty)
        #expect(!(try await store.categoryStartersSeeded()))

        let result = try await store.seedStarterCategoriesIfNeeded(names: ruNames)
        guard case let .seeded(seeded) = result else {
            Issue.record("expected reseed after erase")
            return
        }
        #expect(seeded.map(\.name) == ruNames)
    }

    @Test("seeded names persist as ordinary records and do not auto-rename")
    func seededNamesAreOrdinaryRecords() async throws {
        let store = try makeStore()
        let seededAt = Date(timeIntervalSinceReferenceDate: 10_000)
        _ = try await store.seedStarterCategoriesIfNeeded(names: enNames, now: seededAt)

        let stored = try await store.categories()
        #expect(stored.map(\.name).sorted() == enNames.sorted())
        // The records are editable ordinary categories.
        let first = try #require(stored.first)
        let outcome = try await store.updateCategory(
            id: first.id,
            draft: CategoryDraft(name: "Renamed", icon: .briefcase),
            now: seededAt.addingTimeInterval(1_000)
        )
        guard case let .saved(updated) = outcome else {
            Issue.record("expected saved, got \(outcome)")
            return
        }
        #expect(updated.name == "Renamed")
    }

    @Test("seeding requires exactly seven names")
    func seedingRequiresSevenNames() async throws {
        let store = try makeStore()
        await #expect(throws: Error.self) {
            try await store.seedStarterCategoriesIfNeeded(names: ["Work"])
        }
        #expect(try await store.categories().isEmpty)
        #expect(!(try await store.categoryStartersSeeded()))
    }
}

@Suite("LocalStore Category CRUD (category-management D1)")
struct LocalStoreCategoryMutationTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    @Test("createCategory with a valid draft persists state plus outbox atomically")
    func createPersistsWithOutbox() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let outcome = try await store.createCategory(
            draft: CategoryDraft(name: "  Sport  ", icon: .figureRun),
            id: "cat-1",
            now: now
        )

        guard case let .saved(category) = outcome else {
            Issue.record("expected saved, got \(outcome)")
            return
        }
        #expect(category.name == "Sport")
        #expect(category.icon == "figure.run")
        #expect(category.id == "cat-1")
        #expect(category.createdAt == now)

        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "Sport")

        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.resource == "category")
        #expect(row.op == "create")
        #expect(row.recordID == "cat-1")
        let payload = try #require(row.payload)
        let decoded = try JSONDecoder().decode(TimeOfLife.Category.self, from: Data(payload.utf8))
        #expect(decoded.name == "Sport")
        #expect(decoded.icon == "figure.run")
    }

    @Test("createCategory with a duplicate normalized name returns duplicate with the winner")
    func createDuplicateNormalized() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(draft: CategoryDraft(name: "Work", icon: .briefcase), id: "cat-1")
        let outcome = try await store.createCategory(draft: CategoryDraft(name: "  work  ", icon: .briefcase), id: "cat-2")

        guard case let .duplicate(winner) = outcome else {
            Issue.record("expected duplicate, got \(outcome)")
            return
        }
        #expect(winner.id == "cat-1")
        #expect(winner.name == "Work")
        #expect(try await store.categories().count == 1)
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
    }

    @Test("createCategory rejects empty and overlong names without persisting")
    func createInvalidName() async throws {
        let store = try makeStore()
        let empty = try await store.createCategory(draft: CategoryDraft(name: "   "), id: "cat-1")
        #expect(empty == .invalid(.empty))
        let long = try await store.createCategory(
            draft: CategoryDraft(name: String(repeating: "a", count: 61)), id: "cat-2")
        #expect(long == .invalid(.tooLong))
        #expect(try await store.categories().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("updateCategory renames, keeps identity, and enqueues an update outbox row")
    func updateRenames() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(
            draft: CategoryDraft(name: "Work", icon: .briefcase),
            id: "cat-1",
            now: Date(timeIntervalSinceReferenceDate: 4_000)
        )
        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let outcome = try await store.updateCategory(
            id: "cat-1",
            draft: CategoryDraft(name: "Deep Work", icon: .laptopcomputer),
            now: now
        )

        guard case let .saved(updated) = outcome else {
            Issue.record("expected saved, got \(outcome)")
            return
        }
        #expect(updated.id == "cat-1")
        #expect(updated.name == "Deep Work")
        #expect(updated.icon == "laptopcomputer")
        #expect(updated.updatedAt == now)
        #expect(updated.createdAt == Date(timeIntervalSinceReferenceDate: 4_000))

        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "Deep Work")
        #expect(stored?.icon == "laptopcomputer")

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        #expect(rows.last?.op == "update")
        let payload = try #require(rows.last?.payload)
        let decoded = try JSONDecoder().decode(TimeOfLife.Category.self, from: Data(payload.utf8))
        #expect(decoded.name == "Deep Work")
        #expect(decoded.icon == "laptopcomputer")
    }

    @Test("updateCategory to a case-insensitive collision returns duplicate without partial writes")
    func updateCollisionNoPartialWrite() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "cat-1")
        _ = try await store.createCategory(draft: CategoryDraft(name: "Health"), id: "cat-2")

        let outcome = try await store.updateCategory(
            id: "cat-2",
            draft: CategoryDraft(name: "  WORK  ", icon: .heart),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        guard case let .duplicate(winner) = outcome else {
            Issue.record("expected duplicate, got \(outcome)")
            return
        }
        #expect(winner.id == "cat-1")
        let stored = try await store.category(id: "cat-2")
        #expect(stored?.name == "Health")
        #expect(stored?.icon == "tag")
    }

    @Test("updateCategory to the same normalized name is allowed")
    func updateSameNormalizedAllowed() async throws {
        let store = try makeStore()
        let created = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = try await store.createCategory(
            draft: CategoryDraft(name: "Work"), id: "cat-1", now: created
        )

        let outcome = try await store.updateCategory(
            id: "cat-1",
            draft: CategoryDraft(name: "WORK", icon: .briefcase),
            now: created.addingTimeInterval(1_000)
        )
        guard case .saved = outcome else {
            Issue.record("expected saved, got \(outcome)")
            return
        }
        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "WORK")
    }

    @Test("updateCategory on a missing category returns missing")
    func updateMissing() async throws {
        let store = try makeStore()
        let outcome = try await store.updateCategory(
            id: "nonexistent",
            draft: CategoryDraft(name: "X"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        #expect(outcome == .missing)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("a concurrent normalized duplicate insert resolves to duplicate, never failure")
    func concurrentDuplicateResolves() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(draft: CategoryDraft(name: "Sport", icon: .figureRun), id: "cat-1")

        let outcome = try await store.createCategory(
            draft: CategoryDraft(name: "SPORT", icon: .figureRun),
            id: "cat-2"
        )
        guard case let .duplicate(winner) = outcome else {
            Issue.record("expected duplicate, got \(outcome)")
            return
        }
        #expect(winner.id == "cat-1")
        #expect(try await store.categories().count == 1)
    }

    @Test("the unique index on lower(name) rejects a direct duplicate insert")
    func uniqueIndexEnforcesCategoryUniqueness() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "cat-1")
        let duplicate = TimeOfLife.Category(
            id: "cat-2", name: "work", icon: "tag",
            createdAt: Date(), updatedAt: Date()
        )
        await #expect(throws: Error.self) {
            try await store.createCategory(duplicate)
        }
        #expect(try await store.categories().count == 1)
    }

    @Test("category(named:) finds by case-insensitive name")
    func categoryByName() async throws {
        let store = try makeStore()
        _ = try await store.createCategory(draft: CategoryDraft(name: "Deep Work"), id: "cat-1")
        let found = try await store.category(named: "  deep work  ")
        #expect(found?.id == "cat-1")
    }
}

@Suite("LocalStore Refinement")
struct LocalStoreRefinementTests {

    // MARK: - Helpers

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeActivity(
        id: String = "act-1",
        name: String = "Coding",
        notes: String? = nil,
        categoryIDs: [String] = [],
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 2_000)
    ) -> Activity {
        Activity(
            id: id,
            name: name,
            notes: notes,
            categoryIDs: categoryIDs,
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: updatedAt
        )
    }

    private func makeCategory(
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase"
    ) -> TimeOfLife.Category {
        TimeOfLife.Category(
            id: id,
            name: name,
            icon: icon,
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
    }

    // MARK: - Successful updates

    @Test("refineActivity updates name, notes, and Categories and enqueues an update outbox row")
    func refineUpdatesFields() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Deep Work", notes: "Focus session", categoryIDs: ["cat-2"]),
            now: now
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome, got \(outcome)")
            return
        }
        #expect(activity.id == "act-1")
        #expect(activity.name == "Deep Work")
        #expect(activity.notes == "Focus session")
        #expect(activity.categoryIDs == ["cat-2"])
        #expect(activity.updatedAt == now)
        #expect(activity.createdAt == Date(timeIntervalSinceReferenceDate: 1_000))

        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Deep Work")
        #expect(stored?.notes == "Focus session")
        #expect(stored?.categoryIDs == ["cat-2"])

        let rows = try await store.outboxRows()
        #expect(rows.count == 4)
        let updateRow = try #require(rows.last)
        #expect(updateRow.resource == "activity")
        #expect(updateRow.recordID == "act-1")
        #expect(updateRow.op == "update")
        let payload = try #require(updateRow.payload)
        let decoded = try JSONDecoder().decode(Activity.self, from: Data(payload.utf8))
        #expect(decoded.name == "Deep Work")
        #expect(decoded.notes == "Focus session")
        #expect(decoded.categoryIDs == ["cat-2"])
    }

    @Test("refineActivity preserves the identifier and createdAt")
    func refinePreservesIdentity() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Renamed"),
            now: Date(timeIntervalSinceReferenceDate: 6_000)
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        #expect(activity.id == "act-1")
        #expect(activity.createdAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(activity.name == "Renamed")
    }

    @Test("refineActivity with the same name updates only metadata")
    func refineSameName() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(name: "Coding"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Coding", notes: "Updated notes"),
            now: now
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        #expect(activity.name == "Coding")
        #expect(activity.notes == "Updated notes")
        #expect(activity.updatedAt == now)
    }

    @Test("refineActivity trims whitespace from name and notes")
    func refineTrimsWhitespace() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "  Deep Work  ", notes: "  Notes  "),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        #expect(activity.name == "Deep Work")
        #expect(activity.notes == "Notes")
    }

    @Test("refineActivity stores nil for empty notes")
    func refineEmptyNotesStoresNil() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(notes: "Old notes"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Coding", notes: "   "),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        #expect(activity.notes == nil)
        let stored = try await store.activity(id: "act-1")
        #expect(stored?.notes == nil)
    }

    @Test("refineActivity replaces Category joins atomically")
    func refineReplacesCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createActivity(makeActivity(categoryIDs: ["cat-1"]))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Coding", categoryIDs: ["cat-2"]),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case .updated = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        let stored = try await store.activity(id: "act-1")
        #expect(stored?.categoryIDs == ["cat-2"])
    }

    @Test("refineActivity clears Categories when the draft has none")
    func refineClearsCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createActivity(makeActivity(categoryIDs: ["cat-1"]))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Coding", categoryIDs: []),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case .updated = outcome else {
            Issue.record("expected updated outcome")
            return
        }
        let stored = try await store.activity(id: "act-1")
        #expect(stored?.categoryIDs.isEmpty == true)
    }

    // MARK: - Collision

    @Test("refineActivity rejects a normalized-name collision without partial writes")
    func refineCollisionNoPartialWrite() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(id: "act-1", name: "Coding"))
        try await store.createActivity(makeActivity(id: "act-2", name: "Reading"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Reading", notes: "Attempted"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case let .collision(winner) = outcome else {
            Issue.record("expected collision outcome, got \(outcome)")
            return
        }
        #expect(winner.id == "act-2")
        #expect(winner.name == "Reading")

        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Coding")
        #expect(stored?.notes == nil)

        let rows = try await store.outboxRows()
        let updateRows = rows.filter { $0.op == "update" }
        #expect(updateRows.isEmpty)
    }

    @Test("refineActivity rejects a case-insensitive collision")
    func refineCollisionCaseInsensitive() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(id: "act-1", name: "Coding"))
        try await store.createActivity(makeActivity(id: "act-2", name: "Reading"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "READING"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case let .collision(winner) = outcome else {
            Issue.record("expected collision outcome")
            return
        }
        #expect(winner.id == "act-2")
    }

    @Test("refineActivity allows renaming to the same normalized name")
    func refineSameNormalizedNoCollision() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity(name: "Coding"))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "CODING", notes: "Updated"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case let .updated(activity) = outcome else {
            Issue.record("expected updated outcome, got \(outcome)")
            return
        }
        #expect(activity.name == "CODING")
        #expect(activity.notes == "Updated")
    }

    // MARK: - Missing Activity

    @Test("refineActivity returns missing when the Activity does not exist")
    func refineMissing() async throws {
        let store = try makeStore()

        let outcome = try await store.refineActivity(
            id: "nonexistent",
            draft: ActivityDraft(name: "Coding"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        #expect(outcome == .missing)
        let rows = try await store.outboxRows()
        #expect(rows.isEmpty)
    }

    // MARK: - Invalid input

    @Test("refineActivity rejects an empty name")
    func refineInvalidEmpty() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "   "),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        #expect(outcome == .invalid(.empty))
        let stored = try await store.activity(id: "act-1")
        #expect(stored?.name == "Coding")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
    }

    @Test("refineActivity rejects an overlong name")
    func refineInvalidTooLong() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())

        let outcome = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: String(repeating: "a", count: 61)),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        #expect(outcome == .invalid(.tooLong))
    }

    // MARK: - Outbox payload

    @Test("refineActivity outbox row contains the complete updated Activity")
    func refineOutboxPayloadComplete() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createActivity(makeActivity())
        try? await Task.sleep(nanoseconds: 20_000_000)

        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        _ = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Deep Work", notes: "Focus", categoryIDs: ["cat-1"]),
            now: now
        )

        let rows = try await store.outboxRows()
        let updateRow = try #require(rows.last)
        let payload = try #require(updateRow.payload)
        let decoded = try JSONDecoder().decode(Activity.self, from: Data(payload.utf8))
        #expect(decoded.id == "act-1")
        #expect(decoded.name == "Deep Work")
        #expect(decoded.notes == "Focus")
        #expect(decoded.categoryIDs == ["cat-1"])
        #expect(decoded.updatedAt == now)
    }

    @Test("refineActivity does not create a new activity row")
    func refineDoesNotCreateNewRow() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let countBefore = try await store.activities().count
        try? await Task.sleep(nanoseconds: 20_000_000)

        _ = try await store.refineActivity(
            id: "act-1",
            draft: ActivityDraft(name: "Renamed"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        let countAfter = try await store.activities().count
        #expect(countBefore == countAfter)
    }
}

@Suite("LocalStore Category Associations (category-management D5)")
struct LocalStoreAssociationTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeCategory(id: String, name: String) -> TimeOfLife.Category {
        TimeOfLife.Category(
            id: id, name: name, icon: "tag",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
    }

    @Test("assigning multiple categories preserves selection order")
    func multipleCategoriesPreserveOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createCategory(makeCategory(id: "cat-3", name: "Travel"))

        let outcome = try await store.createOrResolveActivity(
            named: "Gym",
            categoryIDs: ["cat-2", "cat-1", "cat-3"]
        )
        guard case let .created(activity) = outcome else {
            Issue.record("expected created")
            return
        }
        #expect(activity.categoryIDs == ["cat-2", "cat-1", "cat-3"])

        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs == ["cat-2", "cat-1", "cat-3"])
    }

    @Test("de-duplicated ids preserve first-seen order")
    func duplicateIDsPreserveFirstSeenOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))

        let outcome = try await store.createOrResolveActivity(
            named: "Gym",
            categoryIDs: ["cat-2", "cat-2", "cat-1", "cat-2"]
        )
        guard case let .created(activity) = outcome else {
            Issue.record("expected created")
            return
        }
        #expect(activity.categoryIDs == ["cat-2", "cat-1"])
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs == ["cat-2", "cat-1"])
    }

    @Test("removing one assignment keeps the remaining order")
    func removingOneKeepsOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createCategory(makeCategory(id: "cat-3", name: "Travel"))
        let created = try await store.createOrResolveActivity(
            named: "Gym", categoryIDs: ["cat-1", "cat-2", "cat-3"]
        )
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }

        let outcome = try await store.refineActivity(
            id: activity.id,
            draft: ActivityDraft(name: "Gym", categoryIDs: ["cat-1", "cat-3"]),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        guard case .updated = outcome else {
            Issue.record("expected updated")
            return
        }
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs == ["cat-1", "cat-3"])
    }

    @Test("clearing all assignments leaves the activity valid")
    func clearingAllKeepsActivity() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["cat-1"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }

        let outcome = try await store.refineActivity(
            id: activity.id,
            draft: ActivityDraft(name: "Gym", categoryIDs: []),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        guard case let .updated(updated) = outcome else {
            Issue.record("expected updated, got \(outcome)")
            return
        }
        #expect(updated.categoryIDs.isEmpty)
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs.isEmpty == true)
        #expect(stored != nil)
    }

    @Test("an invalid category id rolls back fields, joins, and outbox together")
    func invalidAssociationRollsBackEverything() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["cat-1"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let rowsBefore = try await store.outboxRows().count

        let outcome = try await store.refineActivity(
            id: activity.id,
            draft: ActivityDraft(
                name: "Renamed Gym",
                notes: "attempted",
                categoryIDs: ["cat-1", "nonexistent-category"]
            ),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        guard case .invalidAssociation = outcome else {
            Issue.record("expected invalidAssociation, got \(outcome)")
            return
        }
        // The activity fields were rolled back.
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.name == "Gym")
        #expect(stored?.notes == nil)
        // The joins were rolled back (the original association remains).
        #expect(stored?.categoryIDs == ["cat-1"])
        // No update outbox row was written.
        let rows = try await store.outboxRows()
        #expect(rows.count == rowsBefore)
        #expect(rows.last?.op != "update")
    }

    @Test("the Activity outbox payload carries the complete ordered category set")
    func outboxPayloadCarriesOrderedCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        let created = try await store.createOrResolveActivity(
            named: "Gym", categoryIDs: ["cat-2", "cat-1"]
        )
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }

        let rows = try await store.outboxRows()
        let createRow = try #require(rows.first { $0.resource == "activity" && $0.op == "create" })
        let payload = try #require(createRow.payload)
        let decoded = try JSONDecoder().decode(Activity.self, from: Data(payload.utf8))
        #expect(decoded.categoryIDs == ["cat-2", "cat-1"])

        _ = try await store.refineActivity(
            id: activity.id,
            draft: ActivityDraft(name: "Gym", categoryIDs: ["cat-1", "cat-2"]),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        let rowsAfter = try await store.outboxRows()
        let updateRow = try #require(rowsAfter.last { $0.resource == "activity" && $0.op == "update" })
        let updatePayload = try #require(updateRow.payload)
        let decodedUpdate = try JSONDecoder().decode(Activity.self, from: Data(updatePayload.utf8))
        #expect(decodedUpdate.categoryIDs == ["cat-1", "cat-2"])
    }
}

@Suite("UndoBufferStore")
struct UndoBufferStoreTests {

    // MARK: - Helpers

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    /// A snapshot capturing an activity and one of its entries.
    private func makeSnapshot() throws -> DeletionSnapshot {
        let activity = Activity(
            id: "act-1",
            name: "Coding",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let entry = TimeEntry(
            id: "entry-1",
            activityID: "act-1",
            activityName: "Coding",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_500),
            endedAt: Date(timeIntervalSinceReferenceDate: 3_100),
            durationSeconds: 600,
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        return DeletionSnapshot(records: [
            DeletionSnapshot.Record(
                resource: "activity",
                recordID: activity.id,
                data: try JSONEncoder().encode(activity)
            ),
            DeletionSnapshot.Record(
                resource: "entry",
                recordID: entry.id,
                data: try JSONEncoder().encode(entry)
            ),
        ])
    }

    // MARK: - Tests

    @Test("enter then undo restores records, removes the buffer row, and creates no outbox row")
    func undoRestoresRecordsWithoutOutbox() async throws {
        let store = try makeStore()
        let snapshot = try makeSnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        let undo = UndoBufferStore(store: store)

        try await undo.enter(payload: payload, deletedAt: Date(timeIntervalSinceReferenceDate: 1_000))

        let bufferBeforeUndo = try await undo.mostRecent()
        #expect(bufferBeforeUndo != nil)
        let outboxBeforeUndo = try await store.outboxRows()
        #expect(outboxBeforeUndo.isEmpty)

        let bufferEntry = try #require(bufferBeforeUndo)
        try await undo.undo(id: bufferEntry.id)

        let restoredActivity = try await store.activity(id: "act-1")
        #expect(restoredActivity?.name == "Coding")
        let restoredEntry = try await store.entry(id: "entry-1")
        #expect(restoredEntry?.activityID == "act-1")
        #expect(restoredEntry?.durationSeconds == 600)

        let bufferAfterUndo = try await store.undoBufferMostRecent()
        #expect(bufferAfterUndo == nil)
        let outboxAfterUndo = try await store.outboxRows()
        #expect(outboxAfterUndo.isEmpty)
    }

    @Test("commitExpired with an expired window commits delete outbox rows")
    func commitExpiredCommitsDeletes() async throws {
        let store = try makeStore()
        let snapshot = try makeSnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(
            payload: payload,
            deletedAt: Date().addingTimeInterval(-60)
        )

        let undo = UndoBufferStore(store: store)
        try await undo.commitExpired(now: Date())

        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer == nil)

        let rows = try await store.outboxRows()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.op == "delete" && $0.payload == nil })
        #expect(rows.map(\.resource).sorted() == ["activity", "entry"])
        #expect(rows.map(\.recordID).sorted() == ["act-1", "entry-1"])
    }

    @Test("commitExpired within the window does nothing")
    func commitExpiredWithinWindowDoesNothing() async throws {
        let store = try makeStore()
        let snapshot = try makeSnapshot()
        let payload = try JSONEncoder().encode(snapshot)
        try await store.undoBufferEnter(
            payload: payload,
            deletedAt: Date().addingTimeInterval(-10)
        )

        let undo = UndoBufferStore(store: store)
        try await undo.commitExpired(now: Date())

        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer != nil)
        let outbox = try await store.outboxRows()
        #expect(outbox.isEmpty)
    }

    @Test("mostRecent returns the newest buffer row")
    func mostRecentReturnsNewest() async throws {
        let store = try makeStore()
        try await store.undoBufferEnter(
            payload: Data("older".utf8),
            deletedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        try await store.undoBufferEnter(
            payload: Data("newer".utf8),
            deletedAt: Date(timeIntervalSinceReferenceDate: 200)
        )

        let undo = UndoBufferStore(store: store)
        let entry = try await undo.mostRecent()
        let payloadString = entry.map { String(data: $0.payload, encoding: .utf8) }
        #expect(payloadString == "newer")
    }

    @Test("BufferEntry isExpired honors the 30 second wall-clock window")
    func bufferEntryExpiryBoundary() {
        let deletedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let entry = UndoBufferStore.BufferEntry(
            id: "b1",
            payload: Data("x".utf8),
            deletedAt: deletedAt
        )
        #expect(!entry.isExpired(now: deletedAt.addingTimeInterval(29.9)))
        #expect(entry.isExpired(now: deletedAt.addingTimeInterval(30.1)))
    }
}

@Suite("LocalStore Category Deletion & Undo (category-management D7)")
struct LocalStoreCategoryUndoTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    @Test("undoable deletion captures the category and its ordered associations and writes no outbox row")
    func deleteCapturesAssociationsWithoutOutbox() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        let created = try await store.createOrResolveActivity(
            named: "Gym", categoryIDs: ["cat-1"]
        )
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        let outcome = try await store.deleteCategoryUndoable(
            id: "cat-1",
            deletedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )

        guard case let .deleted(snapshot) = outcome else {
            Issue.record("expected deleted, got \(outcome)")
            return
        }
        #expect(snapshot.category.id == "cat-1")
        #expect(snapshot.activityIDs == [activity.id])

        #expect(try await store.category(id: "cat-1") == nil)
        // The activity itself survives.
        let stored = try await store.activity(id: activity.id)
        #expect(stored != nil)
        #expect(stored?.categoryIDs.isEmpty == true)
        // No outbox row was created while the deletion is in the buffer.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
        // The buffer holds the snapshot.
        #expect(try await store.undoBufferMostRecent() != nil)
    }

    @Test("undo restores the same category identity and assignments without any sync")
    func undoRestoresIdentityAndAssociations() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        let created = try await store.createOrResolveActivity(
            named: "Gym", categoryIDs: ["cat-1"]
        )
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        _ = try await store.deleteCategoryUndoable(id: "cat-1", deletedAt: Date())

        let buffer = try #require(try await store.undoBufferMostRecent())
        let restored = try await store.undoCategoryDeletion(bufferID: buffer.id)

        #expect(restored?.id == "cat-1")
        #expect(restored?.name == "Work")
        #expect(restored?.icon == "briefcase")
        let stored = try await store.category(id: "cat-1")
        #expect(stored?.name == "Work")
        // The ordered association was restored.
        let activityAfterUndo = try await store.activity(id: activity.id)
        #expect(activityAfterUndo?.categoryIDs == ["cat-1"])
        // Buffer row is gone; no outbox delete was ever created.
        #expect(try await store.undoBufferMostRecent() == nil)
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("expiry commits exactly one category delete outbox row")
    func expiryCommitsOneDelete() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(
            id: "cat-1",
            deletedAt: Date().addingTimeInterval(-60)
        )

        let undo = UndoBufferStore(store: store)
        try await undo.commitExpired(now: Date())

        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.resource == "category")
        #expect(deletes.first?.recordID == "cat-1")
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("no outbox row exists before the window expires")
    func noOutboxBeforeExpiry() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(id: "cat-1", deletedAt: Date())

        let undo = UndoBufferStore(store: store)
        try await undo.commitExpired(now: Date())

        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
        #expect(try await store.undoBufferMostRecent() != nil)
    }

    @Test("a newer deletion supersedes: only the most recent is undoable and the older commits at its own expiry")
    func supersessionCommitsOlderOnItsOwnExpiry() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createCategory(TimeOfLife.Category(id: "cat-2", name: "Health", icon: "heart"))

        // First deletion, older timestamp.
        _ = try await store.deleteCategoryUndoable(
            id: "cat-1",
            deletedAt: Date().addingTimeInterval(-40)
        )
        // Second deletion, newer — supersedes the first for undo.
        _ = try await store.deleteCategoryUndoable(id: "cat-2", deletedAt: Date())

        let undo = UndoBufferStore(store: store)
        let mostRecent = try await undo.mostRecent()
        let payload = mostRecent.flatMap { String(data: $0.payload, encoding: .utf8) }
        #expect(payload?.contains("cat-2") == true)

        // Foreground expiry commits the older deletion only.
        try await undo.commitExpired(now: Date())
        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.map(\.recordID) == ["cat-1"])
        #expect(try await store.category(id: "cat-2") == nil)
    }

    @Test("cold-launch navigation within the window still offers the deletion")
    func coldLaunchNavigationWithinWindow() async throws {
        let url = temporaryStoreURL()
        let deletedAt = Date()
        let store1 = try LocalStore(url: url)
        try await store1.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store1.deleteCategoryUndoable(id: "cat-1", deletedAt: deletedAt)

        // Simulate a relaunch at the same URL.
        let store2 = try LocalStore(url: url)
        let buffer = try await store2.undoBufferMostRecent()
        #expect(buffer != nil)
        let restored = try await store2.undoCategoryDeletion(bufferID: try #require(buffer).id)
        #expect(restored?.id == "cat-1")
        #expect(try await store2.category(id: "cat-1") != nil)
    }

    @Test("deleting an unknown category returns missing")
    func deleteMissingReturnsMissing() async throws {
        let store = try makeStore()
        let outcome = try await store.deleteCategoryUndoable(id: "nonexistent")
        #expect(outcome == .missing)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("deletion leaves entries and timer state untouched")
    func deletionLeavesEntriesAndTimerUntouched() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["cat-1"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        try await store.createEntry(TimeEntry(
            id: "entry-1", activityID: activity.id, activityName: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
        ))
        try await store.startTimer(activityID: activity.id, activityName: "Gym", startedAt: Date())

        _ = try await store.deleteCategoryUndoable(id: "cat-1")

        #expect(try await store.entry(id: "entry-1") != nil)
        #expect(try await store.timerState() != nil)
        let stored = try await store.activity(id: activity.id)
        #expect(stored != nil)
    }
}
