import Foundation
import GRDB

// MARK: - Planner tasks (day-planner)

/// `LocalStore` planner surface: account-file CRUD, durable undo, the
/// Today/progress projection source, ordered position allocation support,
/// and the sync-client's page/cursor/drain integration. Every mutation
/// writes its outbox row in the same transaction as the state change — the
/// single-chokepoint rule — and planner rows never feed History, Insights,
/// or Recents.
extension LocalStore {
    /// The outbox/undo resource string for planner tasks. Kept distinct
    /// from the entry/category/tombstone namespaces: planner deletions
    /// never touch `/deletions` and entry/category resurrection is
    /// unaffected.
    static let plannerResource = "planner_task"

    /// The outcome of a planner write.
    enum PlannerMutation: Equatable {
        /// The task was written with its outbox row queued.
        case saved(PlannerTask)
        /// The name is invalid (empty/too long — the shared timer-name rule).
        case invalid(ActivityName.Validation)
        /// The task no longer exists.
        case missing
        /// The local write failed (persistence error).
        case failure
    }

    /// The outcome of `deletePlannerTaskUndoable(...)`.
    enum PlannerDelete: Equatable {
        /// The task was removed; the snapshot is in the durable undo
        /// buffer (no outbox row yet).
        case deleted(PlannerTask)
        /// The task no longer exists.
        case missing
        /// The local write failed (persistence error).
        case failure
    }

    /// Carries the planner link across an atomic linked Stop: the exact
    /// task to complete with the entry, the fresh operation id for its
    /// queued completion, and the civil date of Stop.
    struct PlannerStopLink: Sendable {
        var taskID: String
        var operationID: String
        var completedOn: String
    }

