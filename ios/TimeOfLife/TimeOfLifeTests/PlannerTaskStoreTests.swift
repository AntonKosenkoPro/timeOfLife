// swiftlint:disable file_length
import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// Account-local day-planner storage (day-planner spec D2, local-first-store
/// delta): the additive `planner_tasks` migration plus transactional CRUD and
/// injectable local-day cleanup. Planner mutations never enqueue outbox rows
/// and never touch the undo buffer or sync cursors.
@Suite("PlannerTaskStore")
struct PlannerTaskStoreTests {

    // MARK: - Helpers

    private func temporaryStoreURL(userID: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: userID))
    }

    private func makeStore(userID: String? = "planner-u1") throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL(userID: userID ?? "planner-u1"), userID: userID)
    }

    private func outboxCount(_ store: LocalStore) async throws -> Int {
        try await store.outboxRowCount()
    }

    private func undoIsEmpty(_ store: LocalStore) async throws -> Bool {
        try await UndoBufferStore(store: store).mostRecent() == nil
    }

    private func plannerTableColumns(at url: URL) throws -> [String] {
        let queue = try DatabaseQueue(path: url.path)
        return try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('planner_tasks')")
        }
    }

    // MARK: - Migration

    @Test("fresh files gain an empty planner table")
    func freshFileHasEmptyPlannerTable() async throws {
        let url = temporaryStoreURL(userID: "planner-fresh")
        let store = try LocalStore(url: url, userID: "planner-fresh")
        #expect(try await store.plannerTasks(expectedUserID: "planner-fresh").isEmpty)
        #expect(try plannerTableColumns(at: url).sorted() == ["completed_at", "created_at", "id", "text"])
    }

    @Test("re-migrating a populated file preserves entries, categories, and tasks")
    func remigrationPreservesAllData() async throws {
        let url = temporaryStoreURL(userID: "planner-remigrate")
        let first = try LocalStore(url: url, userID: "planner-remigrate")
        let category = Category(id: "c1", name: "Work", icon: "laptopcomputer")
        try await first.createCategory(category)
        let storedCategory = try await first.category(id: "c1")
        let task = try await first.addPlannerTask(text: "Gym", expectedUserID: "planner-remigrate")
        // A second store on the same file re-runs the additive migrator.
        let second = try LocalStore(url: url, userID: "planner-remigrate")
        let tasks = try await second.plannerTasks(expectedUserID: "planner-remigrate")
        #expect(tasks.count == 1)
        #expect(tasks[0].id == task.id)
        #expect(tasks[0].text == task.text)
        #expect(tasks[0].completedAt == task.completedAt)
        // Exact `Date` equality is asserted through a window, not `==`: the
        // insert returns the in-memory quantized stamp while the second
        // store reads the row back through millisecond-serialized storage,
        // which can differ by a final floating-point ulp.
        #expect(abs(tasks[0].createdAt.timeIntervalSince(task.createdAt)) < 1)
        #expect(try await second.category(id: "c1") == storedCategory)
    }

    // MARK: - Creation

    @Test("add trims text and orders oldest-created first")
    func addTrimsAndOrders() async throws {
        let store = try makeStore()
        let first = try await store.addPlannerTask(text: "  Gym  ", expectedUserID: "planner-u1")
        #expect(first.text == "Gym")
        #expect(first.completedAt == nil)
        let second = try await store.addPlannerTask(text: "Read", expectedUserID: "planner-u1")
        let tasks = try await store.plannerTasks(expectedUserID: "planner-u1")
        #expect(tasks.map(\.id) == [first.id, second.id])
    }

    @Test("duplicate text is allowed with independent identity")
    func duplicateTextAllowed() async throws {
        let store = try makeStore()
        let first = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let second = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        #expect(first.id != second.id)
        let tasks = try await store.plannerTasks(expectedUserID: "planner-u1")
        #expect(tasks.count == 2)
        #expect(try await store.removePlannerTask(id: first.id, expectedUserID: "planner-u1"))
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").map(\.id) == [second.id])
    }

    @Test("invalid input throws and writes nothing")
    func invalidInputThrows() async throws {
        let store = try makeStore()
        await #expect(throws: PlannerTaskValidationError.empty) {
            try await store.addPlannerTask(text: "   ", expectedUserID: "planner-u1")
        }
        await #expect(throws: PlannerTaskValidationError.tooLong) {
            try await store.addPlannerTask(text: String(repeating: "x", count: 61), expectedUserID: "planner-u1")
        }
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").isEmpty)
        #expect(try await outboxCount(store) == 0)
    }

    @Test("exactly 60 characters is accepted")
    func sixtyCharactersAccepted() async throws {
        let store = try makeStore()
        let task = try await store.addPlannerTask(
            text: String(repeating: "y", count: 60), expectedUserID: "planner-u1")
        #expect(task.text.count == 60)
    }

    // MARK: - Completion

    @Test("toggle sets and clears completion without reordering")
    func toggleCompletion() async throws {
        let store = try makeStore()
        let first = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        _ = try await store.addPlannerTask(text: "Read", expectedUserID: "planner-u1")
        let checked = try await store.setPlannerTaskCompleted(
            id: first.id, completed: true, expectedUserID: "planner-u1")
        #expect(checked?.isCompleted == true)
        #expect(checked?.completedAt != nil)
        // Checking does not reorder: the checked row stays first.
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").first?.id == first.id)
        let unchecked = try await store.setPlannerTaskCompleted(
            id: first.id, completed: false, expectedUserID: "planner-u1")
        #expect(unchecked?.isCompleted == false)
        #expect(unchecked?.completedAt == nil)
    }

    @Test("toggling a missing task returns nil")
    func toggleMissingReturnsNil() async throws {
        let store = try makeStore()
        #expect(try await store.setPlannerTaskCompleted(
            id: "missing", completed: true, expectedUserID: "planner-u1") == nil)
    }

    // MARK: - Removal

    @Test("remove deletes only the named row")
    func removeDeletesOne() async throws {
        let store = try makeStore()
        let first = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let second = try await store.addPlannerTask(text: "Read", expectedUserID: "planner-u1")
        #expect(try await store.removePlannerTask(id: first.id, expectedUserID: "planner-u1"))
        #expect(!(try await store.removePlannerTask(id: first.id, expectedUserID: "planner-u1")))
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").map(\.id) == [second.id])
    }

    // MARK: - Cleanup (local-day cutoff)

    @Test("prune removes only completions strictly before the local day start")
    func pruneStrictlyEarlierOnly() async throws {
        let store = try makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // A fixed local noon on a non-DST date.
        let noon = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 3, day: 2,
            hour: 12, minute: 0))!
        let cutoff = PlannerDayCutoff.startOfLocalDay(containing: noon, calendar: calendar)
        let before = try await store.addPlannerTask(text: "old", expectedUserID: "planner-u1")
        _ = try await store.setPlannerTaskCompleted(
            id: before.id, completed: true, expectedUserID: "planner-u1",
            now: cutoff.addingTimeInterval(-1))
        let atBoundary = try await store.addPlannerTask(text: "boundary", expectedUserID: "planner-u1")
        _ = try await store.setPlannerTaskCompleted(
            id: atBoundary.id, completed: true, expectedUserID: "planner-u1", now: cutoff)
        let unfinished = try await store.addPlannerTask(text: "todo", expectedUserID: "planner-u1")
        #expect(try await store.prunePlannerTasks(completedBefore: cutoff, expectedUserID: "planner-u1") == 1)
        #expect(Set(try await store.plannerTasks(expectedUserID: "planner-u1").map(\.id))
            == [atBoundary.id, unfinished.id])
        // Idempotent retry removes nothing further.
        #expect(try await store.prunePlannerTasks(completedBefore: cutoff, expectedUserID: "planner-u1") == 0)
    }

    @Test("uncheck before expiry retains the task; recheck stamps a new time")
    func uncheckRecheckCycle() async throws {
        let store = try makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dayOne = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 3, day: 2, hour: 12))!
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne)!
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let firstCheck = try await store.setPlannerTaskCompleted(
            id: task.id, completed: true, expectedUserID: "planner-u1", now: dayOne)
        _ = try await store.setPlannerTaskCompleted(
            id: task.id, completed: false, expectedUserID: "planner-u1", now: dayOne)
        let cutoffTwo = PlannerDayCutoff.startOfLocalDay(containing: dayTwo, calendar: calendar)
        #expect(try await store.prunePlannerTasks(completedBefore: cutoffTwo, expectedUserID: "planner-u1") == 0)
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").count == 1)
        let rechecked = try await store.setPlannerTaskCompleted(
            id: task.id, completed: true, expectedUserID: "planner-u1", now: dayTwo)
        #expect(rechecked?.completedAt != firstCheck?.completedAt)
    }

    @Test("one reconciliation after multiple inactive days removes all eligible rows")
    func multipleInactiveDays() async throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let dayFive = calendar.date(byAdding: .day, value: 4, to: dayOne)!
        for name in ["a", "b", "c"] {
            let task = try await store.addPlannerTask(text: name, expectedUserID: "planner-u1")
            _ = try await store.setPlannerTaskCompleted(
                id: task.id, completed: true, expectedUserID: "planner-u1", now: dayOne)
        }
        let cutoff = PlannerDayCutoff.startOfLocalDay(containing: dayFive, calendar: calendar)
        #expect(try await store.reconciledPlannerTasks(
            pruningBefore: cutoff, expectedUserID: "planner-u1").isEmpty)
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").isEmpty)
    }

    @Test("DST short and long days resolve against the calendar day, not 24 hours")
    func dstDaysResolveByCalendar() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // Spring forward: 2026-03-08 is a 23-hour day.
        let springNoon = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 3, day: 8, hour: 12))!
        let springCutoff = PlannerDayCutoff.startOfLocalDay(containing: springNoon, calendar: calendar)
        // Fall back: 2026-11-01 is a 25-hour day.
        let fallNoon = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 11, day: 1, hour: 12))!
        let fallCutoff = PlannerDayCutoff.startOfLocalDay(containing: fallNoon, calendar: calendar)
        // The cutoff is midnight local in both cases, not now-minus-24h.
        #expect(calendar.component(.hour, from: springCutoff) == 0)
        #expect(calendar.component(.hour, from: fallCutoff) == 0)
        #expect(springNoon.timeIntervalSince(springCutoff) < 24 * 3600)
        #expect(fallNoon.timeIntervalSince(fallCutoff) < 24 * 3600)
    }

    @Test("time-zone travel re-evaluates eligibility at the current local boundary")
    func timeZoneChangeReevaluates() async throws {
        let store = try makeStore()
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 2026-06-01 09:00 UTC = 2026-06-01 02:00 PDT = 2026-06-01 18:00 JST:
        // the same instant falls on the same local date in both zones here.
        let instant = utc.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        // Completed 2026-06-01 02:00 UTC = 2026-05-31 19:00 PDT (prior local
        // day: eligible under Los Angeles) = 2026-06-01 11:00 JST (today:
        // retained under Tokyo). The same completion prunes only under the
        // Pacific boundary.
        let completion = utc.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 2))!
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        _ = try await store.setPlannerTaskCompleted(
            id: task.id, completed: true, expectedUserID: "planner-u1", now: completion)
        let pacificCutoff = PlannerDayCutoff.startOfLocalDay(containing: instant, calendar: pacific)
        let tokyoCutoff = PlannerDayCutoff.startOfLocalDay(containing: instant, calendar: tokyo)
        #expect(pacificCutoff != tokyoCutoff)
        #expect(try await store.prunePlannerTasks(
            completedBefore: tokyoCutoff, expectedUserID: "planner-u1") == 0)
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").count == 1)
        #expect(try await store.prunePlannerTasks(
            completedBefore: pacificCutoff, expectedUserID: "planner-u1") == 1)
    }

    // MARK: - Local-only (no relay/undo/cursor effects)

    @Test("planner mutations leave outbox, undo buffer, and cursors untouched")
    func plannerMutationsStayLocal() async throws {
        let store = try makeStore()
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        _ = try await store.setPlannerTaskCompleted(
            id: task.id, completed: true, expectedUserID: "planner-u1")
        _ = try await store.setPlannerTaskCompleted(
            id: task.id, completed: false, expectedUserID: "planner-u1")
        _ = try await store.prunePlannerTasks(
            completedBefore: Date(), expectedUserID: "planner-u1")
        _ = try await store.removePlannerTask(id: task.id, expectedUserID: "planner-u1")
        #expect(try await outboxCount(store) == 0)
        #expect(try await undoIsEmpty(store))
        #expect(try await store.lastSyncedAt(resource: "entries") == nil)
        #expect(try await store.lastSyncedAt(resource: "categories") == nil)
    }

    // MARK: - Account fencing

    @Test("stale expected account is rejected without touching rows")
    func staleAccountRejected() async throws {
        let store = try makeStore(userID: "planner-a")
        _ = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-a")
        await #expect(throws: LocalStore.LocalStoreError.accountMismatch) {
            try await store.addPlannerTask(text: "Read", expectedUserID: "planner-b")
        }
        await #expect(throws: LocalStore.LocalStoreError.accountMismatch) {
            try await store.plannerTasks(expectedUserID: "planner-b")
        }
        await #expect(throws: LocalStore.LocalStoreError.accountMismatch) {
            try await store.prunePlannerTasks(completedBefore: Date(), expectedUserID: "planner-b")
        }
        #expect(try await store.plannerTasks(expectedUserID: "planner-a").count == 1)
    }

    @Test("a suspended store fails writes without clearing the checklist")
    func suspendedStoreFailsFast() async throws {
        let store = try makeStore()
        _ = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        DatabaseSuspension.shared.noteSuspended()
        defer {
            if DatabaseSuspension.shared.isSuspended {
                DatabaseSuspension.shared.noteResumed()
            }
        }
        await #expect(throws: LocalStore.LocalStoreError.suspended) {
            try await store.addPlannerTask(text: "Read", expectedUserID: "planner-u1")
        }
        DatabaseSuspension.shared.noteResumed()
        #expect(try await store.plannerTasks(expectedUserID: "planner-u1").count == 1)
    }

    // MARK: - Retention and erasure

    @Test("sign-out keeps tasks; re-login reopens them")
    func signOutRetainsTasks() async throws {
        let url = temporaryStoreURL(userID: "planner-retain")
        let signedIn = try LocalStore(url: url, userID: "planner-retain")
        _ = try await signedIn.addPlannerTask(text: "Gym", expectedUserID: "planner-retain")
        // Sign-out releases the binding without deleting the file
        // (`openAccount` is not used here: it resolves the production App
        // Group path, never a test directory).
        await signedIn.closeAccount()
        let returned = try LocalStore(url: url, userID: "planner-retain")
        #expect(try await returned.plannerTasks(expectedUserID: "planner-retain").count == 1)
    }

    // MARK: - Stop-completes-match (timer-capture-experience delta)

    @Test("stop completion completes the oldest unfinished exact-text match only")
    func stopCompletionOldestFirst() async throws {
        let store = try makeStore()
        let first = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let second = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let other = try await store.addPlannerTask(text: "Read", expectedUserID: "planner-u1")
        let stopTime = Date()
        let completed = try await store.completeOldestMatchingPlannerTask(
            text: "Gym", expectedUserID: "planner-u1", now: stopTime)
        #expect(completed?.id == first.id)
        // Stamped with the stop time, asserted through a window (not exact
        // `Date` equality): storage round-trips millisecond-serialized
        // dates, which can differ from the in-memory value by one ulp.
        if let stamped = completed?.completedAt {
            #expect(abs(stamped.timeIntervalSince(stopTime)) < 1)
        } else {
            Issue.record("expected a completion timestamp")
        }
        let rows = try await store.plannerTasks(expectedUserID: "planner-u1")
        #expect(rows.first { $0.id == second.id }?.isCompleted == false)
        #expect(rows.first { $0.id == other.id }?.isCompleted == false)
        // A second call completes the next oldest duplicate, one per call.
        let next = try await store.completeOldestMatchingPlannerTask(
            text: "Gym", expectedUserID: "planner-u1", now: stopTime)
        #expect(next?.id == second.id)
        // No unfinished match left: returns nil and changes nothing.
        #expect(try await store.completeOldestMatchingPlannerTask(
            text: "Gym", expectedUserID: "planner-u1", now: stopTime) == nil)
        #expect(try await store.outboxRowCount() == 0)
    }

    @Test("stop completion ignores already-completed rows and near matches")
    func stopCompletionSkipsCompletedAndNearMatches() async throws {
        let store = try makeStore()
        let done = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-u1")
        let checkTime = Date()
        _ = try await store.setPlannerTaskCompleted(
            id: done.id, completed: true, expectedUserID: "planner-u1")
        let stopTime = Date()
        // Only an already-completed exact match exists: no-no-op change.
        #expect(try await store.completeOldestMatchingPlannerTask(
            text: "Gym", expectedUserID: "planner-u1", now: stopTime) == nil)
        let reread = try await store.plannerTasks(expectedUserID: "planner-u1").first
        #expect(reread?.isCompleted == true)
        // The original completion stamp is untouched (window, not `==`:
        // millisecond-serialized storage can differ by one ulp).
        if let stamped = reread?.completedAt {
            #expect(stamped >= checkTime.addingTimeInterval(-1))
            #expect(stamped <= Date().addingTimeInterval(1))
        } else {
            Issue.record("expected the retained completion timestamp")
        }
        // Case, whitespace, and substring variants are not exact matches.
        _ = try await store.addPlannerTask(text: "GYM", expectedUserID: "planner-u1")
        #expect(try await store.completeOldestMatchingPlannerTask(
            text: "Gym", expectedUserID: "planner-u1", now: stopTime) == nil)
        #expect(try await store.completeOldestMatchingPlannerTask(
            text: "Gy", expectedUserID: "planner-u1", now: stopTime) == nil)
        #expect(try await store.completeOldestMatchingPlannerTask(
            text: "Nomatch", expectedUserID: "planner-u1", now: stopTime) == nil)
        #expect(try await store.outboxRowCount() == 0)
    }

    @Test("stop completion is account-fenced and defers on suspension")
    func stopCompletionFencingAndSuspension() async throws {
        let store = try makeStore(userID: "planner-a")
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-a")
        await #expect(throws: LocalStore.LocalStoreError.accountMismatch) {
            try await store.completeOldestMatchingPlannerTask(
                text: "Gym", expectedUserID: "planner-b")
        }
        #expect(try await store.plannerTasks(expectedUserID: "planner-a")
            .first { $0.id == task.id }?.isCompleted == false)
        DatabaseSuspension.shared.noteSuspended()
        defer {
            if DatabaseSuspension.shared.isSuspended {
                DatabaseSuspension.shared.noteResumed()
            }
        }
        await #expect(throws: LocalStore.LocalStoreError.suspended) {
            try await store.completeOldestMatchingPlannerTask(
                text: "Gym", expectedUserID: "planner-a")
        }
        DatabaseSuspension.shared.noteResumed()
        #expect(try await store.plannerTasks(expectedUserID: "planner-a")
            .first { $0.id == task.id }?.isCompleted == false)
    }

    @Test("eraseAll removes the account file with its planner rows")
    func eraseAllRemovesPlannerRows() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let url = base.appendingPathComponent(LocalStore.databaseFileName(userID: "planner-erase"))
        let store = try LocalStore(url: url, userID: "planner-erase")
        _ = try await store.addPlannerTask(text: "Gym", expectedUserID: "planner-erase")
        try await store.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("eraseAccount removes only the named account's rows")
    func eraseAccountIsolated() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let storeA = try LocalStore(
            url: base.appendingPathComponent(LocalStore.databaseFileName(userID: "planner-x")),
            userID: "planner-x")
        _ = try await storeA.addPlannerTask(text: "Gym", expectedUserID: "planner-x")
        let storeB = try LocalStore(
            url: base.appendingPathComponent(LocalStore.databaseFileName(userID: "planner-y")),
            userID: "planner-y")
        _ = try await storeB.addPlannerTask(text: "Read", expectedUserID: "planner-y")
        try await storeA.eraseAccount(userID: "planner-x", in: base)
        #expect(!FileManager.default.fileExists(
            atPath: base.appendingPathComponent(LocalStore.databaseFileName(userID: "planner-x")).path))
        #expect(try await storeB.plannerTasks(expectedUserID: "planner-y").count == 1)
    }
}
