// swiftlint:disable file_length
import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncController")
struct SyncControllerTests {

    // MARK: - Cycle ordering

    @Test("first sync pulls categories before draining the entry outbox")
    func firstSyncPullsBeforeDrain() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Local"))

        controller.activate()
        await waitForCycle(controller)

        let pullIndex = mock.calls.firstIndex { $0.method == "fetchCategories" }
        let pushIndex = mock.calls.firstIndex { $0.method == "createEntry" }
        #expect(pullIndex != nil)
        #expect(pushIndex != nil)
        if let pullIndex, let pushIndex {
            #expect(pullIndex < pushIndex)
        }
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("delta pull advances the per-resource cursor and reuses it")
    func deltaPullAdvancesCursor() async throws {
        let (store, mock, controller) = makeContext()
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        mock.entriesResult = [makeEntry(id: "e1", text: "Server", updatedAt: cursor)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.lastSyncedAt(resource: "entry") == cursor)

        mock.clearLog()
        await controller.syncNow()

        #expect(mock.fetchedModifiedSince.first == cursor)
    }

    // MARK: - LWW merge

    @Test("LWW merge applies a newer server entry")
    func lwwMergeAppliesNewerServerEntry() async throws {
        let (store, mock, controller) = makeContext()
        let local = makeEntry(
            id: "e1", text: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try await store.mergeEntry(local)
        let server = makeEntry(
            id: "e1", text: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        mock.entriesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityText == "Server")
    }

    @Test("LWW merge keeps a newer local entry")
    func lwwMergeKeepsNewerLocalEntry() async throws {
        let (store, mock, controller) = makeContext()
        let local = makeEntry(
            id: "e1", text: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.mergeEntry(local)
        let server = makeEntry(
            id: "e1", text: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        mock.entriesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityText == "Local")
    }

    @Test("equal texts with different ids stay independent records (no remap)")
    func nameCollisionKeepsBothRecords() async throws {
        let (store, mock, controller) = makeContext()
        try await store.mergeEntry(makeEntry(id: "local-gym", text: "Gym"))
        mock.entriesResult = [makeEntry(id: "server-gym", text: "Gym")]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "local-gym") != nil)
        #expect(try await store.entry(id: "server-gym") != nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    // MARK: - Outbox drain

    @Test("outbox drain is idempotent")
    func outboxDrainIsIdempotent() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "A"))
        try await store.createEntry(makeEntry(id: "e2", text: "B"))

        controller.activate()
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(Set(pushes.compactMap(\.id)) == Set(["e1", "e2"]))
        #expect(try await store.outboxRows().isEmpty)

        mock.clearLog()
        try await store.createEntry(makeEntry(id: "e3", text: "C"))
        try await store.createEntry(makeEntry(id: "e4", text: "D"))
        let rowsBefore = try await store.outboxRows()

        await controller.syncNow()

        let replayPushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(replayPushes.map(\.id) == rowsBefore.map(\.recordID))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("entry push carries the entries-only payload with ordered tags")
    func entryPushCarriesPayload() async throws {
        let (store, mock, controller) = makeContext()
        var pushed: TimeEntry?
        mock.createEntryHandler = { pushed = $0 }
        try await store.mergeCategory(Category(id: "c1", name: "Work", icon: "tag"))
        try await store.mergeCategory(Category(id: "c2", name: "Health", icon: "tag"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1", "c2"], notes: "Leg day"))

        controller.activate()
        await waitForCycle(controller)

        #expect(pushed?.activityText == "Gym")
        #expect(pushed?.categoryIDs == ["c1", "c2"])
        #expect(pushed?.notes == "Leg day")
    }

    @Test("conflict adopts the server version")
    func conflictAdoptsServerVersion() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Local"))
        let server = makeEntry(id: "e1", text: "Server", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        mock.createEntryHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchEntryHandler = { id in
            #expect(id == "e1")
            return server
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityText == "Server")
    }

    // MARK: - Prune-unknown-category (remove-activities-layer D7)

    @Test("a pulled entry's unknown category id is pruned with the remainder kept")
    func pullPrunesUnknownCategory() async throws {
        let (store, mock, controller) = makeContext()
        let local = Category(id: "c-keep", name: "Sport", icon: "figure.run")
        mock.categoriesResult = [local]
        mock.entriesResult = [
            makeEntry(id: "e1", text: "Gym", categoryIDs: ["c-keep", "c-unknown"])
        ]

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.categoryIDs == ["c-keep"])
        #expect(isIdle(controller.status))
    }

    @Test("a pulled entry whose category ids are all unknown survives untagged")
    func pullPrunesAllUnknownCategories() async throws {
        let (store, mock, controller) = makeContext()
        mock.categoriesResult = []
        mock.entriesResult = [
            makeEntry(id: "e1", text: "Gym", categoryIDs: ["c-ghost"])
        ]

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry != nil)
        #expect(entry?.categoryIDs.isEmpty == true)
        #expect(isIdle(controller.status))
    }

    @Test("conflict adoption prunes unknown categories too")
    func conflictAdoptionPrunesUnknownCategories() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Local"))
        let server = makeEntry(
            id: "e1", text: "Server", categoryIDs: ["c-unknown"],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        mock.categoriesResult = []

        mock.createEntryHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchEntryHandler = { _ in server }

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityText == "Server")
        #expect(entry?.categoryIDs.isEmpty == true)
    }

    // MARK: - In-progress drafts never sync (remove-activities-layer D3/D7)

    @Test("a running draft never enters the outbox and never syncs")
    func draftsNeverSync() async throws {
        let (store, mock, controller) = makeContext()
        try await store.saveTimerDraft(activityText: "Work", categoryIDs: ["c1"], startedAt: Date())

        controller.activate()
        await waitForCycle(controller)

        #expect(mock.calls.allSatisfy { $0.resource != "entry" || $0.method != "createEntry" })
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.timerDraft() != nil)
    }

    // MARK: - Category sync (category-management D6)

    @Test("starter categories with pending create rows survive snapshot reconciliation")
    func starterCategoriesSurviveFirstSync() async throws {
        let (store, mock, controller) = makeContext()
        // First-sync with starter outbox rows: the relay has NO categories yet.
        mock.categoriesResult = []
        let seeded = try await store.seedStarterCategoriesIfNeeded(
            names: ["Work", "Hobby", "Sport", "Education", "Relax", "Sleep", "Entertainment"]
        )
        guard case let .seeded(starterCategories) = seeded else {
            Issue.record("expected seeded")
            return
        }
        let starterIDs = Set(starterCategories.map(\.id))

        controller.activate()
        await waitForCycle(controller)

        let stored = try await store.categories()
        #expect(Set(stored.map(\.id)) == starterIDs)
        // Their create outbox rows were drained but the categories remain.
        #expect(stored.count == 7)
    }

    @Test("clean local categories absent from the relay snapshot are removed")
    func cleanLocalCategoriesRemovedBySnapshot() async throws {
        let (store, mock, controller) = makeContext()
        // A clean local category (no pending outbox work) that the relay no
        // longer has must be removed by the authoritative snapshot.
        try await store.mergeCategory(Category(id: "local-cat", name: "Old", icon: "tag"))
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "local-cat") == nil)
    }

    @Test("categories with pending outbox work are preserved even when absent from the snapshot")
    func dirtyLocalCategoriesPreserved() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "pending-cat", name: "Pending", icon: "tag"))
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        let stored = try await store.category(id: "pending-cat")
        #expect(stored != nil)
        #expect(stored?.name == "Pending")
        // The create row was drained, so the relay now owns it; a subsequent
        // pull snapshot includes it.
    }

    @Test("remote category deletion arrives and strips entry joins while entries survive")
    func remoteCategoryDeletionConverges() async throws {
        let (store, mock, controller) = makeContext()
        // A clean local category (no pending outbox row): merged, not created.
        try await store.mergeCategory(Category(id: "cat-1", name: "Sport", icon: "tag"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["cat-1"]))
        // The relay snapshot no longer contains cat-1 (deleted on another
        // device); there is no pending outbox work for the category.
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "cat-1") == nil)
        let entry = try await store.entry(id: "e1")
        #expect(entry != nil)
        #expect(entry?.categoryIDs.isEmpty == true)
        // No category delete was ever sent to the relay.
        #expect(!mock.calls.contains(Call("deleteCategory", "category", "cat-1")))
    }

    @Test("idempotent replay after a failed pull does not duplicate categories")
    func idempotentReplayNoDuplicates() async throws {
        let (store, mock, controller) = makeContext()
        let category = Category(id: "cat-1", name: "Work", icon: "briefcase")
        mock.categoriesResult = [category]

        controller.activate()
        await waitForCycle(controller)
        mock.clearLog()

        mock.categoriesResult = [category]
        await controller.syncNow()
        await waitForCycle(controller)

        #expect(try await store.categories().count == 1)
        let fetches = mock.calls.filter { $0.method == "fetchCategories" }
        #expect(fetches.count == 1)
    }

    @Test("pull adopts a newer server category on a normalized-name collision")
    func pullAdoptsNewerServerCategory() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        // Fresh-device seed (older) with its queued create row.
        try await store.createCategory(
            Category(
                id: "local-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: old
            )
        )
        mock.categoriesResult = [
            Category(
                id: "server-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: new
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        // Server identity adopted during pull — no push round-trip, no failure.
        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "local-sport") == nil)
        #expect(try await store.category(id: "server-sport")?.name == "Sport")
        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.allSatisfy { $0.method != "createCategory" })
    }

    @Test("pull keeps a newer local category and skips the server branch")
    func pullKeepsNewerLocalCategory() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.createCategory(
            Category(
                id: "local-sport", name: "Sport", icon: "figure.run",
                createdAt: new, updatedAt: new
            )
        )
        mock.categoriesResult = [
            Category(
                id: "server-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: old
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "local-sport")?.name == "Sport")
        #expect(try await store.category(id: "server-sport") == nil)
    }

    @Test("category_exists remaps entry joins, removes the losing identity, and clears its create row")
    func categoryExistsRemapsWithoutLosingEntries() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "local-id", name: "Sport", icon: "figure.run"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["local-id"]))
        let winner = Category(id: "server-id", name: "Sport", icon: "figure.run")

        mock.createCategoryHandler = { _ in
            throw APIError.server(
                code: "category_exists", message: "exists",
                details: ["id": "server-id", "name": "Sport"]
            )
        }
        mock.fetchCategoryHandler = { id in
            #expect(id == "server-id")
            return winner
        }

        controller.activate()
        await waitForCycle(controller)

        // The winning category is available locally.
        let storedWinner = try await store.category(id: "server-id")
        #expect(storedWinner?.name == "Sport")
        // The losing identity is gone, without a delete operation.
        #expect(try await store.category(id: "local-id") == nil)
        // The entry is intact and references the winner.
        let stored = try await store.entry(id: "e1")
        #expect(stored != nil)
        #expect(stored?.categoryIDs == ["server-id"])
        // The losing create row is cleared; no category delete row exists.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.resource != "category" })
        #expect(isIdle(controller.status))
    }

    @Test("category_exists with a failing winner fetch keeps the row and merges nothing")
    func categoryExistsFetchFailureKeepsRow() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "local-id", name: "Sport", icon: "figure.run"))

        mock.createCategoryHandler = { _ in
            throw APIError.server(
                code: "category_exists", message: "exists",
                details: ["id": "server-id", "name": "Sport"]
            )
        }
        mock.fetchCategoryHandler = { _ in throw APIError.offline }

        controller.activate()
        await waitForCycle(controller)

        // No stub merged: the losing identity keeps its real name.
        #expect(try await store.category(id: "server-id") == nil)
        #expect(try await store.category(id: "local-id")?.name == "Sport")
        // The outbox row stays queued for retry; the cycle surfaces the failure.
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "category" && $0.op == "create" && $0.recordID == "local-id" })
        guard case .error = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
    }

    // MARK: - Delete-wins for entries and categories (remove-activities-layer)

    @Test("first sync does not resurrect an entry with a pending delete")
    func firstSyncSkipsPendingEntryDelete() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        // A previously synced record, now locally deleted (committed path,
        // so the outbox holds only the delete row).
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        try await store.deleteEntry(id: "e1")
        // The relay still holds it: pull-first merges before the drain pushes
        // the DELETE.
        mock.entriesResult = [makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.entry(id: "e1") == nil)
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("first sync does not resurrect a category with a pending delete")
    func firstSyncSkipsPendingCategoryDelete() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeCategory(
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        )
        try await store.deleteCategory(id: "c1")
        mock.categoriesResult = [
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "c1") == nil)
        #expect(mock.calls.contains(Call("deleteCategory", "category", "c1")))
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered entry deletion")
    func pullSkipsBufferedEntryDeletion() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        let deleted = try await store.deleteEntryUndoable(id: "e1")
        guard case .deleted = deleted else {
            Issue.record("expected deleted, got \(deleted)")
            return
        }
        mock.entriesResult = [makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.entry(id: "e1") == nil)
        // Still undoable: the buffer row survived the sync.
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered category deletion")
    func pullSkipsBufferedCategoryDeletion() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeCategory(
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        )
        let deleted = try await store.deleteCategoryUndoable(id: "c1")
        guard case .deleted = deleted else {
            Issue.record("expected deleted, got \(deleted)")
            return
        }
        mock.categoriesResult = [
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "c1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(isIdle(controller.status))
    }

    @Test("update conflict does not resurrect a locally deleted entry")
    func conflictAdoptSkipsPendingDelete() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateEntry(makeEntry(id: "e1", text: "Gym v2", createdAt: t0, updatedAt: t1))
        try await store.deleteEntry(id: "e1")
        mock.updateEntryHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchEntryHandler = { _ in
            makeEntry(id: "e1", text: "Server", createdAt: t0, updatedAt: t2)
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.entry(id: "e1") == nil)
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    // MARK: - Deletion tombstones (entries and categories only)

    @Test("entry tombstone converges with joins cascade, no outbox, and cursor advance")
    func entryTombstoneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeCategory(Category(
            id: "cat-1", name: "Work", icon: "briefcase", createdAt: old, updatedAt: old
        ))
        try await store.mergeEntry(
            makeEntry(id: "e1", text: "Gym", categoryIDs: ["cat-1"], createdAt: old, updatedAt: old)
        )
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
        // First sync: no cursor yet, so the fetch ran without `deleted_since`.
        #expect(mock.fetchedDeletionsSince.first! == nil)
    }

    @Test("category tombstone removes joins and the row while entries survive untagged")
    func categoryTombstoneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeCategory(Category(
            id: "cat-1", name: "Work", icon: "briefcase", createdAt: old, updatedAt: old
        ))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["cat-1"]))
        mock.deletionsResult = [Deletion(resource: "category", recordID: "cat-1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "cat-1") == nil)
        let stored = try await store.entry(id: "e1")
        #expect(stored?.categoryIDs.isEmpty == true)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("an unknown-resource tombstone is ignored but still advances the cursor")
    func unknownResourceTombstoneIsIgnored() async throws {
        let (store, mock, controller) = makeContext()
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    @Test("stale tombstone keeps a clean local row newer than the deletion (R1)")
    func staleTombstoneKeepsCleanNewerRow() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        let recreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: recreatedAt))
        // No pending create/update rows: a recreation via the pull-merge path
        // is clean, and its updated_at is newer than the stale tombstone.
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "e1")?.activityText == "Gym")
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("tombstones drop a stale pending update before the drain, so the 404-throwing update mock is never called")
    func tombstonesDropStalePendingUpdatePreDrain() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        _ = try await store.updateEntry(makeEntry(
            id: "e1", text: "Gym v2", createdAt: old,
            updatedAt: Date(timeIntervalSince1970: 1_620_000_000)
        ))
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]
        mock.updateEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // The tombstone step removed the row and its pending update row
        // before the drain ran — no update was ever pushed, and the cycle
        // stayed idle (a push would have thrown).
        #expect(mock.calls.allSatisfy { $0.method != "updateEntry" })
        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    @Test("empty deletions list keeps the cursor nil")
    func emptyDeletionsKeepCursor() async throws {
        let (store, mock, controller) = makeContext()
        mock.deletionsResult = []

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.lastSyncedAt(resource: "deletions") == nil)
        #expect(mock.calls.contains(Call("fetchDeletions", "deletion")))
    }

    @Test("tombstone for an unknown id is a no-op that still advances the cursor")
    func unknownIDTombstoneIsNoOp() async throws {
        let (store, mock, controller) = makeContext()
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "unknown", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "unknown") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    @Test("deletions cursor advances to the max deleted_at across a batch")
    func deletionsCursorAdvancesToMax() async throws {
        let (store, mock, controller) = makeContext()
        let earlier = Date(timeIntervalSince1970: 1_640_000_000)
        let later = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: earlier, updatedAt: earlier))
        try await store.mergeEntry(makeEntry(id: "e2", text: "Run", createdAt: earlier, updatedAt: earlier))
        mock.deletionsResult = [
            Deletion(resource: "entry", recordID: "e1", deletedAt: earlier),
            Deletion(resource: "entry", recordID: "e2", deletedAt: later),
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.entry(id: "e2") == nil)
        #expect(try await store.lastSyncedAt(resource: "deletions") == later)
    }

    @Test("second sync sends the deletions cursor")
    func secondSyncSendsDeletionsCursor() async throws {
        let (store, mock, controller) = makeContext()
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: deletedAt, updatedAt: deletedAt))
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        mock.clearLog()
        await controller.syncNow()

        #expect(mock.fetchedDeletionsSince.first == deletedAt)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    @Test("pending DELETE row survives tombstone application (converges via 404-as-success)")
    func tombstoneKeepsPendingDeleteRow() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        try await store.deleteEntry(id: "e1")
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        // The locally queued DELETE drained normally; the tombstone found
        // nothing to remove and dropped nothing but stale create/update rows.
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    // MARK: - Push-404 resurrection (entries and categories only)

    @Test("stale entry update re-posts as create")
    func entryUpdateNotFoundRepostsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t1))
        mock.updateEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }
        var createdIDs: [String] = []
        mock.createEntryHandler = { createdIDs.append($0.id) }

        controller.activate()
        await waitForCycle(controller)

        #expect(createdIDs == ["e1"])
        #expect(try await store.entry(id: "e1") != nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("stale category update re-posts the full local row as create")
    func categoryUpdateNotFoundRepostsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeCategory(
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: t0, updatedAt: t0)
        )
        _ = try await store.updateCategory(
            Category(id: "c1", name: "Sport", icon: "tag", createdAt: t0, updatedAt: t1)
        )
        mock.updateCategoryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }
        var createdIDs: [String] = []
        mock.createCategoryHandler = { createdIDs.append($0.id) }

        controller.activate()
        await waitForCycle(controller)

        #expect(createdIDs == ["c1"])
        #expect(try await store.category(id: "c1")?.icon == "tag")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("an update row for a locally missing entry clears without pushing")
    func locallyMissingUpdateClears() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        // A create whose push will be superseded, plus a stacked update for
        // the same record that no longer exists locally.
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateEntry(makeEntry(id: "e1", text: "Gym v2", createdAt: t0, updatedAt: t1))
        try await store.deleteEntry(id: "e1") // commit the delete: removes the local row
        // The tombstone drops the create row; the update row would 404 forever.
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: Date())]
        var updateCalls = 0
        mock.updateEntryHandler = { _ in
            updateCalls += 1
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(updateCalls == 0)
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("pre-tombstone relay does not fail the cycle")
    func fetchDeletionsNotFoundSkipsTombstones() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.fetchDeletionsHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // Drain and pull ran normally around the skipped tombstone step.
        #expect(mock.calls.contains(Call("createEntry", "entry", "e1")))
        #expect(mock.calls.contains(Call("fetchEntries", "entry", nil)))
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == nil)
        #expect(isIdle(controller.status))
    }

    @Test("failed cycle exposes its message through status")
    func failedCycleExposesMessage() async {
        let (store, mock, controller) = makeContext()
        try? await store.createCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))
        mock.createCategoryHandler = { _ in
            throw APIError.server(code: "internal_error", message: "boom", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(controller.status == .error("server(internal_error): boom"))
    }

    @Test("not_found on delete is treated as success")
    func notFoundOnDeleteIsSuccess() async throws {
        let (store, mock, controller) = makeContext()
        try await store.deleteEntry(id: "e1")

        mock.deleteEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(isIdle(controller.status))
    }

    @Test("offline activation errors without network calls")
    func offlineActivationErrorsWithoutNetworkCalls() async throws {
        let (_, mock, controller) = makeContext(connected: false)
        controller.activate()
        await waitForCycle(controller)

        #expect(mock.calls.isEmpty)
        #expect(controller.status == .error("offline"))
    }

    @Test("deactivate stops sync and syncNow is a no-op")
    func deactivateStopsSync() async throws {
        let (_, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        controller.deactivate()
        #expect(controller.status == .inactive)

        mock.clearLog()
        await controller.syncNow()
        #expect(mock.calls.isEmpty)
    }

    @Test("trigger is single-flight")
    func triggerIsSingleFlight() async throws {
        let (_, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        mock.clearLog()
        controller.trigger()
        controller.trigger()
        await waitUntil { mock.calls.count == 3 }

        let fetches = mock.calls.filter { $0.method == "fetchEntries" }
        #expect(fetches.count == 1)
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        text: String,
        categoryIDs: [String] = [],
        notes: String = "",
        startedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            source: "manual",
            categoryIDs: categoryIDs,
            notes: notes,
            createdAt: createdAt ?? startedAt,
            updatedAt: updatedAt ?? startedAt
        )
    }

    private func makeContext(
        connected: Bool = true
    ) -> (store: LocalStore, mock: MockCatalogRepository, controller: SyncController) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        let connectivity = MockConnectivity(connected: connected)
        let controller = SyncController(
            store: store, remote: mock, connectivity: connectivity
        )
        return (store, mock, controller)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }

    private func waitForCycle(_ controller: SyncController) async {
        await waitUntil {
            if case .syncing = controller.status { return false }
            return true
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func isIdle(_ status: SyncController.SyncStatus) -> Bool {
        if case .idle = status { return true }
        return false
    }
}

private typealias Call = MockCatalogRepository.Call
