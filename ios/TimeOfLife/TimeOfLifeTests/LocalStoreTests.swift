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

    private func makeCategory(
        id: String = "cat-1",
        name: String = "Work",
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 2_000)
    ) -> Category {
        Category(
            id: id,
            name: name,
            icon: "briefcase",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: updatedAt
        )
    }

    private func makeEntry(
        id: String = "entry-1",
        activityText: String = "Coding",
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 2_500),
        source: String = "manual",
        sourceRef: String? = nil,
        notes: String = "",
        categoryIDs: [String] = [],
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 3_000)
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: activityText,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            source: source,
            sourceRef: sourceRef,
            categoryIDs: categoryIDs,
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: updatedAt
        )
    }

    // MARK: - Entry creation (owned fields + single outbox row)

    @Test("createEntry writes text, categories, notes, and one outbox row")
    func createEntryEnqueuesOutbox() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        let entry = makeEntry(notes: "note", categoryIDs: ["cat-1"])
        let outcome = try await store.createEntry(entry)

        guard case let .created(stored) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(stored == entry)

        let fetched = try await store.entry(id: entry.id)
        #expect(fetched == entry)

        let rows = try await store.outboxRows()
        // Seeded category create + entry create.
        #expect(rows.count == 2)
        let row = try #require(rows.first { $0.resource == "entry" })
        #expect(row.recordID == entry.id)
        #expect(row.op == "create")
        let payload = try #require(row.payload)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(payload.utf8))
        #expect(decoded == entry)
    }

    @Test("createEntry trims the text before persisting")
    func createEntryTrimsText() async throws {
        let store = try makeStore()
        let outcome = try await store.createEntry(makeEntry(activityText: "  Coding  "))
        guard case let .created(entry) = outcome else {
            Issue.record("expected created outcome, got \(outcome)")
            return
        }
        #expect(entry.activityText == "Coding")
        #expect(try await store.entry(id: entry.id)?.activityText == "Coding")
    }

    @Test("createEntry is case-sensitive: Gym and GYM are distinct entries")
    func createEntryIsCaseSensitive() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(id: "entry-1", activityText: "Gym"))
        _ = try await store.createEntry(makeEntry(id: "entry-2", activityText: "GYM"))
        let entries = try await store.entries()
        #expect(Set(entries.map(\.activityText)) == ["Gym", "GYM"])
    }

    @Test("createEntry rejects empty and overlong text without persisting")
    func createEntryValidatesText() async throws {
        let store = try makeStore()
        let empty = try await store.createEntry(makeEntry(id: "entry-1", activityText: "   "))
        #expect(empty == .invalid(.empty))
        let long = try await store.createEntry(
            makeEntry(id: "entry-2", activityText: String(repeating: "a", count: 61))
        )
        #expect(long == .invalid(.tooLong))
        #expect(try await store.entries().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("createEntry is idempotent on id")
    func createEntryIsIdempotent() async throws {
        let store = try makeStore()
        let entry = makeEntry()
        _ = try await store.createEntry(entry)
        let replay = try await store.createEntry(entry)
        guard case .created = replay else {
            Issue.record("expected created outcome on replay")
            return
        }
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(try await store.entries().count == 1)
    }

    @Test("createEntry rolls back everything when a category is unknown")
    func createEntryInvalidAssociationRollsBack() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        do {
            _ = try await store.createEntry(makeEntry(categoryIDs: ["cat-1", "ghost"]))
            Issue.record("expected invalidCategory throw")
        } catch let error as AssociationError {
            #expect(error == .invalidCategory("ghost"))
        }
        #expect(try await store.entry(id: "entry-1") == nil)
        // The seeded category's own outbox row survives; only the entry's
        // write must roll back.
        #expect(!(try await store.outboxRows()).contains { $0.recordID == "entry-1" })
    }

    @Test("createEntry stores an empty default notes value")
    func createEntryDefaultsNotes() async throws {
        let store = try makeStore()
        let outcome = try await store.createEntry(makeEntry())
        guard case let .created(entry) = outcome else {
            Issue.record("expected created outcome")
            return
        }
        #expect(entry.notes.isEmpty)
        #expect(try await store.entry(id: entry.id)?.notes.isEmpty == true)
    }

    // MARK: - Entry update (LWW)

    @Test("stale updateEntry returns false and changes nothing")
    func staleEntryUpdateIsRejected() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))

        let stale = makeEntry(activityText: "Stale", updatedAt: Date(timeIntervalSinceReferenceDate: 3_000))
        let applied = try await store.updateEntry(stale)
        #expect(!applied)

        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.activityText == "Coding")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
    }

    @Test("newer updateEntry updates text, notes, categories, and enqueues an update row")
    func newerEntryUpdateApplies() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        _ = try await store.createEntry(makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)))
        try? await Task.sleep(nanoseconds: 20_000_000)

        let newer = TimeEntry(
            id: "entry-1",
            activityText: "Deep work",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_500),
            endedAt: Date(timeIntervalSinceReferenceDate: 3_100),
            durationSeconds: 600,
            categoryIDs: ["cat-2"],
            notes: "updated",
            updatedAt: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        let applied = try await store.updateEntry(newer)
        #expect(applied)

        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.activityText == "Deep work")
        #expect(stored?.notes == "updated")
        #expect(stored?.categoryIDs == ["cat-2"])

        let rows = try await store.outboxRows()
        // Two category creates + entry create + entry update.
        #expect(rows.filter { $0.resource == "entry" }.count == 2)
        let updateRow = try #require(rows.last)
        #expect(updateRow.op == "update")
        #expect(updateRow.resource == "entry")
        #expect(updateRow.recordID == "entry-1")
    }

    @Test("editing one entry never changes another entry (per-entry isolation)")
    func entryEditIsIsolated() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        _ = try await store.createEntry(makeEntry(id: "entry-1", activityText: "Gym", categoryIDs: ["cat-1"]))
        _ = try await store.createEntry(makeEntry(id: "entry-2", activityText: "Gym", categoryIDs: ["cat-1"], updatedAt: Date(timeIntervalSinceReferenceDate: 3_500)))

        var edited = try #require(try await store.entry(id: "entry-1"))
        edited.activityText = "GYM"
        edited.categoryIDs = []
        edited.notes = "changed"
        edited.updatedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        _ = try await store.updateEntry(edited)

        let other = try await store.entry(id: "entry-2")
        #expect(other?.activityText == "Gym")
        #expect(other?.categoryIDs == ["cat-1"])
        #expect(other?.notes.isEmpty == true)
    }

    @Test("updateEntry on a missing entry returns false")
    func updateMissingEntry() async throws {
        let store = try makeStore()
        let applied = try await store.updateEntry(makeEntry())
        #expect(!applied)
    }

    // MARK: - Entry deletion

    @Test("deleteEntry removes the row and enqueues a delete outbox row")
    func deleteEntryEnqueuesDeleteOutbox() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.deleteEntry(id: "entry-1")

        #expect(try await store.entry(id: "entry-1") == nil)
        let rows = try await store.outboxRows()
        // Entry create + entry delete.
        #expect(rows.count == 2)
        let deleteRow = try #require(rows.first { $0.op == "delete" })
        #expect(deleteRow.resource == "entry")
        #expect(deleteRow.recordID == "entry-1")
        #expect(deleteRow.op == "delete")
        #expect(deleteRow.payload == nil)
    }

    // MARK: - Provenance

    @Test("entry provenance round-trips through entry(id:)")
    func provenanceRoundTrips() async throws {
        let store = try makeStore()
        let entry = makeEntry(source: "screentime", sourceRef: "st-callback-42")
        _ = try await store.createEntry(entry)

        let fetched = try await store.entry(id: entry.id)
        #expect(fetched == entry)
        #expect(fetched?.source == "screentime")
        #expect(fetched?.sourceRef == "st-callback-42")
    }

    @Test("a second entry with the same (source, sourceRef) is rejected")
    func duplicateProvenanceIsRejected() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(source: "screentime", sourceRef: "x"))

        let duplicate = makeEntry(id: "entry-2", source: "screentime", sourceRef: "x")
        let outcome = try await store.createEntry(duplicate)
        guard case .failure = outcome else {
            Issue.record("expected a failure outcome, got \(outcome)")
            return
        }
        #expect(try await store.entries().count == 1)
    }

    @Test("manual entries with nil sourceRef may duplicate")
    func manualEntriesWithoutSourceRefCanDuplicate() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(id: "entry-1", source: "manual", sourceRef: nil))
        _ = try await store.createEntry(makeEntry(id: "entry-2", source: "manual", sourceRef: nil))
        #expect(try await store.entries().count == 2)
    }

    // MARK: - Recents (timer-capture-experience D5)

    @Test("recents groups by exact text, newest started_at wins per group")
    func recentsGroupNewestWins() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        _ = try await store.createEntry(makeEntry(id: "e1", activityText: "Gym", categoryIDs: ["cat-1"]))
        _ = try await store.createEntry(makeEntry(id: "e2", activityText: "Gym", startedAt: Date(timeIntervalSinceReferenceDate: 2_400), updatedAt: Date(timeIntervalSinceReferenceDate: 3_100)))

        let recents = try await store.recents()
        #expect(recents.count == 1)
        #expect(recents.first?.activityText == "Gym")
        #expect(recents.first?.startedAt == Date(timeIntervalSinceReferenceDate: 2_500))
        #expect(recents.first?.categoryIDs == ["cat-1"])
    }

    @Test("recents identity is case-sensitive (Gym and GYM are distinct chips)")
    func recentsAreCaseSensitive() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(id: "e1", activityText: "Gym"))
        _ = try await store.createEntry(makeEntry(id: "e2", activityText: "GYM", updatedAt: Date(timeIntervalSinceReferenceDate: 3_100)))

        let recents = try await store.recents()
        #expect(recents.map(\.activityText) == ["GYM", "Gym"])
    }

    @Test("recents orders groups by their newest entry DESC and caps at limit")
    func recentsOrderAndCap() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        for index in 0..<8 {
            _ = try await store.createEntry(makeEntry(
                id: "e\(index)",
                activityText: "Text\(index)",
                startedAt: base.addingTimeInterval(Double(index))
            ))
        }

        let recents = try await store.recents(limit: 6)
        #expect(recents.count == 6)
        #expect(recents.map(\.activityText) == (2...7).reversed().map { "Text\($0)" })
        #expect(recents.first?.activityText == "Text7")
        #expect(recents.last?.activityText == "Text2")
    }

    @Test("recents is empty with no committed entries")
    func recentsEmpty() async throws {
        let store = try makeStore()
        #expect(try await store.recents().isEmpty)
    }

    // MARK: - Timer draft (remove-activities-layer D3/D4)

    @Test("saveTimerDraft persists trimmed text and ordered categories")
    func saveTimerDraftPersists() async throws {
        let store = try makeStore()
        try await store.saveTimerDraft(
            activityText: "  Gym  ",
            categoryIDs: ["b", "a", "b"],
            startedAt: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        let draft = try await store.timerDraft()
        #expect(draft?.activityText == "Gym")
        #expect(draft?.categoryIDs == ["b", "a"])
        #expect(draft?.startedAt == Date(timeIntervalSinceReferenceDate: 5_000))
        #expect(draft?.status == "running")
    }

    @Test("timer draft survives a simulated relaunch at the same database URL")
    func timerDraftSurvivesRelaunch() async throws {
        let url = temporaryStoreURL()
        let startedAt = Date(timeIntervalSinceReferenceDate: 5_000)

        let store1 = try LocalStore(url: url)
        try await store1.saveTimerDraft(activityText: "Coding", categoryIDs: ["cat-1"], startedAt: startedAt)

        let store2 = try LocalStore(url: url)
        let draft = try await store2.timerDraft()
        #expect(draft?.activityText == "Coding")
        #expect(draft?.categoryIDs == ["cat-1"])
        #expect(draft?.startedAt == startedAt)
        #expect(draft?.status == "running")

        try await store2.clearTimerDraft()

        let store3 = try LocalStore(url: url)
        #expect(try await store3.timerDraft() == nil)
    }

    @Test("updateTimerDraftCategoryIDs rewrites only the snapshot")
    func updateTimerDraftCategoryIDsIsSnapshotOnly() async throws {
        let store = try makeStore()
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: ["a"], startedAt: Date())
        try await store.updateTimerDraftCategoryIDs(["b", "a"])
        let draft = try await store.timerDraft()
        #expect(draft?.categoryIDs == ["b", "a"])
        #expect(draft?.activityText == "Gym")
    }

    @Test("updateTimerDraftCategoryIDs is a no-op with no draft")
    func updateDraftWithoutDraftIsNoOp() async throws {
        let store = try makeStore()
        try await store.updateTimerDraftCategoryIDs(["a"])
        #expect(try await store.timerDraft() == nil)
    }

    @Test("clearTimerDraft clears the singleton")
    func clearTimerDraft() async throws {
        let store = try makeStore()
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: Date())
        try await store.clearTimerDraft()
        #expect(try await store.timerDraft() == nil)
    }

    // MARK: - Erase

    @Test("eraseAll wipes every table")
    func eraseAllWipesEverything() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        _ = try await store.createEntry(makeEntry())
        try await store.saveTimerDraft(activityText: "Coding", categoryIDs: [], startedAt: Date())
        try await store.setLastSyncedAt(resource: "entry", date: Date())
        try await store.undoBufferEnter(payload: Data("snapshot".utf8), deletedAt: Date())

        try await store.eraseAll()

        let categories = try await store.categories()
        #expect(categories.isEmpty)
        let entries = try await store.entries()
        #expect(entries.isEmpty)
        let state = try await store.timerDraft()
        #expect(state == nil)
        let outbox = try await store.outboxRows()
        #expect(outbox.isEmpty)
        let buffer = try await store.undoBufferMostRecent()
        #expect(buffer == nil)
        let cursor = try await store.lastSyncedAt(resource: "entry")
        #expect(cursor == nil)
    }

    // MARK: - Sync state

    @Test("lastSyncedAt stores and advances per resource")
    func syncStateAdvancesCursor() async throws {
        let store = try makeStore()
        let initial = try await store.lastSyncedAt(resource: "entry")
        #expect(initial == nil)

        let first = Date(timeIntervalSinceReferenceDate: 10_000)
        let second = Date(timeIntervalSinceReferenceDate: 20_000)
        try await store.setLastSyncedAt(resource: "entry", date: first)
        let readBack = try await store.lastSyncedAt(resource: "entry")
        #expect(readBack == first)

        try await store.setLastSyncedAt(resource: "entry", date: secondOf(first, second))
        let advanced = try await store.lastSyncedAt(resource: "entry")
        #expect(advanced == second)

        let otherResource = try await store.lastSyncedAt(resource: "category")
        #expect(otherResource == nil)
    }

    private func secondOf(_ first: Date, _ second: Date) -> Date { second }

    // MARK: - Outbox ordering

    @Test("outboxRows returns oldest first")
    func outboxRowsAreOldestFirst() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(id: "e-a", activityText: "Alpha"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        _ = try await store.createEntry(makeEntry(id: "e-b", activityText: "Beta"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        _ = try await store.createEntry(makeEntry(id: "e-c", activityText: "Gamma"))

        let rows = try await store.outboxRows()
        #expect(rows.map(\.recordID) == ["e-a", "e-b", "e-c"])
        #expect(rows[0].createdAt <= rows[1].createdAt)
        #expect(rows[1].createdAt <= rows[2].createdAt)
    }

    // MARK: - Deletion tombstones (cross-device-delete-propagation)

    @Test("entry tombstone removes the row (joins cascade) and drops its pending create/update rows")
    func entryTombstoneDropsPendingRows() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        _ = try await store.createEntry(makeEntry(categoryIDs: ["cat-1"]))
        try? await Task.sleep(nanoseconds: 20_000_000)
        var bumped = makeEntry(categoryIDs: ["cat-1"])
        bumped.updatedAt = Date(timeIntervalSinceReferenceDate: 5_000)
        _ = try await store.updateEntry(bumped)

        try await store.applyDeletionTombstone(
            Deletion(resource: "entry", recordID: "entry-1", deletedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        )

        #expect(try await store.entry(id: "entry-1") == nil)
        // The category's create row survives; only the entry's rows were dropped.
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.resource == "category")
    }

    @Test("category tombstone removes joins and the row while entries survive untagged")
    func categoryTombstoneRemovesJoinsOnly() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        _ = try await store.createEntry(makeEntry(categoryIDs: ["cat-1"]))

        try await store.applyDeletionTombstone(
            Deletion(resource: "category", recordID: "cat-1", deletedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        )

        #expect(try await store.category(id: "cat-1") == nil)
        let stored = try await store.entry(id: "entry-1")
        #expect(stored != nil)
        #expect(stored?.activityText == "Coding")
        #expect(stored?.categoryIDs.isEmpty == true)
        // The entry's create row is untouched.
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.resource == "entry")
        #expect(rows.first?.recordID == "entry-1")
    }

    @Test("a pending DELETE outbox row survives tombstone application")
    func tombstoneKeepsPendingDeleteRow() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())
        try? await Task.sleep(nanoseconds: 20_000_000)
        try await store.deleteEntry(id: "entry-1")
        try await store.applyDeletionTombstone(
            Deletion(resource: "entry", recordID: "entry-1", deletedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        )

        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "entry" && $0.recordID == "entry-1" && $0.op == "delete" })
        #expect(rows.count == 1)
        #expect(rows.first?.op == "delete")
    }

    @Test("a clean local row newer than the tombstone is kept (R1)")
    func staleTombstoneKeepsCleanNewerRow() async throws {
        let store = try makeStore()
        let recreated = makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 8_000))
        try await store.mergeEntry(recreated)

        try await store.applyDeletionTombstone(
            Deletion(resource: "entry", recordID: "entry-1", deletedAt: Date(timeIntervalSinceReferenceDate: 5_000))
        )

        #expect(try await store.entry(id: "entry-1") == recreated)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("a dirty row older than the tombstone is still deleted and its pending rows dropped")
    func tombstoneDeletesDirtyRow() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(updatedAt: Date(timeIntervalSinceReferenceDate: 8_000)))
        try? await Task.sleep(nanoseconds: 20_000_000)
        var bumped = makeEntry()
        bumped.updatedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        _ = try await store.updateEntry(bumped)

        try await store.applyDeletionTombstone(
            Deletion(resource: "entry", recordID: "entry-1", deletedAt: Date(timeIntervalSinceReferenceDate: 7_000))
        )

        #expect(try await store.entry(id: "entry-1") == nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("an activity tombstone is a no-op (the resource no longer exists)")
    func activityTombstoneIsNoOp() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())

        try await store.applyDeletionTombstone(
            Deletion(resource: "activity", recordID: "ghost", deletedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        )

        #expect(try await store.entry(id: "entry-1") != nil)
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
    }

    @Test("a tombstone for an unknown id is a no-op")
    func unknownIDTombstoneIsNoOp() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())

        try await store.applyDeletionTombstone(
            Deletion(resource: "category", recordID: "unknown", deletedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        )

        #expect(try await store.entry(id: "entry-1") != nil)
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
    }

    // MARK: - Merge (prune-unknown-category, D7)

    @Test("mergeEntry prunes unknown category ids and keeps the remainder")
    func mergeEntryPrunesUnknownCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory())
        let serverEntry = makeEntry(categoryIDs: ["cat-1", "server-only"])
        try await store.mergeEntry(serverEntry)

        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.activityText == "Coding")
        #expect(stored?.categoryIDs == ["cat-1"])
        // mergeEntry enqueues nothing; only the seeded category create remains.
        #expect(!(try await store.outboxRows()).contains { $0.resource == "entry" })
    }

    // MARK: - Account-switch adoption (fix-cross-account-id-collision)

    @Test("switchSyncAccountIfNeeded adopts clean locals under fresh ids, drops stale updates, preserves deletes")
    func switchAccountAdoptsFreshIDs() async throws {
        let store = try makeStore()
        // Clean previously-synced rows for account A (merged: no outbox).
        try await store.mergeCategory(makeCategory(id: "cat-1", name: "Sport"))
        try await store.mergeEntry(
            makeEntry(id: "entry-1", activityText: "Gym", notes: "Leg day", categoryIDs: ["cat-1"])
        )
        // A previously-synced category with a queued update: superseded by adoption.
        try await store.mergeCategory(makeCategory(id: "cat-2", name: "Music"))
        let updatedCat2 = Category(
            id: "cat-2", name: "Music", icon: "music.note",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 9_000)
        )
        #expect(try await store.updateCategory(updatedCat2))
        // A never-pushed create keeps its device id untouched.
        _ = try await store.createEntry(
            makeEntry(id: "entry-2", activityText: "Run", categoryIDs: ["cat-1"])
        )
        // A pending delete still drains.
        try await store.mergeEntry(makeEntry(id: "entry-3", activityText: "Old"))
        try await store.deleteEntry(id: "entry-3")
        try await store.setSyncAccountId("user-A")
        try await store.setLastSyncedAt(resource: "entry", date: Date(timeIntervalSinceReferenceDate: 8_000))

        #expect(try await store.switchSyncAccountIfNeeded(to: "user-B"))

        // Old relay-global ids are gone; content preserved under fresh ids.
        #expect(try await store.category(id: "cat-1") == nil)
        #expect(try await store.category(id: "cat-2") == nil)
        #expect(try await store.entry(id: "entry-1") == nil)
        let cats = try await store.categories()
        #expect(cats.count == 2)
        #expect(Set(cats.map(\.name)) == ["Sport", "Music"])
        #expect(cats.allSatisfy { $0.id != "cat-1" && $0.id != "cat-2" })
        let sportID = try #require(cats.first { $0.name == "Sport" }?.id)
        #expect(try #require(cats.first { $0.name == "Music" }).icon == "music.note")
        let entries = try await store.entries()
        #expect(entries.count == 2)
        let freshEntry = try #require(entries.first { $0.id != "entry-2" })
        #expect(freshEntry.activityText == "Gym")
        #expect(freshEntry.notes == "Leg day")
        #expect(freshEntry.categoryIDs == [sportID])
        // The never-pushed create is untouched but follows the fresh category id.
        #expect(try await store.entry(id: "entry-2")?.categoryIDs == [sportID])

        let rows = try await store.outboxRows()
        // Two category creates + two entry creates + the preserved delete.
        #expect(rows.count == 5)
        #expect(rows.filter { $0.resource == "category" && $0.op == "create" }.count == 2)
        #expect(rows.filter { $0.resource == "entry" && $0.op == "create" }.count == 2)
        #expect(rows.contains { $0.resource == "entry" && $0.recordID == "entry-3" && $0.op == "delete" })
        // No row still references an adopted-away id (stale updates dropped).
        #expect(!rows.contains { ["cat-1", "cat-2", "entry-1"].contains($0.recordID) })
        // The kept create payload references the fresh category id.
        let keptRow = try #require(rows.first { $0.resource == "entry" && $0.recordID == "entry-2" })
        let keptPayload = try #require(keptRow.payload)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(keptPayload.utf8))
        #expect(decoded.categoryIDs == [sportID])

        // Cursors were reset and the stored account advanced …
        #expect(try await store.lastSyncedAt(resource: "entry") == nil)
        #expect(try await store.syncAccountId() == "user-B")
        // … and re-sign-in to the same account is a no-op.
        #expect(try await store.switchSyncAccountIfNeeded(to: "user-B") == false)
        #expect(try await store.outboxRows().count == 5)
    }

    @Test("switching back before the drain leaves queued rows untouched under their adopted ids")
    func switchBackKeepsQueuedAdoption() async throws {
        let store = try makeStore()
        try await store.mergeCategory(makeCategory(id: "cat-1", name: "Sport"))
        try await store.setSyncAccountId("user-A")

        #expect(try await store.switchSyncAccountIfNeeded(to: "user-B"))
        let adoptedID = try #require((try await store.categories()).first?.id)
        #expect(adoptedID != "cat-1")
        #expect(try await store.outboxRows().count == 1)

        // The drain has not run yet, so the adopted rows still carry outbox
        // rows: switching back keeps them untouched (no second rekey) and the
        // pending push lands them on the original account under the
        // collision-free adopted ids — no cross-talk either way.
        #expect(try await store.switchSyncAccountIfNeeded(to: "user-A"))
        #expect(try await store.syncAccountId() == "user-A")
        #expect(try #require((try await store.categories()).first?.id) == adoptedID)
        #expect((try await store.outboxRows()).map(\.recordID) == [adoptedID])
    }

    // MARK: - Adoption map (fix-round-trip-duplication)

    @Test("adoption records old-to-new id mappings and resolves them transitively")
    func adoptionMapRecordsAndResolves() async throws {
        let store = try makeStore()
        try await store.mergeCategory(makeCategory(id: "cat-A", name: "Sport"))
        try await store.mergeEntry(makeEntry(id: "e-A", activityText: "Gym", categoryIDs: ["cat-A"]))
        try await store.setSyncAccountId("user-A")

        #expect(try await store.switchSyncAccountIfNeeded(to: "user-B"))
        let freshCat = try #require(try await store.categories().first)
        #expect(freshCat.id != "cat-A")
        let freshEntry = try #require(try await store.entries().first)
        #expect(freshEntry.id != "e-A")

        // Map rows were written in the adoption transaction.
        #expect(try await store.resolveAdoption(resource: "category", id: "cat-A") == freshCat.id)
        #expect(try await store.resolveAdoption(resource: "entry", id: "e-A") == freshEntry.id)
        // Unknown ids resolve to themselves.
        #expect(try await store.resolveAdoption(resource: "entry", id: "unknown") == "unknown")

        // A heal extends the chain; resolution follows it transitively.
        let healedCat = try #require(try await store.healCategoryCollision(recordID: freshCat.id))
        let healedEntry = try #require(try await store.healEntryCollision(recordID: freshEntry.id))
        #expect(try await store.resolveAdoption(resource: "category", id: "cat-A") == healedCat.id)
        #expect(try await store.resolveAdoption(resource: "category", id: freshCat.id) == healedCat.id)
        #expect(try await store.resolveAdoption(resource: "entry", id: "e-A") == healedEntry.id)
        #expect(try await store.resolveAdoption(resource: "entry", id: freshEntry.id) == healedEntry.id)
    }

    // MARK: - Duplicate convergence (fix-round-trip-duplication)

    @Test("convergeDuplicateEntries folds byte-identical generations and keeps divergent copies")
    func convergeDuplicateEntriesFoldsIdentical() async throws {
        let store = try makeStore()
        try await store.mergeCategory(makeCategory(id: "cat-1", name: "Work"))
        let base = Date(timeIntervalSinceReferenceDate: 2_500)
        // Three identical generations (as after two account round trips).
        for id in ["e-1", "e-2", "e-3"] {
            try await store.mergeEntry(
                makeEntry(id: id, activityText: "Coding", startedAt: base, categoryIDs: ["cat-1"])
            )
        }
        // A divergent copy (user-edited notes) must survive untouched.
        try await store.mergeEntry(
            makeEntry(id: "e-4", activityText: "Coding", startedAt: base, notes: "edited", categoryIDs: ["cat-1"])
        )
        // Identical content but a pending create: excluded from folding.
        _ = try await store.createEntry(
            makeEntry(id: "e-5", activityText: "Coding", startedAt: base, categoryIDs: ["cat-1"])
        )
        // Buffered deletion: stays buffered, never enqueued for the relay.
        _ = try await store.createEntry(
            makeEntry(id: "e-6", activityText: "Coding", startedAt: base, categoryIDs: ["cat-1"])
        )
        _ = try await store.deleteEntryUndoable(id: "e-6")
        // Committed deletion: no second delete row is enqueued.
        try await store.mergeEntry(
            makeEntry(id: "e-7", activityText: "Coding", startedAt: base, categoryIDs: ["cat-1"])
        )
        try await store.deleteEntry(id: "e-7")

        let report = try await store.convergeDuplicateEntriesIfNeeded(accountID: "user-A")
        #expect(report.foldedGroups == 1)
        #expect(report.foldedRows == 2)

        // Deterministic survivor: intact refs, earliest createdAt, smallest id.
        let live = try await store.entries()
        #expect(Set(live.map(\.id)) == ["e-1", "e-4", "e-5"])
        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }.map(\.recordID).sorted()
        #expect(deletes == ["e-2", "e-3", "e-7"])
        #expect(rows.contains { $0.resource == "entry" && $0.recordID == "e-5" && $0.op == "create" })
        #expect(!rows.contains { $0.recordID == "e-4" })
        // e-6 keeps its never-pushed create (the undoable delete clears
        // nothing while buffered) but gains no delete row.
        #expect(!rows.contains { $0.recordID == "e-6" && $0.op == "delete" })
        // The buffered snapshot is untouched.
        #expect(try await store.isBufferedForDeletion(resource: "entry", recordID: "e-6"))

        // Second run is a no-op (once-flag).
        let again = try await store.convergeDuplicateEntriesIfNeeded(accountID: "user-A")
        #expect(again.foldedGroups == 0)
        #expect(again.foldedRows == 0)
        #expect(try await store.entries().count == 3)
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
            Issue.record("expected seeded outcome, got \(result)")
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

    @Test("seeding skips names already present instead of failing the whole set")
    func seedsSkipExistingNames() async throws {
        let store = try makeStore()
        // Relay-merged rows present without the marker (erase-then-sync shape).
        try await store.createCategory(
            Category(id: "server-sport", name: "Sport", icon: "figure.run")
        )

        let result = try await store.seedStarterCategoriesIfNeeded(names: enNames)

        guard case let .seeded(seeded) = result else {
            Issue.record("expected seeded outcome")
            return
        }
        // Six inserted; the present name kept its identity and got no new row.
        #expect(seeded.count == 6)
        #expect(seeded.allSatisfy { $0.name != "Sport" })
        #expect(try await store.category(id: "server-sport")?.name == "Sport")
        let stored = try await store.categories()
        #expect(stored.count == 7)
        let rows = try await store.outboxRows()
        #expect(rows.count == 7)
        #expect(try await store.categoryStartersSeeded())
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
        let decoded = try JSONDecoder().decode(Category.self, from: Data(payload.utf8))
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
        let decoded = try JSONDecoder().decode(Category.self, from: Data(payload.utf8))
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
        let duplicate = Category(
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

@Suite("LocalStore Entry-Category Associations (category-management D5)")
struct LocalStoreAssociationTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeCategory(id: String, name: String) -> Category {
        Category(
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

        let outcome = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(),
            categoryIDs: ["cat-2", "cat-1", "cat-3"]
        ))
        guard case let .created(entry) = outcome else {
            Issue.record("expected created")
            return
        }
        #expect(entry.categoryIDs == ["cat-2", "cat-1", "cat-3"])

        let stored = try await store.entry(id: "e1")
        #expect(stored?.categoryIDs == ["cat-2", "cat-1", "cat-3"])
    }

    @Test("de-duplicated ids preserve first-seen order")
    func duplicateIDsPreserveFirstSeenOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))

        let outcome = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(),
            categoryIDs: ["cat-2", "cat-2", "cat-1", "cat-2"]
        ))
        guard case let .created(entry) = outcome else {
            Issue.record("expected created")
            return
        }
        #expect(entry.categoryIDs == ["cat-2", "cat-1"])
        let stored = try await store.entry(id: "e1")
        #expect(stored?.categoryIDs == ["cat-2", "cat-1"])
    }

    @Test("removing one assignment keeps the remaining order")
    func removingOneKeepsOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createCategory(makeCategory(id: "cat-3", name: "Travel"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(),
            categoryIDs: ["cat-1", "cat-2", "cat-3"]
        ))

        var updated = try #require(try await store.entry(id: "e1"))
        updated.categoryIDs = ["cat-1", "cat-3"]
        updated.updatedAt = Date().addingTimeInterval(60)
        let applied = try await store.updateEntry(updated)
        #expect(applied)
        let stored = try await store.entry(id: "e1")
        #expect(stored?.categoryIDs == ["cat-1", "cat-3"])
    }

    @Test("clearing all assignments leaves the entry valid")
    func clearingAllKeepsEntry() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(), categoryIDs: ["cat-1"]
        ))

        var updated = try #require(try await store.entry(id: "e1"))
        updated.categoryIDs = []
        updated.updatedAt = Date().addingTimeInterval(60)
        let applied = try await store.updateEntry(updated)
        #expect(applied)
        let stored = try await store.entry(id: "e1")
        #expect(stored?.categoryIDs.isEmpty == true)
        #expect(stored != nil)
    }

    @Test("the entry outbox payload carries the complete ordered category set")
    func outboxPayloadCarriesOrderedCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(makeCategory(id: "cat-2", name: "Health"))
        try await store.createCategory(makeCategory(id: "cat-1", name: "Work"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(),
            categoryIDs: ["cat-2", "cat-1"]
        ))

        let rows = try await store.outboxRows()
        let createRow = try #require(rows.first { $0.resource == "entry" && $0.op == "create" })
        let payload = try #require(createRow.payload)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(payload.utf8))
        #expect(decoded.categoryIDs == ["cat-2", "cat-1"])
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

    /// A snapshot capturing a category and one of its entries.
    private func makeSnapshot() throws -> DeletionSnapshot {
        let category = Category(
            id: "cat-1",
            name: "Work",
            icon: "briefcase",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let entry = TimeEntry(
            id: "entry-1",
            activityText: "Coding",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_500),
            endedAt: Date(timeIntervalSinceReferenceDate: 3_100),
            durationSeconds: 600,
            categoryIDs: ["cat-1"],
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        return DeletionSnapshot(records: [
            DeletionSnapshot.Record(
                resource: "category",
                recordID: category.id,
                data: try JSONEncoder().encode(category)
            ),
            DeletionSnapshot.Record(
                resource: "entry",
                recordID: entry.id,
                data: try JSONEncoder().encode(entry)
            ),
        ])
    }

    // MARK: - Tests

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

    @Test("undoable deletion captures the category and its ordered entry associations and writes no outbox row")
    func deleteCapturesAssociationsWithoutOutbox() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(), categoryIDs: ["cat-1"]
        ))
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
        #expect(snapshot.entryIDs == ["e1"])

        #expect(try await store.category(id: "cat-1") == nil)
        // The entry itself survives, untagged.
        let stored = try await store.entry(id: "e1")
        #expect(stored != nil)
        #expect(stored?.activityText == "Gym")
        #expect(stored?.categoryIDs.isEmpty == true)
        // No outbox row was created while the deletion is in the buffer.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
        // The buffer holds the snapshot.
        #expect(try await store.undoBufferMostRecent() != nil)
    }

    @Test("undo restores the same category identity and entry associations without any sync")
    func undoRestoresIdentityAndAssociations() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym", startedAt: Date(), categoryIDs: ["cat-1"]
        ))
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
        let entryAfterUndo = try await store.entry(id: "e1")
        #expect(entryAfterUndo?.categoryIDs == ["cat-1"])
        // Buffer row is gone; no outbox delete was ever created.
        #expect(try await store.undoBufferMostRecent() == nil)
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("commitAll commits exactly one category delete outbox row")
    func commitAllCommitsOneCategoryDelete() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(
            id: "cat-1",
            deletedAt: Date().addingTimeInterval(-60)
        )

        let undo = UndoBufferStore(store: store)
        try await undo.commitAll()

        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.resource == "category")
        #expect(deletes.first?.recordID == "cat-1")
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("no outbox row exists while the deletion is buffered")
    func noOutboxWhileBuffered() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(id: "cat-1", deletedAt: Date())

        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
        #expect(try await store.undoBufferMostRecent() != nil)
    }

    @Test("a newer deletion supersedes for undo; both stay buffered until restart")
    func supersessionKeepsBothBufferedUntilRestart() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createCategory(Category(id: "cat-2", name: "Health", icon: "heart"))

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

        // A restart commits every buffered deletion — nothing expires early.
        try await undo.commitAll()
        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.map(\.recordID).sorted() == ["cat-1", "cat-2"])
        #expect(try await store.category(id: "cat-2") == nil)
    }

    @Test("cold launch commits the buffered deletion instead of offering it")
    func coldLaunchCommitsBufferedDeletion() async throws {
        let url = temporaryStoreURL()
        let deletedAt = Date()
        let store1 = try LocalStore(url: url)
        try await store1.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store1.deleteCategoryUndoable(id: "cat-1", deletedAt: deletedAt)

        // Simulate a restart at the same URL: the launch reconciliation
        // finalizes whatever the previous process buffered.
        let store2 = try LocalStore(url: url)
        try await UndoBufferStore(store: store2).commitAll()
        #expect(try await store2.undoBufferMostRecent() == nil)
        let rows = try await store2.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.recordID == "cat-1")
        #expect(try await store2.category(id: "cat-1") == nil)
    }

    @Test("deleting an unknown category returns missing")
    func deleteMissingReturnsMissing() async throws {
        let store = try makeStore()
        let outcome = try await store.deleteCategoryUndoable(id: "nonexistent")
        #expect(outcome == .missing)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("deletion leaves entries, their text/notes/timings, and the timer draft untouched")
    func deletionLeavesEntriesAndTimerUntouched() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            categoryIDs: ["cat-1"], notes: "kept"
        ))
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: ["cat-1"], startedAt: Date())

        _ = try await store.deleteCategoryUndoable(id: "cat-1")

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityText == "Gym")
        #expect(entry?.notes == "kept")
        #expect(entry?.durationSeconds == 600)
        #expect(try await store.timerDraft()?.activityText == "Gym")
    }

    @Test("entry decoder refuses a category-owned row, leaving the buffer intact (D10)")
    func foreignDecodersRefuseCategoryRow() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(id: "cat-1", deletedAt: Date())

        let buffer = try #require(try await store.undoBufferMostRecent())
        #expect(try await store.entryDeletionSnapshot(bufferID: buffer.id) == nil)
        #expect(try await store.undoEntryDeletion(bufferID: buffer.id) == nil)
        // The category row is untouched and still restorable by its owner.
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.undoCategoryDeletion(bufferID: buffer.id)?.id == "cat-1")
    }
}

