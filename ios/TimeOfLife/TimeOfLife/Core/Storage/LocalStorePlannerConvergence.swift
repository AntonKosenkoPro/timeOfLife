import Foundation
import GRDB

// MARK: - Planner linked-run convergence (day-planner 15.2)

/// One editor-sheet save: the validated name, the ordered category set, and
/// the notes, each with its own outbox operation id (a changed field sends
/// its intent; an unchanged field sends nothing).
struct PlannerSheetWrite: Sendable {
    var name: String
    var categoryIDs: [String]
    var notes: String
    var renameOperationID: String
    var retagOperationID: String
    var notesOperationID: String
}

/// `LocalStore` planner convergence surface: the live bidirectional
/// write-through between the running draft and its linked task. Every
/// method commits the draft and the task change in the SAME chokepoint
/// transaction with no extra outbox rows beyond the field intents and no
/// draft-sync row (drafts never sync). CRUD and undo live in
/// `LocalStorePlanner.swift`; the helpers there are shared.
extension LocalStore {
    /// Which sheet fields changed (drives the row rewrite and the draft
    /// write-through).
    private struct SheetDirty: Equatable {
        /// Any field changed (the row rewrite + timestamp bump gate).
        var touched = false
        /// A live draft field (categories or notes) changed (the draft
        /// write-through gate — a name-only edit leaves the draft
        /// untouched).
        var liveFieldsChanged = false
    }

