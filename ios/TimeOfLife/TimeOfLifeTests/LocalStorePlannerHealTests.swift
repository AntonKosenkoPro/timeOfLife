import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// Field files whose recorded v3 predates the planner shape (day-planner
/// follow-up fix): an in-place upgrade from an intermediate build records
/// "v3" without the planner objects, so the shipped v3 migration is a
/// no-op for them and `plannerTasks()` throws "no such table" — Today
/// opens with an empty list plus the generic error dialog while Track
/// keeps working (entry/draft reads never touch the planner shape). The
/// open path must converge the planner shape (existing heal precedent:
/// `healTimerStateNotesColumn`).
@MainActor
@Suite("Planner schema heal (stale-v3 field files)")
struct LocalStorePlannerHealTests {
    /// Today loads clean (no error, empty snapshot) on a field file whose
    /// v3 record predates the planner shape, and the pre-existing
    /// entries/draft survive (the Track behavior the phone shows).
    @Test("Today loads clean on a field file whose v3 record predates the planner shape")
    func todayLoadsOnStaleV3FieldFile() async throws {
        let url = temporaryAccountURL(userID: "field-u1")
        do {
            // Healthy account file through the production seam, seeded like
            // the phone: committed entries plus a running draft, no
            // planner rows.
            let seed = try LocalStore(url: url, userID: "field-u1")
            _ = try await seed.createEntry(TimeEntry(
                id: "e1", activityText: "Work",
                startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
                endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
            ))
            try await seed.saveTimerDraft(
                activityText: "Work", categoryIDs: [],
                startedAt: Date(timeIntervalSinceReferenceDate: 2_000)
            )
        }
        // Simulate the field condition: v3 stays recorded, planner objects
        // are absent.
        try stripPlannerV3Objects(at: url)
        try #require(try v3Recorded(at: url), "sim must keep the v3 record so migrate is a no-op")
        // Reopen through the production seam (migrate + heals) and drive
        // the exact Today load.
        let reopened = try LocalStore(url: url, userID: "field-u1")
        let vm = PlannerViewModel(
            store: reopened,
            undoBuffer: UndoBufferStore(store: reopened),
            timer: TimerService(store: reopened)
        )
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.snapshot.tasks.isEmpty)
        #expect(try await reopened.plannerTasks().isEmpty)
        // The pre-existing data survives the heal.
        #expect(try await reopened.recents(limit: 10).count == 1)
        #expect(try await reopened.timerDraft()?.activityText == "Work")
    }

    /// Today loads clean on a field file whose `planner_tasks` has an
    /// intermediate-build shape (recorded v3, table present but missing
    /// columns current code reads): the bind itself must succeed and the
    /// table must converge to the current shape.
    @Test("Today loads clean on a field file with an intermediate planner table shape")
    func todayLoadsOnIntermediatePlannerTableShape() async throws {
        let url = temporaryAccountURL(userID: "field-u2")
        do {
            let seed = try LocalStore(url: url, userID: "field-u2")
            _ = try await seed.createEntry(TimeEntry(
                id: "e1", activityText: "Work",
                startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
                endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600
            ))
        }
        // Simulate the intermediate field condition: v3 recorded, planner
        // table present but shaped without the order/completion columns.
        try reshufflePlannerTableToIntermediateShape(at: url)
        try #require(try v3Recorded(at: url), "sim must keep the v3 record so migrate is a no-op")
        // The bind itself must succeed (a CREATE INDEX against the stale
        // shape threw here and dead-ended the launch gate).
        let reopened = try LocalStore(url: url, userID: "field-u2")
        let vm = PlannerViewModel(
            store: reopened,
            undoBuffer: UndoBufferStore(store: reopened),
            timer: TimerService(store: reopened)
        )
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.snapshot.tasks.isEmpty)
        #expect(try await reopened.plannerTasks().isEmpty)
        #expect(try await reopened.recents(limit: 10).count == 1)
        // The converged shape accepts writes again.
        let created = try await reopened.createPlannerTask(
            id: "t1", name: "Read", positionKey: "500000", operationID: "op1"
        )
        guard case .saved = created else {
            Issue.record("create must succeed on the healed shape, got \(created)")
            return
        }
    }

    /// Replaces `planner_tasks` with an intermediate-build shape (recorded
    /// v3, table present but missing the columns current code reads).
    private func reshufflePlannerTableToIntermediateShape(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS planner_tasks")
            try db.execute(sql: "DROP INDEX IF EXISTS index_planner_tasks_on_position")
            try db.execute(sql: """
                CREATE TABLE planner_tasks (id TEXT PRIMARY KEY, name TEXT NOT NULL)
                """)
        }
    }

    /// Removes every v3 planner object while keeping the recorded "v3"
    /// migration, reproducing a field file upgraded in place from an
    /// intermediate build whose v3 lacked the planner shape.
    private func stripPlannerV3Objects(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS planner_tasks")
            let syncColumns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('sync_state')")
            if syncColumns.contains("cursor_revision") {
                try db.execute(sql: "ALTER TABLE sync_state DROP COLUMN cursor_revision")
            }
            let timerColumns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('timer_state')")
            if timerColumns.contains("planner_task_id") {
                try db.execute(sql: "ALTER TABLE timer_state DROP COLUMN planner_task_id")
            }
        }
    }

    private func v3Recorded(at url: URL) throws -> Bool {
        let queue = try DatabaseQueue(path: url.path)
        let applied = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        return applied.contains("v3")
    }

    private func temporaryAccountURL(userID: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: userID))
    }
}