    /// Maps a `planner_tasks` row into a PlannerTask. `category_ids` is
    /// the ordered set as a comma-joined TEXT column (timer_state grammar);
    /// NULL or empty decodes to no categories.
    private static func plannerTask(from row: Row) -> PlannerTask {
        let joined: String? = row["category_ids"]
        return PlannerTask(
            id: row["id"],
            name: row["name"],
            positionKey: row["position_key"],
            completedOn: row["completed_on"],
            categoryIDs: plannerCategoryIDs(from: joined),
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    /// Decodes a comma-joined ordered category set (the `timer_state`
    /// grammar). UUIDs never contain a comma, so the split is lossless.
    /// Internal (not private): the sync extension in
    /// `LocalStorePlannerSync.swift` shares these helpers.
    static func plannerCategoryIDs(from joined: String?) -> [String] {
        guard let joined, !joined.isEmpty else { return [] }
        return joined.split(separator: ",").map(String.init)
    }

    /// Encodes the ordered category set for storage, deduplicated
    /// (category-management D5) with first-seen order preserved.
    /// Internal (not private): the sync extension in
    /// `LocalStorePlannerSync.swift` shares these helpers.
    static func joinPlannerCategoryIDs(_ ids: [String]) -> String {
        Self.deduplicate(ids).joined(separator: ",")
    }

    /// All planner tasks in the shared display order
    /// (`position_key`, `id` — byte-wise, matching the relay).
    func plannerTasks() throws -> [PlannerTask] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM planner_tasks ORDER BY position_key, id
                """)
            return rows.map { Self.plannerTask(from: $0) }
        }
    }

    /// One planner task by id, or nil.
    func plannerTask(id: String) throws -> PlannerTask? {
        try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM planner_tasks WHERE id = ?
                """, arguments: [id]) else { return nil }
            return Self.plannerTask(from: row)
        }
    }

    /// Creates a planner task (appended at `positionKey`, allocated by the
    /// caller between its neighbors) plus its outbox create row in one
    /// transaction. Names follow the shared timer-name rule; identical
    /// names are separate identities. New tasks carry no categories —
    /// the editor sheet tags them afterwards through the retag intent.
    /// Returns `.invalid` without writing when the name is empty or too long.
    func createPlannerTask(
        id: String,
        name: String,
        positionKey: String,
        operationID: String,
        now: Date = Date()
    ) throws -> PlannerMutation {
        let trimmed = ActivityName.normalized(name)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        guard PlannerPositionKey.validate(positionKey) else { return .failure }
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            let task = PlannerTask(
                id: id, name: trimmed, positionKey: positionKey,
                createdAt: stamped, updatedAt: stamped
            )
            do {
                try db.execute(
                    sql: """
                        INSERT INTO planner_tasks (id, name, category_ids, position_key, completed_on, created_at, updated_at)
                        VALUES (?, ?, ?, ?, NULL, ?, ?)
                        """,
                    arguments: [task.id, task.name, Self.joinPlannerCategoryIDs(task.categoryIDs), task.positionKey, task.createdAt, task.updatedAt]
                )
            } catch {
                return .failure
            }
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "create", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.create.rawValue,
                                       name: task.name, positionKey: task.positionKey
                                   ))
            return .saved(task)
        }
    }

    /// Renames a planner task plus its outbox row in one transaction.
    /// A rename never changes the position, completion, or any timer/entry.
    /// Unchanged names enqueue nothing.
    func renamePlannerTask(id: String, name: String, operationID: String, now: Date = Date()) throws -> PlannerMutation {
        let trimmed = ActivityName.normalized(name)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            guard task.name != trimmed else { return .saved(task) }
            task.name = trimmed
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.rename.rawValue,
                                       name: task.name
                                   ))
            return .saved(task)
        }
    }

    /// Replaces a planner task's ordered category set plus its outbox row
    /// in one transaction (the `retag` field intent — its own revision and
    /// acceptance, like rename). A retag never changes the name, position,
    /// completion, or any timer/entry. Unchanged sets enqueue nothing.
    func retagPlannerTask(id: String, categoryIDs: [String], operationID: String, now: Date = Date()) throws -> PlannerMutation {
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            let deduped = Self.deduplicate(categoryIDs)
            guard task.categoryIDs != deduped else { return .saved(task) }
            task.categoryIDs = deduped
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.retag.rawValue,
                                       categoryIDs: task.categoryIDs
                                   ))
            return .saved(task)
        }
    }

    /// Moves a planner task to `positionKey` plus its outbox row in one
    /// transaction. Unchanged keys enqueue nothing.
    func movePlannerTask(id: String, positionKey: String, operationID: String, now: Date = Date()) throws -> PlannerMutation {
        guard PlannerPositionKey.validate(positionKey) else { return .failure }
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            guard task.positionKey != positionKey else { return .saved(task) }
            task.positionKey = positionKey
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.move.rawValue,
                                       positionKey: task.positionKey
                                   ))
            return .saved(task)
        }
    }

    /// Completes a planner task for `completedOn` (a civil `YYYY-MM-DD`
    /// date) plus its outbox row in one transaction. Position is kept;
    /// no timer starts and no entry is created or modified.
    func completePlannerTask(id: String, completedOn: String, operationID: String, now: Date = Date()) throws -> PlannerMutation {
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            guard task.completedOn != completedOn else { return .saved(task) }
            task.completedOn = completedOn
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.complete.rawValue,
                                       completedOn: completedOn
                                   ))
            return .saved(task)
        }
    }

    /// Reopens a planner task (clears the completion date, keeps the
    /// position) plus its outbox row in one transaction. The linked entry,
    /// if any, is unchanged.
    func reopenPlannerTask(id: String, operationID: String, now: Date = Date()) throws -> PlannerMutation {
        let stamped = Self.storageQuantized(now)
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            guard task.completedOn != nil else { return .saved(task) }
            task.completedOn = nil
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.reopen.rawValue
                                   ))
            return .saved(task)
        }
    }

    /// One local planner delete that is undoable until its push succeeds
    /// (buffered deletions push on the next sync; cold launch stays the
    /// backstop). Removes the task in ONE transaction with the buffer
    /// insert. NO outbox row is created while the deletion is buffered.
    func deletePlannerTaskUndoable(
        id: String,
        deletedAt: Date = Date()
    ) throws -> PlannerDelete {
        try queue.write { db in
            guard let task = try Self.fetchPlannerTask(db, id: id) else {
                return .missing
            }
            let payload = String(data: try JSONEncoder().encode(DeletionSnapshot(records: [
                DeletionSnapshot.Record(
                    resource: Self.plannerResource,
                    recordID: task.id,
                    data: try JSONEncoder().encode(task)
                ),
            ])), encoding: .utf8)
            do {
                try db.execute(
                    sql: """
                        INSERT INTO undo_buffer (id, payload, deleted_at) VALUES (?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, payload, deletedAt]
                )
                try db.execute(sql: "DELETE FROM planner_tasks WHERE id = ?", arguments: [id])
            } catch {
                return .failure
            }
            return .deleted(task)
        }
    }

    /// Decodes the planner-deletion snapshot held in a buffer row. Returns
    /// nil when the row does not exist or does not carry a planner-OWNED
    /// deletion (ownership is exclusive — entry/category rows are left for
    /// their owners).
    func plannerTaskDeletionSnapshot(bufferID: String) throws -> PlannerTask? {
        try queue.read { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == Self.plannerResource else { return nil }
            guard let record = snapshot.records.first(where: { $0.resource == Self.plannerResource }) else {
                return nil
            }
            return try JSONDecoder().decode(PlannerTask.self, from: record.data)
        }
    }

    /// Undoes a planner-task deletion: re-inserts the task and removes the
    /// buffer row in one transaction. No outbox row is ever created, so
    /// the relay is never notified of the deletion. Refuses with
    /// `UndoError.pushInFlight` while a buffered-deletion push is in flight.
    @discardableResult
    func undoPlannerTaskDeletion(bufferID: String) throws -> PlannerTask? {
        guard !undoPushInFlight else { throw UndoError.pushInFlight }
        return try queue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == Self.plannerResource else { return nil }
            guard let record = snapshot.records.first(where: { $0.resource == Self.plannerResource }) else {
                return nil
            }
            let task = try JSONDecoder().decode(PlannerTask.self, from: record.data)
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO planner_tasks (id, name, category_ids, position_key, completed_on, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [task.id, task.name, Self.joinPlannerCategoryIDs(task.categoryIDs), task.positionKey, task.completedOn, task.createdAt, task.updatedAt]
            )
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [bufferID])
            return task
        }
    }

    /// Fetches one planner task row inside a write transaction.
    private static func fetchPlannerTask(_ db: Database, id: String) throws -> PlannerTask? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM planner_tasks WHERE id = ?
            """, arguments: [id]) else { return nil }
        return plannerTask(from: row)
    }

    /// Rewrites a planner task row (the caller owns the transaction and the
    /// outbox row).
    private static func writePlannerTask(_ db: Database, _ task: PlannerTask) throws {
        try db.execute(
            sql: """
                UPDATE planner_tasks
                SET name = ?, category_ids = ?, position_key = ?, completed_on = ?, updated_at = ?
                WHERE id = ?
                """,
            arguments: [task.name, Self.joinPlannerCategoryIDs(task.categoryIDs), task.positionKey, task.completedOn, task.updatedAt, task.id]
        )
    }
}