    /// Rewrites the running draft's live category snapshot and — when the
    /// run is linked to an existing planner task — the task's ordered set
    /// in the SAME chokepoint transaction, enqueueing the single `retag`
    /// outbox row (Track→task direction). The locked draft text, notes,
    /// and `started_at` are untouched; no draft-sync row is ever queued
    /// (drafts never sync). A missing draft is a no-op; a missing task
    /// still rewrites the draft (time capture never fails for the
    /// planner). Unchanged sets enqueue nothing (retag parity).
    func updateRunningDraftCategories(_ categoryIDs: [String], operationID: String, now: Date = Date()) throws {
        let joined = Self.deduplicate(categoryIDs).joined(separator: ",")
        let stamped = Self.storageQuantized(now)
        try queue.write { db in
            try db.execute(
                sql: "UPDATE timer_state SET category_ids = ? WHERE id = 'singleton'",
                arguments: [joined]
            )
            guard db.changesCount > 0 else { return }
            let link: String? = try String.fetchOne(db, sql: """
                SELECT planner_task_id FROM timer_state WHERE id = 'singleton'
                """)
            guard let link, var task = try Self.fetchPlannerTask(db, id: link) else { return }
            let deduped = Self.deduplicate(categoryIDs)
            guard task.categoryIDs != deduped else { return }
            task.categoryIDs = deduped
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.retag.rawValue,
                                       categoryIDs: task.categoryIDs
                                   ))
        }
    }

    /// Rewrites the running draft's live notes snapshot and — when the run
    /// is linked to an existing planner task — the task's notes in the
    /// SAME chokepoint transaction, enqueueing the single `notes` outbox
    /// row (Track→task direction). The locked draft text, categories, and
    /// `started_at` are untouched; no draft-sync row is ever queued. A
    /// missing draft is a no-op; a missing task still rewrites the draft.
    /// Unchanged notes enqueue nothing (notes parity). The bound is the
    /// caller's (sheet validity gate) and the relay's; the store keeps the
    /// text verbatim, mirroring entry notes.
    func updateRunningDraftNotes(_ notes: String, operationID: String, now: Date = Date()) throws {
        let stamped = Self.storageQuantized(now)
        try queue.write { db in
            try db.execute(
                sql: "UPDATE timer_state SET notes = ? WHERE id = 'singleton'",
                arguments: [notes]
            )
            guard db.changesCount > 0 else { return }
            let link: String? = try String.fetchOne(db, sql: """
                SELECT planner_task_id FROM timer_state WHERE id = 'singleton'
                """)
            guard let link, var task = try Self.fetchPlannerTask(db, id: link) else { return }
            guard task.notes != notes else { return }
            task.notes = notes
            task.updatedAt = stamped
            try Self.writePlannerTask(db, task)
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: operationID,
                                       taskID: task.id, intent: PlannerIntent.notes.rawValue,
                                       notes: task.notes
                                   ))
        }
    }

    /// Saves the editor sheet's name, ordered categories, and notes for one
    /// task — each changed field as its own outbox intent (`rename`,
    /// `retag`, `notes`; unchanged fields enqueue nothing) — and, when the
    /// task carries the active linked run, rewrites the running draft's
    /// live categories and notes in the SAME chokepoint transaction
    /// (sheet→draft direction). The locked draft name never moves; the
    /// draft's `started_at` is untouched and no draft-sync row is queued.
    /// Position, completion, and every entry stay untouched. Returns
    /// `.invalid` without writing when the name is empty or too long.
    func savePlannerTaskSheet(id: String, write: PlannerSheetWrite, now: Date = Date()) throws -> PlannerMutation {
        let trimmed = ActivityName.normalized(write.name)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        return try queue.write { db in
            guard var task = try Self.fetchPlannerTask(db, id: id) else { return .missing }
            let dirty = try Self.applySheetWrite(db: db, task: &task, write: write, name: trimmed, now: now)
            if dirty.touched {
                try Self.writePlannerTask(db, task)
            }
            if dirty.touched, dirty.liveFieldsChanged {
                try Self.convergeDraftToSheetTask(db: db, taskID: id, task: task)
            }
            return .saved(task)
        }
    }

    /// Applies the changed sheet fields to the task with one outbox row per
    /// field, reporting what changed. An unchanged save applies nothing:
    /// no row rewrite, no timestamp bump, no outbox row.
    private static func applySheetWrite(
        db: Database,
        task: inout PlannerTask,
        write: PlannerSheetWrite,
        name: String,
        now: Date
    ) throws -> SheetDirty {
        let deduped = Self.deduplicate(write.categoryIDs)
        let stamped = Self.storageQuantized(now)
        var dirty = SheetDirty()
        if task.name != name {
            task.name = name
            task.updatedAt = stamped
            dirty.touched = true
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: write.renameOperationID,
                                       taskID: task.id, intent: PlannerIntent.rename.rawValue,
                                       name: task.name
                                   ))
        }
        if task.categoryIDs != deduped {
            task.categoryIDs = deduped
            task.updatedAt = stamped
            dirty.touched = true
            dirty.liveFieldsChanged = true
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: write.retagOperationID,
                                       taskID: task.id, intent: PlannerIntent.retag.rawValue,
                                       categoryIDs: task.categoryIDs
                                   ))
        }
        if task.notes != write.notes {
            task.notes = write.notes
            task.updatedAt = stamped
            dirty.touched = true
            dirty.liveFieldsChanged = true
            try Self.enqueueOutbox(db: db, resource: Self.plannerResource, recordID: task.id,
                                   op: "update", payload: PlannerOperationPayload(
                                       operationID: write.notesOperationID,
                                       taskID: task.id, intent: PlannerIntent.notes.rawValue,
                                       notes: task.notes
                                   ))
        }
        return dirty
    }

    /// Rewrites the linked running draft's live categories and notes from
    /// the saved task (sheet→draft direction). Only runs when the draft's
    /// link points at the saved task; the locked name never moves.
    private static func convergeDraftToSheetTask(db: Database, taskID: String, task: PlannerTask) throws {
        let link: String? = try String.fetchOne(db, sql: """
            SELECT planner_task_id FROM timer_state WHERE id = 'singleton'
            """)
        guard link == taskID else { return }
        try db.execute(
            sql: "UPDATE timer_state SET category_ids = ?, notes = ? WHERE id = 'singleton'",
            arguments: [Self.deduplicate(task.categoryIDs).joined(separator: ","), task.notes]
        )
    }
}
