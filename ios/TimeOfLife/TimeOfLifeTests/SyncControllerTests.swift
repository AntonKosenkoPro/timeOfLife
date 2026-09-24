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

    @Test("pull does not resurrect a buffered entry deletion (the buffered push commits it)")
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

        // The pull skipped the relay copy (no resurrection), then the
        // buffered push committed the deletion: DELETE went out and the
        // buffer cleared — undo ends at push success.
        #expect(try await store.entry(id: "e1") == nil)
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(try await store.undoBufferMostRecent() == nil)
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered category deletion (the buffered push commits it)")
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
        #expect(mock.calls.contains(Call("deleteCategory", "category", "c1")))
        #expect(try await store.undoBufferMostRecent() == nil)
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

    // MARK: - Buffered deletions push before the drain (push-then-commit)

    @Test("buffered entry deletion pushes DELETE on the next cycle and clears the buffer")
    func bufferedEntryDeletionPushes() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        let outcome = try await store.deleteEntryUndoable(id: "e1")
        guard case .deleted = outcome else {
            Issue.record("expected the entry to be buffered for undo")
            return
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.bufferedDeletions().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("buffered category deletion pushes DELETE on the next cycle and clears the buffer")
    func bufferedCategoryDeletionPushes() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeCategory(Category(
            id: "cat-1", name: "Work", icon: "briefcase", createdAt: old, updatedAt: old
        ))
        _ = try await store.deleteCategoryUndoable(id: "cat-1")

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(mock.calls.contains(Call("deleteCategory", "category", "cat-1")))
        #expect(try await store.category(id: "cat-1") == nil)
        #expect(try await store.bufferedDeletions().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("404 on a buffered push is success: the buffer clears and the cycle stays idle")
    func bufferedPush404ClearsBuffer() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        _ = try await store.deleteEntryUndoable(id: "e1")
        mock.deleteEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.bufferedDeletions().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("failed buffered push keeps the row buffered and undoable, and fails the cycle loudly")
    func bufferedPushFailureKeepsRowUndoable() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        _ = try await store.deleteEntryUndoable(id: "e1")
        mock.deleteEntryHandler = { _ in
            throw APIError.server(code: "internal", message: "boom", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // Loud failure, nothing committed — and the deletion is still
        // restorable afterwards (the in-flight flag was cleared on error).
        if case .error = controller.status {} else {
            Issue.record("expected the cycle to fail loudly")
        }
        #expect(try await store.bufferedDeletions().count == 1)
        let recent = try await store.undoBufferMostRecent()
        let restored = try await store.undoEntryDeletion(bufferID: recent!.id)
        #expect(restored?.id == "e1")
        #expect(try await store.entry(id: "e1")?.activityText == "Gym")
    }

    @Test("undo refused while a buffered push is in flight, allowed again after")
    func undoRefusedDuringBufferedPush() async throws {
        let (store, _, _) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        _ = try await store.deleteEntryUndoable(id: "e1")
        let recent = try await store.undoBufferMostRecent()

        await store.setUndoPushInFlight(true)
        await #expect(throws: UndoError.pushInFlight) {
            try await store.undoEntryDeletion(bufferID: recent!.id)
        }
        await store.setUndoPushInFlight(false)
        let restored = try await store.undoEntryDeletion(bufferID: recent!.id)
        #expect(restored?.id == "e1")
    }

    @Test("buffered push runs before the drain: a stale queued update for the same id is dropped, never pushed")
    func bufferedPushRunsBeforeDrain() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: old, updatedAt: old))
        // A stale queued update…
        _ = try await store.updateEntry(makeEntry(
            id: "e1", text: "Gym v2", createdAt: old,
            updatedAt: Date(timeIntervalSince1970: 1_620_000_000)
        ))
        // …then the user deletes the entry (buffered, no outbox row).
        _ = try await store.deleteEntryUndoable(id: "e1")
        mock.updateEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(mock.calls.allSatisfy { $0.method != "updateEntry" })
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.bufferedDeletions().isEmpty)
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

    @Test("bare http_404 on deletions skips tombstones like a pre-tombstone relay")
    func fetchDeletionsHttp404SkipsTombstones() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        // An unregistered /deletions route (or a proxy 404 page) carries no
        // uniform envelope, so the client sees `http_404`, not `not_found`.
        mock.fetchDeletionsHandler = { _ in
            throw APIError.server(code: "http_404", message: "Not Found", details: [:])
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

    @Test("bare http_404 on delete is treated as success")
    func http404OnDeleteIsSuccess() async throws {
        let (store, mock, controller) = makeContext()
        try await store.deleteEntry(id: "e1")

        mock.deleteEntryHandler = { _ in
            throw APIError.server(code: "http_404", message: "Not Found", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e1")))
        #expect(isIdle(controller.status))
    }

    @Test("stale entry update with a bare http_404 re-posts as create")
    func entryUpdateHttp404RepostsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateEntry(makeEntry(id: "e1", text: "Gym", createdAt: t0, updatedAt: t1))
        mock.updateEntryHandler = { _ in
            throw APIError.server(code: "http_404", message: "Not Found", details: [:])
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

    // MARK: - Join instead of fork (history-pull-to-sync)

    @Test("concurrent syncNow calls join a single cycle")
    func syncNowJoinsInFlightCycle() async throws {
        let (store, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        // A slow push keeps the first cycle in flight while the second
        // syncNow arrives (pull joining a Profile-started cycle, or two
        // pulls racing).
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        mock.clearLog()

        let first = Task { await controller.syncNow() }
        await waitUntil { controller.status == .syncing }
        await controller.syncNow()
        await first.value
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(pushes.count == 1)
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("syncNow joins a trigger-started cycle")
    func syncNowJoinsTriggerCycle() async throws {
        let (store, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        mock.clearLog()

        controller.trigger()
        await waitUntil { controller.status == .syncing }
        await controller.syncNow()
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(pushes.count == 1)
        #expect(isIdle(controller.status))
    }

    @Test("trigger during a syncNow cycle does not fork")
    func triggerDuringSyncNowDoesNotFork() async throws {
        let (store, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        mock.clearLog()

        let syncing = Task { await controller.syncNow() }
        await waitUntil { controller.status == .syncing }
        controller.trigger()
        controller.trigger()
        await syncing.value
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createEntry" }
        #expect(pushes.count == 1)
        #expect(isIdle(controller.status))
    }

    @Test("sequential syncNow calls run separate cycles")
    func sequentialSyncNowRunsSeparateCycles() async throws {
        let (_, mock, controller) = makeContext()
        controller.activate()
        await waitForCycle(controller)

        mock.clearLog()
        await controller.syncNow()
        await controller.syncNow()

        // The boundary "race" (cycle already over at check time) is a fresh
        // cheap cycle, not a join: one fetchEntries per call.
        let fetches = mock.calls.filter { $0.method == "fetchEntries" }
        #expect(fetches.count == 2)
        #expect(isIdle(controller.status))
    }

    // MARK: - Category-before-entry drain (fix-entry-category-sync)

    @Test("drain pushes categories before entries even when the entry was queued first")
    func drainPushesCategoriesBeforeEntries() async throws {
        let (store, mock, controller) = makeContext()
        // Entry queued first (no categories so it can exist before c1), then
        // the category. Global created_at order would push the entry first;
        // dependency ordering must push the category first.
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        try await store.createCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))

        controller.activate()
        await waitForCycle(controller)

        let categoryIndex = mock.calls.firstIndex { $0.method == "createCategory" }
        let entryIndex = mock.calls.firstIndex { $0.method == "createEntry" }
        #expect(categoryIndex != nil)
        #expect(entryIndex != nil)
        if let categoryIndex, let entryIndex {
            #expect(categoryIndex < entryIndex)
        }
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("entry push creates a relay-unknown category first and pushes the full set")
    func entryPushValidationHealsByPruning() async throws {
        let (store, mock, controller) = makeContext()
        mock.categoriesResult = [Category(id: "c-keep", name: "Sport", icon: "figure.run")]

        controller.activate()
        await waitForCycle(controller)

        // Clean local rows (no outbox): the relay knows c-keep but not c-new,
        // so only the drain's ensure step can create c-new before pushing.
        try await store.mergeCategory(Category(id: "c-keep", name: "Sport", icon: "figure.run"))
        try await store.mergeCategory(Category(id: "c-new", name: "Music", icon: "music.note"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c-keep", "c-new"]))
        var pushed: [TimeEntry] = []
        var createdCategoryIDs: [String] = []
        mock.createCategoryHandler = { category in
            createdCategoryIDs.append(category.id)
            // Simulate the relay now owning the created category.
            if !mock.categoriesResult.contains(where: { $0.id == category.id }) {
                mock.categoriesResult.append(category)
            }
        }
        mock.createEntryHandler = { entry in
            pushed.append(entry)
            let known = Set(mock.categoriesResult.map(\.id))
            if !Set(entry.categoryIDs).isSubset(of: known) {
                throw APIError.server(
                    code: "validation_error", message: "Validation failed",
                    details: ["category_ids": "One or more categories do not exist"]
                )
            }
        }

        await controller.syncNow()

        #expect(createdCategoryIDs == ["c-new"])
        #expect(pushed.count == 1)
        #expect(pushed.first?.categoryIDs == ["c-keep", "c-new"])
        #expect(try await store.entry(id: "e1")?.categoryIDs == ["c-keep", "c-new"])
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("entry push with a row-less dangling category id still prunes as a last resort")
    func entryPushValidationHealsDanglingID() async throws {
        let (store, mock, controller) = makeContext()
        try await store.mergeCategory(Category(id: "c-keep", name: "Sport", icon: "figure.run"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c-keep"]))
        // Rewrite the queued payload to reference a dangling id with no local
        // row: ensure must skip it, the push 422s, and the last-resort heal
        // prunes it.
        let dangling = makeEntry(id: "e1", text: "Gym", categoryIDs: ["c-keep", "c-ghost"])
        try await store.rewriteOutboxPayload(resource: "entry", recordID: "e1", payload: dangling)
        mock.categoriesResult = [Category(id: "c-keep", name: "Sport", icon: "figure.run")]
        var pushed: [TimeEntry] = []
        mock.createEntryHandler = { entry in
            pushed.append(entry)
            if entry.categoryIDs.contains("c-ghost") {
                throw APIError.server(
                    code: "validation_error", message: "Validation failed",
                    details: ["category_ids": "One or more categories do not exist"]
                )
            }
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(pushed.count == 2)
        #expect(pushed.last?.categoryIDs == ["c-keep"])
        #expect(mock.calls.allSatisfy { $0.method != "createCategory" })
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("entry push 422 with nothing to prune still fails loudly")
    func entryPushValidationWithoutPruneFails() async throws {
        let (store, mock, controller) = makeContext()
        try await store.mergeCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1"]))
        mock.categoriesResult = [Category(id: "c1", name: "Sport", icon: "figure.run")]
        mock.createEntryHandler = { _ in
            throw APIError.server(
                code: "validation_error", message: "Validation failed",
                details: ["category_ids": "One or more categories do not exist"]
            )
        }

        controller.activate()
        await waitForCycle(controller)

        guard case .error = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
        #expect(!(try await store.outboxRows()).isEmpty)
    }

    @Test("pull remaps a relay-known id to a newer same-name local rival and adopts snapshot-only ids")
    func pullAdoptsOrRemapsRelayKnownCategories() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        // The local "Sport" rival is newer than the relay row, so the pull
        // keeps it; it stays dirty (pending create) so snapshot
        // reconciliation preserves it.
        try await store.createCategory(Category(
            id: "local-sport", name: "Sport", icon: "figure.run",
            createdAt: new, updatedAt: new
        ))
        mock.categoriesResult = [
            Category(
                id: "server-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: old
            ),
            Category(
                id: "server-only", name: "Music", icon: "music.note",
                createdAt: old, updatedAt: old
            ),
        ]
        mock.entriesResult = [
            makeEntry(
                id: "e1", text: "Gym", categoryIDs: ["server-sport", "server-only"],
                createdAt: old, updatedAt: old
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        // server-sport remapped to the local rival, server-only adopted: the
        // entry keeps a category for both, with no outbox row enqueued for
        // the remap itself.
        #expect(try await store.entry(id: "e1")?.categoryIDs == ["local-sport", "server-only"])
        #expect(try await store.category(id: "local-sport")?.name == "Sport")
        #expect(try await store.category(id: "server-only")?.name == "Music")
        #expect(try await store.category(id: "server-sport") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a tie pull with a local category superset enqueues a healing update that drains with the full set")
    func tiePullHealsCategoryFork() async throws {
        let (store, mock, controller) = makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeCategory(Category(
            id: "c1", name: "Sport", icon: "figure.run", createdAt: stamp, updatedAt: stamp
        ))
        try await store.mergeCategory(Category(
            id: "c2", name: "Music", icon: "music.note", createdAt: stamp, updatedAt: stamp
        ))
        try await store.mergeEntry(makeEntry(
            id: "e1", text: "Gym", categoryIDs: ["c1", "c2"], createdAt: stamp, updatedAt: stamp
        ))
        // The relay silently pruned c2 while storing the client timestamp
        // verbatim: the tie keeps local and must heal.
        mock.categoriesResult = [
            Category(
                id: "c1", name: "Sport", icon: "figure.run", createdAt: stamp, updatedAt: stamp
            ),
            Category(
                id: "c2", name: "Music", icon: "music.note", createdAt: stamp, updatedAt: stamp
            ),
        ]
        mock.entriesResult = [
            makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1"], createdAt: stamp, updatedAt: stamp)
        ]
        var updated: [TimeEntry] = []
        mock.updateEntryHandler = { updated.append($0) }

        controller.activate()
        await waitForCycle(controller)

        #expect(updated.count == 1)
        #expect(updated.first?.categoryIDs == ["c1", "c2"])
        #expect(updated.first.map { $0.updatedAt > stamp } == true)
        #expect(try await store.entry(id: "e1")?.categoryIDs == ["c1", "c2"])
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a tie pull with a server category superset adopts the joins locally without enqueueing")
    func tiePullAdoptsServerCategorySuperset() async throws {
        let (store, mock, controller) = makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeCategory(Category(
            id: "c1", name: "Sport", icon: "figure.run", createdAt: stamp, updatedAt: stamp
        ))
        try await store.mergeCategory(Category(
            id: "c2", name: "Music", icon: "music.note", createdAt: stamp, updatedAt: stamp
        ))
        // A pre-fix pull wiped the join; the entry's ms timestamp ties with
        // the relay's sub-ms one forever (whole-row LWW never adopts).
        try await store.mergeEntry(makeEntry(
            id: "e1", text: "Gym", categoryIDs: [], createdAt: stamp, updatedAt: stamp
        ))
        mock.categoriesResult = [
            Category(
                id: "c1", name: "Sport", icon: "figure.run", createdAt: stamp, updatedAt: stamp
            ),
            Category(
                id: "c2", name: "Music", icon: "music.note", createdAt: stamp, updatedAt: stamp
            ),
        ]
        mock.entriesResult = [
            makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1", "c2"], createdAt: stamp, updatedAt: stamp)
        ]

        controller.activate()
        await waitForCycle(controller)

        // Local-only adoption: joins restored, timestamp unchanged, no push.
        let entry = try await store.entry(id: "e1")
        #expect(entry?.categoryIDs == ["c1", "c2"])
        #expect(entry?.updatedAt == stamp)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("a server-older pull keeps local joins even when the server set supersets")
    func serverOlderPullDoesNotAdoptServerSuperset() async throws {
        let (store, mock, controller) = makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let older = stamp.addingTimeInterval(-10)
        try await store.mergeCategory(Category(
            id: "c1", name: "Sport", icon: "figure.run", createdAt: older, updatedAt: older
        ))
        try await store.mergeEntry(makeEntry(
            id: "e1", text: "Gym", categoryIDs: [], createdAt: older, updatedAt: stamp
        ))
        mock.categoriesResult = [
            Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: older, updatedAt: older)
        ]
        // A legitimate relay prune on another device: older server version
        // with the pruned (here empty→untagged) set. Server set is a strict
        // superset of the (empty) local set but the tie is absent: keep local.
        mock.entriesResult = [
            makeEntry(id: "e1", text: "Gym", categoryIDs: [], createdAt: older, updatedAt: older)
        ]

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.categoryIDs.isEmpty == true)
        #expect(entry?.updatedAt == stamp)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    // MARK: - Account switch (SiWA relogin)

    @Test("account switch preserves clean locals and pushes them to the new relay")
    func accountSwitchPreservesCleanLocals() async throws {
        let (store, mock, controller) = makeContext()
        // Previously-synced dataset for user-A: clean rows, no outbox.
        try await store.mergeCategory(Category(id: "cat-1", name: "Sport", icon: "tag"))
        try await store.mergeEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["cat-1"]))
        try await store.setSyncAccountId("user-A")
        let stale = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.setLastSyncedAt(resource: "entry", date: stale)
        // The new account's relay is empty (SiWA mints a separate identity).
        mock.categoriesResult = []
        mock.entriesResult = []
        mock.deletionsResult = []

        controller.activate(accountId: "user-B")
        await waitForCycle(controller)

        // Adopted under fresh ids: record ids are relay-global, so the old
        // account's ids are gone locally instead of being re-pushed.
        #expect(try await store.category(id: "cat-1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
        let cats = try await store.categories()
        #expect(cats.count == 1)
        let freshCat = try #require(cats.first)
        #expect(freshCat.id != "cat-1")
        #expect(freshCat.name == "Sport")
        let entries = try await store.entries()
        #expect(entries.count == 1)
        let freshEntry = try #require(entries.first)
        #expect(freshEntry.id != "e1")
        #expect(freshEntry.activityText == "Gym")
        #expect(freshEntry.categoryIDs == [freshCat.id])
        // … and the drain pushed the fresh rows to the new relay.
        let pushedCats = mock.calls.filter { $0.method == "createCategory" }.compactMap(\.id)
        #expect(pushedCats.first == freshCat.id)
        #expect(Set(pushedCats) == [freshCat.id])
        let pushedEntries = mock.calls.filter { $0.method == "createEntry" }.compactMap(\.id)
        #expect(Set(pushedEntries) == [freshEntry.id])
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.syncAccountId() == "user-B")
        // Cursors were reset, so the pull was a full pull (nil cursor).
        #expect(mock.fetchedModifiedSince.count == 1)
        #expect(mock.fetchedModifiedSince.first! == nil)
        #expect(isIdle(controller.status))
    }

    @Test("same account keeps snapshot reconciliation")
    func sameAccountKeepsReconciliation() async throws {
        let (store, mock, controller) = makeContext()
        try await store.mergeCategory(Category(id: "local-cat", name: "Old", icon: "tag"))
        try await store.setSyncAccountId("user-A")
        mock.categoriesResult = []

        controller.activate(accountId: "user-A")
        await waitForCycle(controller)

        #expect(try await store.category(id: "local-cat") == nil)
    }

    // MARK: - Cross-account id collision (fix-cross-account-id-collision)

    @Test("category_exists with an empty winner id never fetches and self-heals onto a fresh id")
    func categoryExistsEmptyWinnerSelfHeals() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "cat-1", name: "Sport", icon: "figure.run"))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["cat-1"]))
        var pushedCategoryIDs: [String] = []
        var pushedEntries: [TimeEntry] = []
        mock.createCategoryHandler = { category in
            pushedCategoryIDs.append(category.id)
            if category.id == "cat-1" {
                throw APIError.server(
                    code: "category_exists", message: "exists",
                    details: ["id": "", "name": "Sport"]
                )
            }
            if !mock.categoriesResult.contains(where: { $0.id == category.id }) {
                mock.categoriesResult.append(category)
            }
        }
        mock.createEntryHandler = { pushedEntries.append($0) }

        controller.activate()
        await waitForCycle(controller)

        // The empty winner never becomes a fetch: no GET with an empty id.
        #expect(mock.calls.allSatisfy { $0.method != "fetchCategory" })
        // The row healed onto a fresh id and landed; joins followed intact.
        #expect(pushedCategoryIDs.first == "cat-1")
        let freshID = try #require(pushedCategoryIDs.dropFirst().first)
        #expect(freshID != "cat-1")
        #expect(try await store.category(id: "cat-1") == nil)
        #expect(try await store.category(id: freshID)?.name == "Sport")
        #expect(try await store.entry(id: "e1")?.categoryIDs == [freshID])
        #expect(pushedEntries.first?.categoryIDs == [freshID])
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("category_exists with an empty winner id and a failing retry keeps the row queued with a collision diagnostic")
    func categoryExistsEmptyWinnerKeepsRowQueued() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "cat-1", name: "Sport", icon: "figure.run"))
        mock.createCategoryHandler = { _ in
            throw APIError.server(
                code: "category_exists", message: "exists",
                details: ["id": "", "name": "Sport"]
            )
        }

        controller.activate()
        await waitForCycle(controller)

        // No winner fetch was ever issued for the empty id (no mystery http_404).
        #expect(mock.calls.allSatisfy { $0.method != "fetchCategory" })
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "category" && $0.op == "create" })
        guard case .error(let message) = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
        #expect(message.contains("id_collision"))
        #expect(message.contains("category"))
    }

    @Test("category_exists with a missing winner id never fetches, keeps the row queued, and fails loudly")
    func categoryExistsMissingWinnerKeepsRowQueued() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(Category(id: "cat-1", name: "Sport", icon: "figure.run"))
        mock.createCategoryHandler = { _ in
            throw APIError.server(code: "category_exists", message: "exists", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(mock.calls.allSatisfy { $0.method != "fetchCategory" })
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "category" && $0.op == "create" })
        guard case .error(let message) = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
        #expect(message.contains("id_collision"))
    }

    @Test("account switch drops superseded updates but still drains pending deletes")
    func accountSwitchDropsStaleUpdatesButPreservesDeletes() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeCategory(
            Category(id: "cat-1", name: "Sport", icon: "tag", createdAt: old, updatedAt: old)
        )
        _ = try await store.updateCategory(
            Category(
                id: "cat-1", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: Date(timeIntervalSince1970: 1_650_000_000)
            )
        )
        try await store.mergeEntry(makeEntry(id: "e-gone", text: "Old"))
        try await store.deleteEntry(id: "e-gone")
        try await store.setSyncAccountId("user-A")
        mock.categoriesResult = []
        mock.entriesResult = []
        mock.deletionsResult = []

        controller.activate(accountId: "user-B")
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        // The stale update for the adopted-away id never pushed …
        #expect(mock.calls.allSatisfy { $0.method != "updateCategory" })
        // … the pending delete still drained (404-as-success converges it) …
        #expect(mock.calls.contains(Call("deleteEntry", "entry", "e-gone")))
        #expect(try await store.outboxRows().isEmpty)
        // … and the adopted category landed under a fresh id with latest state.
        #expect(try await store.category(id: "cat-1") == nil)
        let cats = try await store.categories()
        #expect(cats.count == 1)
        #expect(cats.first?.id != "cat-1")
        #expect(cats.first?.icon == "figure.run")
    }

    @Test("duplicate_import with a not_found disambiguation GET self-heals the entry onto a fresh id")
    func duplicateImportNotFoundSelfHeals() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(
            makeEntry(id: "e1", text: "Gym", categoryIDs: [], notes: "Leg day")
        )
        var pushed: [TimeEntry] = []
        mock.createEntryHandler = { entry in
            pushed.append(entry)
            if entry.id == "e1" {
                throw APIError.server(code: "duplicate_import", message: "duplicate", details: [:])
            }
        }
        mock.fetchEntryHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // Exactly one disambiguation GET for the pushed id — never per row.
        #expect(mock.calls.filter { $0.method == "fetchEntry" }.count == 1)
        #expect(pushed.count == 2)
        #expect(pushed.first?.id == "e1")
        let freshID = try #require(pushed.last?.id)
        #expect(freshID != "e1")
        let landed = try #require(try await store.entry(id: freshID))
        #expect(landed.activityText == "Gym")
        #expect(landed.notes == "Leg day")
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("duplicate_import with matching import keys still clears silently")
    func duplicateImportMatchingKeysClearsSilently() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        var pushes = 0
        mock.createEntryHandler = { _ in
            pushes += 1
            throw APIError.server(code: "duplicate_import", message: "duplicate", details: [:])
        }
        // The relay holds the same import keys (manual/nil) under this id.
        mock.fetchEntryHandler = { _ in makeEntry(id: "e1", text: "Gym") }

        controller.activate()
        await waitForCycle(controller)

        #expect(pushes == 1)
        #expect(mock.calls.filter { $0.method == "fetchEntry" }.count == 1)
        #expect(try await store.entry(id: "e1")?.activityText == "Gym")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
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
