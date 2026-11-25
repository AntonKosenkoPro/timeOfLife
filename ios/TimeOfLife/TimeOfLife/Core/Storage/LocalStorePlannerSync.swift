import Foundation
import GRDB

// MARK: - Planner sync (day-planner)

/// `LocalStore` planner sync surface: the revision-cursor/page/drain
/// integration plus the timer-draft claim. CRUD and undo live in
/// `LocalStorePlanner.swift`; every mutation still commits its outbox
/// row in the same transaction as the state change.
extension LocalStore {
    // MARK: - Planner sync state (revision cursor)

    /// The last-applied planner feed revision, or 0 before the first pull.
    func plannerRevisionCursor() throws -> Int64 {
        try queue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT cursor_revision FROM sync_state WHERE resource = ?
                """, arguments: [Self.plannerCursorResource]) ?? 0
        }
    }

    /// Advances the planner feed cursor. Called only from
    /// `applyPlannerPage`, which persists the page and the cursor
    /// atomically.
    private static let plannerCursorResource = "planner"

    private static func setPlannerRevisionCursor(_ db: Database, _ revision: Int64) throws {
        try db.execute(
            sql: """
                INSERT INTO sync_state (resource, cursor_revision) VALUES (?, ?)
                ON CONFLICT(resource) DO UPDATE SET cursor_revision = excluded.cursor_revision
                """,
            arguments: [plannerCursorResource, revision]
        )
    }

    /// Applies one feed page and persists its cursor in ONE transaction: a
    /// resumed pull replays from the cursor and never skips a change. Rules,
    /// in order per change:
    /// - locally deleted (buffered undoable deletion or pending outbox
    ///   delete): skipped — delete-wins, the queued DELETE converges the
    ///   relay on drain;
    /// - pending local create/update: kept visible — EXCEPT a terminal
    ///   relay delete, which wins: pending create/update rows are dropped
    ///   and the local row is removed (a Stop-driven completion queued
    ///   offline against a remotely deleted task converges to deleted
    ///   without recreating it);
    /// - otherwise the feed state is applied (live rows upserted, terminal
    ///   markers remove the local row and drop superseded pending
    ///   create/update rows).
    func applyPlannerPage(changes: [PlannerFeedChange], cursor: Int64) throws {
        try queue.write { db in
            for change in changes {
                let id = change.task.id
                if try Self.plannerLocallyDeleted(db, recordID: id) {
                    continue
                }
                if try Self.hasPendingPlannerIntent(db, recordID: id) {
                    if change.deleted {
                        try Self.dropPendingPlannerIntent(db, recordID: id)
                        try db.execute(sql: "DELETE FROM planner_tasks WHERE id = ?", arguments: [id])
                    }
                    continue
                }
                if change.deleted {
                    try db.execute(sql: "DELETE FROM planner_tasks WHERE id = ?", arguments: [id])
                    try Self.dropPendingPlannerIntent(db, recordID: id)
                    continue
                }
                try db.execute(
                    sql: """
                        INSERT INTO planner_tasks (id, name, position_key, completed_on, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            name = excluded.name,
                            position_key = excluded.position_key,
                            completed_on = excluded.completed_on,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        id, change.task.name, change.task.positionKey, change.task.completedOn,
                        change.task.createdAt, change.task.updatedAt,
                    ]
                )
            }
            try Self.setPlannerRevisionCursor(db, cursor)
        }
    }

    /// Whether the planner task is locally deleted: a pending outbox DELETE
    /// or a buffered undoable deletion snapshot. Mirrors `isLocallyDeleted`
    /// for the planner resource inside a write transaction.
    private static func plannerLocallyDeleted(_ db: Database, recordID: String) throws -> Bool {
        let pending = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM outbox
            WHERE resource = ? AND record_id = ? AND op = 'delete'
            """, arguments: [plannerResource, recordID]) ?? 0
        if pending > 0 { return true }
        let rows = try UndoBufferRow.fetchAll(db, sql: "SELECT * FROM undo_buffer")
        for row in rows {
            guard let data = row.payload.data(using: .utf8),
                  let snapshot = try? JSONDecoder().decode(DeletionSnapshot.self, from: data),
                  snapshot.records.contains(where: { $0.resource == plannerResource && $0.recordID == recordID })
            else { continue }
            return true
        }
        return false
    }

    /// Whether a planner task has a pending local create/update intent.
    private static func hasPendingPlannerIntent(_ db: Database, recordID: String) throws -> Bool {
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM outbox
            WHERE resource = ? AND record_id = ? AND op IN ('create', 'update')
            """, arguments: [plannerResource, recordID]) ?? 0
        return count > 0
    }

    /// Drops pending local create/update intents for a planner task. Pending
    /// DELETE rows are left alone: the drain converges them.
    private static func dropPendingPlannerIntent(_ db: Database, recordID: String) throws {
        try db.execute(
            sql: "DELETE FROM outbox WHERE resource = ? AND record_id = ? AND op IN ('create', 'update')",
            arguments: [plannerResource, recordID]
        )
    }

    /// Adopts the relay's current task after a 409 `planner_conflict`: the
    /// server version replaces the local row and superseded pending
    /// create/update rows are dropped (a pending DELETE still converges the
    /// relay on drain — delete-wins is checked first and skips adoption).
    func adoptPlannerTask(_ task: PlannerTask) throws {
        try queue.write { db in
            if try Self.plannerLocallyDeleted(db, recordID: task.id) {
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO planner_tasks (id, name, position_key, completed_on, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        position_key = excluded.position_key,
                        completed_on = excluded.completed_on,
                        updated_at = excluded.updated_at
                    """,
                arguments: [task.id, task.name, task.positionKey, task.completedOn, task.createdAt, task.updatedAt]
            )
            try Self.dropPendingPlannerIntent(db, recordID: task.id)
        }
    }

    /// Converges a planner task to its terminal relay delete (410
    /// `planner_gone`): drops every pending outbox row for the task and
    /// removes the local row. Retrying the operation is futile — the marker
    /// never clears.
    func convergePlannerTaskDeleted(id: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE resource = ? AND record_id = ?",
                arguments: [Self.plannerResource, id]
            )
            try db.execute(sql: "DELETE FROM planner_tasks WHERE id = ?", arguments: [id])
        }
    }

    /// Removes outbox rows for a planner task (drain convergence that keeps
    /// the row, e.g. a validated-noop). Prefer the targeted
    /// adopt/converge paths above for conflict/terminal outcomes.
    func removePlannerOutboxRows(recordID: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE resource = ? AND record_id = ?",
                arguments: [Self.plannerResource, recordID]
            )
        }
    }

    // MARK: - Timer draft planner link (day-planner D3)

    /// Atomically claims the running draft for a planner-linked Start:
    /// inserts the singleton only when no draft exists. Returns false when
    /// a run is already active, pending, or awaiting a Stop retry — a
    /// second Start never replaces it at the mutation boundary.
    func claimTimerDraft(
        activityText: String,
        categoryIDs: [String],
        startedAt: Date,
        notes: String = "",
        plannerTaskID: String? = nil
    ) throws -> Bool {
        let trimmed = ActivityName.normalized(activityText)
        let joined = Self.deduplicate(categoryIDs).joined(separator: ",")
        return try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO timer_state (id, activity_text, category_ids, notes, started_at, status, planner_task_id)
                    SELECT 'singleton', ?, ?, ?, ?, 'running', ?
                    WHERE NOT EXISTS (SELECT 1 FROM timer_state WHERE id = 'singleton')
                    """,
                arguments: [trimmed, joined, notes, startedAt, plannerTaskID]
            )
            return db.changesCount > 0
        }
    }
}
