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
        let row = try #require(rows.last)
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
        try await store.createCategory(makeCategory(id: "cat-a"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createCategory(makeCategory(id: "cat-b"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.createCategory(makeCategory(id: "cat-c"))

        let rows = try await store.outboxRows()
        #expect(rows.map(\.recordID) == ["cat-a", "cat-b", "cat-c"])
        #expect(rows[0].createdAt <= rows[1].createdAt)
        #expect(rows[1].createdAt <= rows[2].createdAt)
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
