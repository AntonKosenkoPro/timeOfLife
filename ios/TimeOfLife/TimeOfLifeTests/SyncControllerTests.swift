// swiftlint:disable file_length
import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("SyncController")
struct SyncControllerTests {

    @Test("first sync pulls before draining outbox")
    func firstSyncPullsBeforeDrain() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Local"))

        controller.activate()
        await waitForCycle(controller)

        let pullIndex = mock.calls.firstIndex { $0.method == "fetchActivities" }
        let pushIndex = mock.calls.firstIndex { $0.method == "createActivity" }
        #expect(pullIndex != nil)
        #expect(pushIndex != nil)
        if let pullIndex, let pushIndex {
            #expect(pullIndex < pushIndex)
        }
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("delta pull advances cursor and reuses it")
    func deltaPullAdvancesCursor() async throws {
        let (store, mock, controller) = makeContext()
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        mock.activitiesResult = [Activity(id: "a1", name: "Server", updatedAt: cursor)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.lastSyncedAt(resource: "activity") == cursor)

        mock.clearLog()
        await controller.syncNow()

        let activityFetch = mock.calls.firstIndex { $0.method == "fetchActivities" }
        #expect(activityFetch != nil)
        #expect(mock.fetchedModifiedSince.first == cursor)
    }

    @Test("LWW merge applies newer server activity")
    func lwwMergeAppliesNewerServerActivity() async throws {
        let (store, mock, controller) = makeContext()
        let local = Activity(
            id: "a1", name: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try await store.createActivity(local)
        let server = Activity(
            id: "a1", name: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        mock.activitiesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Server")
    }

    @Test("LWW merge keeps newer local activity")
    func lwwMergeKeepsNewerLocalActivity() async throws {
        let (store, mock, controller) = makeContext()
        let local = Activity(
            id: "a1", name: "Local",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.createActivity(local)
        let server = Activity(
            id: "a1", name: "Server",
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        mock.activitiesResult = [server]

        controller.activate()
        await waitForCycle(controller)

        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Local")
    }

    @Test("outbox drain is idempotent")
    func outboxDrainIsIdempotent() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "A"))
        try await store.createActivity(Activity(id: "a2", name: "B"))

        controller.activate()
        await waitForCycle(controller)

        let pushes = mock.calls.filter { $0.method == "createActivity" }
        #expect(Set(pushes.compactMap(\.id)) == Set(["a1", "a2"]))
        #expect(try await store.outboxRows().isEmpty)

        mock.clearLog()
        try await store.createActivity(Activity(id: "b1", name: "C"))
        try await store.createActivity(Activity(id: "b2", name: "D"))
        let rowsBefore = try await store.outboxRows()

        await controller.syncNow()

        let replayPushes = mock.calls.filter { $0.method == "createActivity" }
        #expect(replayPushes.map(\.id) == rowsBefore.map(\.recordID))
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("conflict adopts server version")
    func conflictAdoptsServerVersion() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Local"))
        let server = Activity(id: "a1", name: "Server", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        mock.createActivityHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchActivityHandler = { id in
            #expect(id == "a1")
            return server
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        let activity = try await store.activity(id: "a1")
        #expect(activity?.name == "Server")
    }

    @Test("activity_exists remaps references to winning id")
    func activityExistsRemapsReferences() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: Date())
        )

        mock.createActivityHandler = { _ in
            throw APIError.server(
                code: "activity_exists", message: "exists",
                details: ["id": "server-id", "name": "Gym"]
            )
        }
        mock.fetchActivityHandler = { _ in Activity(id: "server-id", name: "Gym") }

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityID == "server-id")