@Suite("LocalStore Entry Deletion & Undo (entry-editor)")
struct LocalStoreEntryUndoTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeEntry(
        id: String = "entry-1",
        source: String = "manual",
        categoryIDs: [String] = [],
        notes: String = ""
    ) -> TimeEntry {
        TimeEntry(
            id: id, activityText: "Running",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: source, categoryIDs: categoryIDs, notes: notes
        )
    }

    @Test("undoable entry deletion removes the entry and writes no outbox row")
    func deleteRemovesEntryWithoutOutbox() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.createEntry(makeEntry(categoryIDs: ["cat-1"], notes: "n"))

        let outcome = try await store.deleteEntryUndoable(
            id: "entry-1",
            deletedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )

        guard case let .deleted(snapshot) = outcome else {
            Issue.record("expected deleted, got \(outcome)")
            return
        }
        #expect(snapshot.id == "entry-1")
        #expect(snapshot.activityText == "Running")
        #expect(snapshot.durationSeconds == 600)
        #expect(try await store.entry(id: "entry-1") == nil)
        // No outbox row was created while the deletion is in the buffer.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
        // The buffer holds the snapshot.
        let buffer = try #require(try await store.undoBufferMostRecent())
        #expect(try await store.entryDeletionSnapshot(bufferID: buffer.id)?.id == "entry-1")
    }

    @Test("undo restores the same entry identity, categories, and values without any sync")
    func undoRestoresEntryWithoutSync() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "cat-1", name: "Work", icon: "briefcase"))
        _ = try await store.createEntry(makeEntry(source: "garmin", categoryIDs: ["cat-1"], notes: "kept"))
        _ = try await store.deleteEntryUndoable(id: "entry-1", deletedAt: Date())

        let buffer = try #require(try await store.undoBufferMostRecent())
        let restored = try await store.undoEntryDeletion(bufferID: buffer.id)

        #expect(restored?.id == "entry-1")
        #expect(restored?.activityText == "Running")
        #expect(restored?.durationSeconds == 600)
        #expect(restored?.source == "garmin")
        #expect(restored?.categoryIDs == ["cat-1"])
        #expect(restored?.notes == "kept")
        let stored = try await store.entry(id: "entry-1")
        #expect(stored?.activityText == "Running")
        // Buffer row is gone; no outbox delete was ever created.
        #expect(try await store.undoBufferMostRecent() == nil)
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("commitAll commits exactly one entry delete outbox row")
    func commitAllCommitsOneEntryDelete() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())
        _ = try await store.deleteEntryUndoable(
            id: "entry-1",
            deletedAt: Date().addingTimeInterval(-60)
        )

        let undo = UndoBufferStore(store: store)
        try await undo.commitAll()

        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.resource == "entry")
        #expect(deletes.first?.recordID == "entry-1")
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("deleting an unknown entry returns missing and buffers nothing")
    func deleteMissingReturnsMissing() async throws {
        let store = try makeStore()
        let outcome = try await store.deleteEntryUndoable(id: "nonexistent")
        #expect(outcome == .missing)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("a newer entry deletion supersedes an older one for undo")
    func supersessionKeepsNewestUndoable() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry(id: "entry-1"))
        _ = try await store.createEntry(makeEntry(id: "entry-2"))

        _ = try await store.deleteEntryUndoable(
            id: "entry-1",
            deletedAt: Date().addingTimeInterval(-40)
        )
        _ = try await store.deleteEntryUndoable(id: "entry-2", deletedAt: Date())

        let undo = UndoBufferStore(store: store)
        let mostRecent = try await undo.mostRecent()
        let payload = mostRecent.flatMap { String(data: $0.payload, encoding: .utf8) }
        #expect(payload?.contains("entry-2") == true)

        // A restart commits every buffered deletion — nothing expires early.
        try await undo.commitAll()
        let rows = try await store.outboxRows()
        let deletes = rows.filter { $0.op == "delete" }
        #expect(deletes.map(\.recordID).sorted() == ["entry-1", "entry-2"])
        #expect(try await store.entry(id: "entry-2") == nil)
    }

    @Test("category decoder refuses an entry-owned row, leaving the buffer intact (D10)")
    func foreignDecodersRefuseEntryRow() async throws {
        let store = try makeStore()
        _ = try await store.createEntry(makeEntry())
        _ = try await store.deleteEntryUndoable(id: "entry-1", deletedAt: Date())

        let buffer = try #require(try await store.undoBufferMostRecent())
        #expect(try await store.categoryDeletionSnapshot(bufferID: buffer.id) == nil)
        #expect(try await store.undoCategoryDeletion(bufferID: buffer.id) == nil)
        // The entry row is untouched and still restorable by its owner.
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.undoEntryDeletion(bufferID: buffer.id)?.id == "entry-1")
    }
}
