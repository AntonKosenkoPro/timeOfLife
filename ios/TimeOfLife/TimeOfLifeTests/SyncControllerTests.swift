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

        controller.activate()
        await waitForCycle(controller)

        let entry = try await store.entry(id: "e1")
        #expect(entry?.activityID == "server-id")

        let remaining = try await store.outboxRows()
        #expect(remaining.allSatisfy { $0.resource == "entry" && $0.op == "update" })
        #expect(isIdle(controller.status))
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