        let remaining = try await store.outboxRows()
        #expect(remaining.allSatisfy { $0.resource == "entry" && $0.op == "update" })
        #expect(isIdle(controller.status))
    }

    @Test("activity_exists with failing winner fetch keeps the row and merges nothing")
    func activityExistsFetchFailureKeepsRow() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: Date())
        )

        mock.createActivityHandler = { _ in
            throw APIError.server(
                code: "activity_exists", message: "exists",
                details: ["id": "server-id", "name": "Gym"]
            )
        }
        mock.fetchActivityHandler = { _ in throw APIError.offline }

        controller.activate()
        await waitForCycle(controller)

        // No stub merged: no UUID-named record, the local keeps its real name,
        // and entries still reference it.
        #expect(try await store.activity(id: "server-id") == nil)
        #expect(try await store.activity(id: "a1")?.name == "Gym")
        #expect(try await store.entry(id: "e1")?.activityID == "a1")
        // The outbox row stays queued for retry; the cycle surfaces the failure.
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "activity" && $0.op == "create" && $0.recordID == "a1" })
        guard case .error = controller.status else {
            Issue.record("expected error status, got \(controller.status)")
            return
        }
    }

    @Test("category_exists with failing winner fetch keeps the row and merges nothing")
    func categoryExistsFetchFailureKeepsRow() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(TimeOfLife.Category(id: "local-id", name: "Sport", icon: "figure.run"))

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

    @Test("pull adopts newer server category on seed name collision")
    func pullAdoptsNewerServerCategory() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        // Fresh-device seed (older) with its queued create row.
        try await store.createCategory(
            TimeOfLife.Category(
                id: "local-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: old
            )
        )
        mock.categoriesResult = [
            TimeOfLife.Category(
                id: "server-sport", name: "Sport", icon: "figure.run",
                createdAt: old, updatedAt: new
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        // Server identity adopted during pull — no push round-trip, no failure
        // (previously SQLite 19 on index_categories_on_lower_name).
        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "local-sport") == nil)
        #expect(try await store.category(id: "server-sport")?.name == "Sport")
        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.allSatisfy { $0.method != "createCategory" })
    }

    @Test("pull keeps newer local seed, translates tags, and push-409 heals identity")
    func pullKeepsNewerSeedAndPushHeals() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.createCategory(
            TimeOfLife.Category(
                id: "local-sport", name: "Sport", icon: "figure.run",
                createdAt: new, updatedAt: new
            )
        )
        let serverCategory = TimeOfLife.Category(
            id: "server-sport", name: "Sport", icon: "figure.run",
            createdAt: old, updatedAt: old
        )
        mock.categoriesResult = [serverCategory]
        mock.activitiesResult = [
            Activity(
                id: "server-gym", name: "Gym", categoryIDs: ["server-sport"],
                createdAt: old, updatedAt: old
            )
        ]
        mock.entriesResult = [
            TimeEntry(
                id: "e1", activityID: "server-gym", activityName: "Gym",
                startedAt: old, createdAt: old, updatedAt: old
            )
        ]
        mock.createCategoryHandler = { _ in
            throw APIError.server(
                code: "category_exists", message: "exists",
                details: ["id": "server-sport", "name": "Sport"]
            )
        }
        mock.fetchCategoryHandler = { _ in serverCategory }

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "local-sport") == nil)
        #expect(try await store.category(id: "server-sport")?.name == "Sport")
        // The server activity merged with the translated (local, then healed)
        // tag, and its entry followed.
        #expect(try await store.activity(id: "server-gym")?.categoryIDs == ["server-sport"])
        #expect(try await store.entry(id: "e1")?.activityID == "server-gym")
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("pull adopts newer server activity and moves entries")
    func pullAdoptsNewerServerActivity() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.createActivity(
            Activity(
                id: "local-gym", name: "Gym",
                createdAt: old, updatedAt: old
            )
        )
        try await store.createEntry(
            TimeEntry(
                id: "e1", activityID: "local-gym", activityName: "Gym",
                startedAt: old, createdAt: old, updatedAt: old
            )
        )
        mock.activitiesResult = [
            Activity(
                id: "server-gym", name: "Gym",
                createdAt: old, updatedAt: new
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "local-gym") == nil)
        #expect(try await store.activity(id: "server-gym")?.name == "Gym")
        #expect(try await store.entry(id: "e1")?.activityID == "server-gym")
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("pull keeps newer local activity and skips the server branch")
    func pullKeepsNewerLocalActivityBranch() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.createActivity(
            Activity(
                id: "local-gym", name: "Gym",
                createdAt: new, updatedAt: new
            )
        )
        mock.activitiesResult = [
            Activity(
                id: "server-gym", name: "Gym",
                createdAt: old, updatedAt: old
            )
        ]
        mock.entriesResult = [
            TimeEntry(
                id: "e1", activityID: "server-gym", activityName: "Gym",
                startedAt: old, createdAt: old, updatedAt: old
            )
        ]

        controller.activate()
        await waitForCycle(controller)

        // Kept local, skipped server + its dangling entry — and the cycle
        // completed instead of failing on the unique index or the entry FK.
        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "local-gym")?.name == "Gym")
        #expect(try await store.activity(id: "server-gym") == nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("failed cycle exposes its message through status")
    func failedCycleExposesMessage() async {
        let (store, mock, controller) = makeContext()
        try? await store.createCategory(TimeOfLife.Category(id: "c1", name: "Sport", icon: "figure.run"))
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
        try await store.deleteActivity(id: "a1")

        mock.deleteActivityHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.outboxRows().isEmpty)
        #expect(mock.calls.contains(Call("deleteActivity", "activity", "a1")))
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

        let fetches = mock.calls.filter { $0.method == "fetchActivities" }
        #expect(fetches.count == 1)
    }

    // MARK: - Category sync (category-management D6)

    @Test("first sync pulls Categories before Activities")
    func categoriesPulledBeforeActivities() async throws {
        let (store, mock, controller) = makeContext()
        mock.categoriesResult = [TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase")]
        mock.activitiesResult = [Activity(id: "a1", name: "Gym", categoryIDs: ["cat-1"])]

        controller.activate()
        await waitForCycle(controller)

        let categoriesFetch = mock.calls.firstIndex { $0.method == "fetchCategories" }
        let activitiesFetch = mock.calls.firstIndex { $0.method == "fetchActivities" }
        #expect(categoriesFetch != nil)
        #expect(activitiesFetch != nil)
        if let categoriesFetch, let activitiesFetch {
            #expect(categoriesFetch < activitiesFetch)
        }
        // The merged activity references a category that exists locally.
        let activity = try await store.activity(id: "a1")
        #expect(activity?.categoryIDs == ["cat-1"])
    }

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
        try await store.mergeCategory(TimeOfLife.Category(id: "local-cat", name: "Old", icon: "tag"))
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "local-cat") == nil)
    }

    @Test("categories with pending outbox work are preserved even when absent from the snapshot")
    func dirtyLocalCategoriesPreserved() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(TimeOfLife.Category(id: "pending-cat", name: "Pending", icon: "tag"))
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        let stored = try await store.category(id: "pending-cat")
        #expect(stored != nil)
        #expect(stored?.name == "Pending")
        // The create row was drained, so the relay now owns it; a subsequent
        // pull snapshot includes it.
    }

    @Test("remote category deletion arrives and removes associations while preserving activities")
    func remoteCategoryDeletionConverges() async throws {
        let (store, mock, controller) = makeContext()
        // A clean local category (no pending outbox row): merged, not created.
        try await store.mergeCategory(TimeOfLife.Category(id: "cat-1", name: "Sport", icon: "tag"))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["cat-1"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        // The relay snapshot no longer contains cat-1 (deleted on another
        // device); there is no pending outbox work for the category.
        mock.categoriesResult = []

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "cat-1") == nil)
        let stored = try await store.activity(id: activity.id)
        #expect(stored != nil)
        #expect(stored?.categoryIDs.isEmpty == true)
        // No category delete was ever sent to the relay.
        #expect(!mock.calls.contains(Call("deleteCategory", "category", "cat-1")))
    }

    @Test("idempotent replay after a failed pull does not duplicate categories")
    func idempotentReplayNoDuplicates() async throws {
        let (store, mock, controller) = makeContext()
        let category = TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase")
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

    @Test("category_exists remaps joins, rewrites payloads, removes the losing identity, and clears its create row")
    func categoryExistsRemapsWithoutLosingActivities() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createCategory(TimeOfLife.Category(id: "local-id", name: "Sport", icon: "figure.run"))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["local-id"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        let winner = TimeOfLife.Category(id: "server-id", name: "Sport", icon: "figure.run")

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
        // Capture the Activity pushed after the remap: its payload must carry
        // the winning category id (the pending payload was rewritten).
        var pushedActivity: Activity?
        mock.createActivityHandler = { activity in
            pushedActivity = activity
        }

        controller.activate()
        await waitForCycle(controller)

        // The winning category is available locally.
        let storedWinner = try await store.category(id: "server-id")
        #expect(storedWinner?.name == "Sport")
        // The losing identity is gone, without a delete operation.
        #expect(try await store.category(id: "local-id") == nil)
        // The activity is intact and references the winner.
        let stored = try await store.activity(id: activity.id)
        #expect(stored != nil)
        #expect(stored?.categoryIDs == ["server-id"])
        // The losing create row is cleared; no category delete row exists.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.resource != "category" })
        // The pushed Activity carried the remapped winner id.
        #expect(pushedActivity?.categoryIDs == ["server-id"])
    }

    // MARK: - Delete-wins on pull (delete resurrection)

    @Test("first sync does not resurrect an activity with a pending delete")
    func firstSyncSkipsPendingActivityDelete() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        // A previously synced record, now locally deleted (committed path,
        // so the outbox holds only the delete row).
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.deleteActivity(id: "a1")
        // The relay still holds it: pull-first merges before the drain pushes
        // the DELETE.
        mock.activitiesResult = [Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.activity(id: "a1") == nil)
        #expect(mock.calls.contains(Call("deleteActivity", "activity", "a1")))
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered activity deletion")
    func pullSkipsBufferedActivityDeletion() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        let deleted = try await store.deleteActivityUndoable(id: "a1")
        guard case .deleted = deleted else {
            Issue.record("expected deleted, got \(deleted)")
            return
        }
        mock.activitiesResult = [Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old)]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.activity(id: "a1") == nil)
        // Still undoable: the buffer row survived the sync.
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered category deletion")
    func pullSkipsBufferedCategoryDeletion() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeCategory(
            TimeOfLife.Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        )
        let deleted = try await store.deleteCategoryUndoable(id: "c1")
        guard case .deleted = deleted else {
            Issue.record("expected deleted, got \(deleted)")
            return
        }
        mock.categoriesResult = [
            TimeOfLife.Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: old, updatedAt: old)
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.category(id: "c1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(isIdle(controller.status))
    }

    @Test("pull does not resurrect a buffered entry deletion")
    func pullSkipsBufferedEntryDeletion() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.mergeEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        let deleted = try await store.deleteEntryUndoable(id: "e1")
        guard case .deleted = deleted else {
            Issue.record("expected deleted, got \(deleted)")
            return
        }
        mock.entriesResult = [
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(isIdle(controller.status))
    }

    @Test("update conflict does not resurrect a locally deleted activity")
    func conflictAdoptSkipsPendingDelete() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateActivity(Activity(id: "a1", name: "Gym v2", createdAt: t0, updatedAt: t1))
        try await store.deleteActivity(id: "a1")
        mock.updateActivityHandler = { _ in
            throw APIError.server(code: "conflict", message: "stale", details: [:])
        }
        mock.fetchActivityHandler = { _ in
            Activity(id: "a1", name: "Server", createdAt: t0, updatedAt: t2)
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(try await store.activity(id: "a1") == nil)
        #expect(mock.calls.contains(Call("deleteActivity", "activity", "a1")))
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    // MARK: - Deletion tombstones (cross-device-delete-propagation)

    @Test("activity tombstone converges with cascade, no outbox, and cursor advance")
    func activityTombstoneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeCategory(TimeOfLife.Category(
            id: "cat-1", name: "Work", icon: "briefcase", createdAt: old, updatedAt: old
        ))
        try await store.mergeActivity(Activity(
            id: "a1", name: "Gym", categoryIDs: ["cat-1"], createdAt: old, updatedAt: old
        ))
        try await store.mergeEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.activity(named: "Gym") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
        // First sync: no cursor yet, so the fetch ran without `deleted_since`.
        #expect(mock.fetchedDeletionsSince.first! == nil)
    }

    @Test("entry tombstone converges with no outbox")
    func entryTombstoneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.mergeEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        mock.deletionsResult = [Deletion(resource: "entry", recordID: "e1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.activity(id: "a1") != nil)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("category tombstone removes joins and the row while the activity survives untagged")
    func categoryTombstoneConverges() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeCategory(TimeOfLife.Category(
            id: "cat-1", name: "Work", icon: "briefcase", createdAt: old, updatedAt: old
        ))
        let created = try await store.createOrResolveActivity(named: "Gym", categoryIDs: ["cat-1"])
        guard case let .created(activity) = created else {
            Issue.record("expected created")
            return
        }
        mock.deletionsResult = [Deletion(resource: "category", recordID: "cat-1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.category(id: "cat-1") == nil)
        let stored = try await store.activity(id: activity.id)
        #expect(stored?.categoryIDs.isEmpty == true)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("stale tombstone keeps a clean local row newer than the deletion (R1)")
    func staleTombstoneKeepsCleanNewerRow() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        let recreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: recreatedAt))
        // No pending create/update rows: a recreation via the pull-merge path
        // is clean, and its updated_at is newer than the stale tombstone.
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "a1")?.name == "Gym")
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
        #expect(try await store.outboxRows().isEmpty)
    }

    @Test("tombstones drop a stale pending update before the drain, so the 404-throwing update mock is never called")
    func tombstonesDropStalePendingUpdatePreDrain() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        _ = try await store.updateActivity(Activity(
            id: "a1", name: "Gym v2", createdAt: old,
            updatedAt: Date(timeIntervalSince1970: 1_620_000_000)
        ))
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]
        mock.updateActivityHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // The tombstone step removed the row and its pending update row
        // before the drain ran — no update was ever pushed, and the cycle
        // stayed idle (a push would have thrown).
        #expect(mock.calls.allSatisfy { $0.method != "updateActivity" })
        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "a1") == nil)
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
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "unknown", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "unknown") == nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    @Test("deletions cursor advances to the max deleted_at across a batch")
    func deletionsCursorAdvancesToMax() async throws {
        let (store, mock, controller) = makeContext()
        let earlier = Date(timeIntervalSince1970: 1_640_000_000)
        let later = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: earlier, updatedAt: earlier))
        try await store.mergeActivity(Activity(id: "a2", name: "Run", createdAt: earlier, updatedAt: earlier))
        mock.deletionsResult = [
            Deletion(resource: "activity", recordID: "a1", deletedAt: earlier),
            Deletion(resource: "activity", recordID: "a2", deletedAt: later),
        ]

        controller.activate()
        await waitForCycle(controller)

        #expect(isIdle(controller.status))
        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.activity(id: "a2") == nil)
        #expect(try await store.lastSyncedAt(resource: "deletions") == later)
    }

    @Test("second sync sends the deletions cursor")
    func secondSyncSendsDeletionsCursor() async throws {
        let (store, mock, controller) = makeContext()
        let deletedAt = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: deletedAt, updatedAt: deletedAt))
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]

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
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.deleteActivity(id: "a1")
        mock.deletionsResult = [Deletion(resource: "activity", recordID: "a1", deletedAt: deletedAt)]

        controller.activate()
        await waitForCycle(controller)

        // The locally queued DELETE drained normally; the tombstone found
        // nothing to remove and dropped nothing but stale create/update rows.
        #expect(isIdle(controller.status))
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == deletedAt)
    }

    // MARK: - Push-404 resurrection (push-404-resurrect)

    @Test("entry push against a forgotten parent resurrects and retries")
    func entryCreateAgainstDeletedActivityResurrects() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        // The parent is gone relay-side with no tombstone on file
        // (pre-deployment ghost), but the full local rows exist.
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        var healedParents: [String] = []
        mock.createActivityHandler = { activity in healedParents.append(activity.id) }
        mock.createEntryHandler = { entry in
            // First attempt (pre-heal parent): relay answers parent-missing.
            if healedParents.isEmpty {
                throw APIError.server(code: "activity_not_found", message: "Referenced activity not found", details: [:])
            }
            #expect(entry.id == "e1")
            #expect(entry.activityID == "a1")
        }

        controller.activate()
        await waitForCycle(controller)

        // Parent re-posted, entry retried: everything intact, nothing queued.
        #expect(healedParents == ["a1"])
        #expect(try await store.activity(id: "a1")?.name == "Gym")
        #expect(try await store.entry(id: "e1") != nil)
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("stale entry update re-posts as create")
    func entryUpdateNotFoundRepostsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: t0, updatedAt: t0))
        try await store.mergeEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: t0, createdAt: t0, updatedAt: t0)
        )
        _ = try await store.updateEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: t0, createdAt: t0, updatedAt: t1)
        )
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

    @Test("stale activity update re-posts the full local row as create")
    func activityUpdateNotFoundRepostsAsCreate() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: t0, updatedAt: t0))
        try await store.mergeEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: t0, createdAt: t0, updatedAt: t0)
        )
        _ = try await store.updateActivity(Activity(id: "a1", name: "Gym v2", createdAt: t0, updatedAt: t1))
        mock.updateActivityHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }
        var createdIDs: [String] = []
        mock.createActivityHandler = { createdIDs.append($0.id) }

        controller.activate()
        await waitForCycle(controller)

        #expect(createdIDs == ["a1"])
        #expect(try await store.activity(id: "a1")?.name == "Gym v2")
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
            TimeOfLife.Category(id: "c1", name: "Sport", icon: "figure.run", createdAt: t0, updatedAt: t0)
        )
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", categoryIDs: ["c1"], createdAt: t0, updatedAt: t0))
        _ = try await store.updateCategory(
            TimeOfLife.Category(id: "c1", name: "Sport", icon: "tag", createdAt: t0, updatedAt: t1)
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
        #expect(try await store.activity(id: "a1")?.categoryIDs == ["c1"])
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("parent heal through a name collision remaps and retries")
    func entryHealViaCollisionRemap() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeActivity(Activity(id: "local-gym", name: "Gym", createdAt: old, updatedAt: old))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "local-gym", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        mock.createEntryHandler = { entry in
            if entry.activityID == "local-gym" {
                throw APIError.server(code: "activity_not_found", message: "Referenced activity not found", details: [:])
            }
            #expect(entry.activityID == "server-gym")
        }
        mock.createActivityHandler = { _ in
            throw APIError.server(code: "activity_exists", message: "exists", details: ["id": "server-gym", "name": "Gym"])
        }
        mock.fetchActivityHandler = { _ in Activity(id: "server-gym", name: "Gym") }

        controller.activate()
        await waitForCycle(controller)

        // Entries moved to the winner, payloads rewritten, retry pushed.
        #expect(try await store.activity(id: "local-gym") == nil)
        #expect(try await store.entry(id: "e1")?.activityID == "server-gym")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("failed parent heal surfaces the original error with rows retained")
    func entryHealFailureRethrowsOriginal() async throws {
        let (store, mock, controller) = makeContext()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.mergeActivity(Activity(id: "a1", name: "Gym", createdAt: old, updatedAt: old))
        try await store.createEntry(
            TimeEntry(id: "e1", activityID: "a1", activityName: "Gym", startedAt: old, createdAt: old, updatedAt: old)
        )
        mock.createEntryHandler = { _ in
            throw APIError.server(code: "activity_not_found", message: "Referenced activity not found", details: [:])
        }
        mock.createActivityHandler = { _ in
            throw APIError.server(code: "internal_error", message: "boom", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // Nothing converged, nothing lost: the rows stay queued and the cycle
        // reports the original push failure.
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "entry" && $0.op == "create" && $0.recordID == "e1" })
        #expect(try await store.entry(id: "e1") != nil)
        #expect(controller.status == .error("server(activity_not_found): Referenced activity not found"))
    }

    @Test("remap-leftover update clears without pushing")
    func remapLeftoverUpdateClears() async throws {
        let (store, mock, controller) = makeContext()
        let t0 = Date(timeIntervalSince1970: 1_600_000_000)
        let t1 = Date(timeIntervalSince1970: 1_650_000_000)
        // A create that will 409-remap, plus a stacked update for the same
        // losing id: after the remap the loser is gone locally and the
        // update would 404 forever (the pre-existing stacked-remap wedge).
        try await store.createActivity(Activity(id: "local-2", name: "Gym", createdAt: t0, updatedAt: t0))
        _ = try await store.updateActivity(Activity(id: "local-2", name: "Gym v2", createdAt: t0, updatedAt: t1))
        mock.createActivityHandler = { activity in
            if activity.id == "local-2" {
                throw APIError.server(code: "activity_exists", message: "exists", details: ["id": "server-gym", "name": "Gym"])
            }
        }
        mock.fetchActivityHandler = { _ in Activity(id: "server-gym", name: "Gym") }
        // The stale loser update must never be pushed: the repush path finds
        // no local row (remap already moved on) and clears the row.
        var updateCalls = 0
        mock.updateActivityHandler = { _ in
            updateCalls += 1
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        #expect(updateCalls == 0)
        #expect(try await store.activity(id: "local-2") == nil)
        #expect(try await store.activity(id: "server-gym")?.name == "Gym")
        #expect(try await store.outboxRows().isEmpty)
        #expect(isIdle(controller.status))
    }

    @Test("pre-tombstone relay does not fail the cycle")
    func fetchDeletionsNotFoundSkipsTombstones() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        mock.fetchDeletionsHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // Drain and pull ran normally around the skipped tombstone step.
        #expect(mock.calls.contains(Call("createActivity", "activity", "a1")))
        #expect(mock.calls.contains(Call("fetchActivities", "activity", nil)))
        #expect(try await store.outboxRows().isEmpty)
        #expect(try await store.lastSyncedAt(resource: "deletions") == nil)
        #expect(isIdle(controller.status))
    }

    @Test("activity create 404 still throws loudly")
    func activityCreateNotFoundThrows() async throws {
        let (store, mock, controller) = makeContext()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        mock.createActivityHandler = { _ in
            throw APIError.server(code: "not_found", message: "gone", details: [:])
        }

        controller.activate()
        await waitForCycle(controller)

        // No convergence for creates (impossible per routes): the row stays
        // queued and the cycle surfaces the failure.
        let rows = try await store.outboxRows()
        #expect(rows.contains { $0.resource == "activity" && $0.op == "create" && $0.recordID == "a1" })
        #expect(controller.status == .error("server(not_found): gone"))
    }

    // MARK: - Helpers

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
