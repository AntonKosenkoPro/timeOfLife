import GRDB
import Foundation

/// Undo-flow operations: hide records during the 30 s window, undo (restore),
/// and expiry/supersession (convert to durable pending deletion).
///
/// All multi-record mutations execute inside one SQLite transaction (AC7):
/// - During the window, records keep their data and are hidden via
///   `is_undo_hidden`; no remote deletion state is created.
/// - Undo clears the hidden state and removes the hold — no network.
/// - Expiry/supersession/relaunch converts hidden records to
///   `is_deleted = 1` + `sync_status = pending` and clears the hold, so the
///   `SyncCoordinator` picks up the deletion on its next cycle.
extension LocalStore {

    // MARK: - Hold + hide (deletion entry point)

    /// Hides the records for the given hold and writes a single `undo_hold`
    /// row, replacing any existing one (supersession). Records remain on disk,
    /// excluded from user-facing queries via `is_undo_hidden`. No remote
    /// deletion state is created yet.
    ///
    /// The caller must have already validated the records exist.
    func holdForUndo(_ hold: UndoHold) throws {
        try dbQueue.write { db in
            switch hold.type {
            case .activityWithEntries:
                try hideActivityAndEntries(db, activityId: hold.targetId, entryIds: hold.entryIds)
            case .latestEntry:
                try setEntryUndoHidden(db, id: hold.targetId, hidden: true)
            case .category:
                try hideCategoryAndJoins(
                    db, categoryId: hold.targetId, joins: hold.categoryJoins)
            }
            // Replace any existing hold (only the most recent undoable
            // deletion is restorable — U7).
            _ = try UndoHoldRecord.deleteAll(db)
            let record = UndoHoldRecord(
                id: nil,
                holdType: hold.type.rawValue,
                payload: try hold.encodePayload(),
                createdAt: hold.createdAt.timeIntervalSinceReferenceDate,
                expiresAt: hold.expiresAt.timeIntervalSinceReferenceDate)
            var rec = record
            try rec.save(db)
        }
    }

    // MARK: - Undo (restore)

    /// Clears the undo-hidden state for the current hold's records and
    /// removes the hold. No network request is sent.
    ///
    /// Returns the restored hold type so the caller can report it, or `nil`
    /// if there was no active hold.
    @discardableResult
    func performUndo() throws -> UndoHoldType? {
        try dbQueue.write { db in
            guard let record = try UndoHoldRecord.fetchOne(db) else { return nil }
            let hold = try UndoHold.decodePayload(record.payload)
            switch hold.type {
            case .activityWithEntries:
                try unhideActivityAndEntries(
                    db, activityId: hold.targetId, entryIds: hold.entryIds)
            case .latestEntry:
                try setEntryUndoHidden(db, id: hold.targetId, hidden: false)
            case .category:
                try unhideCategoryAndJoins(
                    db, categoryId: hold.targetId, joins: hold.categoryJoins)
            }
            _ = try UndoHoldRecord.deleteAll(db)
            return hold.type
        }
    }

    // MARK: - Expiry / supersession / relaunch

    /// Converts the current hold's hidden records into durable pending
    /// deletion state (`is_deleted = 1`, `sync_status = pending`) and clears
    /// the hold. The `SyncCoordinator` picks up the pending deletes on its
    /// next cycle.
    ///
    /// Returns the hold type that was expired, or `nil` if there was no
    /// active hold.
    @discardableResult
    func expireUndoHold() throws -> UndoHoldType? {
        try dbQueue.write { db in
            guard let record = try UndoHoldRecord.fetchOne(db) else { return nil }
            let hold = try UndoHold.decodePayload(record.payload)
            switch hold.type {
            case .activityWithEntries:
                try commitActivityAndEntriesDeletion(
                    db, activityId: hold.targetId, entryIds: hold.entryIds)
            case .latestEntry:
                try commitEntryDeletion(db, id: hold.targetId)
            case .category:
                try commitCategoryDeletion(
                    db, categoryId: hold.targetId, joins: hold.categoryJoins)
            }
            _ = try UndoHoldRecord.deleteAll(db)
            return hold.type
        }
    }

    /// Returns the current active undo hold, or `nil` if none.
    func currentHold() throws -> UndoHold? {
        try dbQueue.read { db in
            guard let record = try UndoHoldRecord.fetchOne(db) else { return nil }
            return try? UndoHold.decodePayload(record.payload)
        }
    }

    // MARK: - Hide helpers

    private func hideActivityAndEntries(
        _ db: Database, activityId: String, entryIds: [String]
    ) throws {
        try setActivityUndoHidden(db, id: activityId, hidden: true)
        for id in entryIds {
            try setEntryUndoHidden(db, id: id, hidden: true)
        }
    }

    private func hideCategoryAndJoins(
        _ db: Database, categoryId: String, joins: [UndoHold.CategoryJoinSnapshot]
    ) throws {
        try setCategoryUndoHidden(db, id: categoryId, hidden: true)
        // Remove the join rows now (entries unaffected); undo restores them.
        for join in joins {
            _ = try ActivityCategoryRecord
                .filter(
                    Column("activity_id") == join.activityId &&
                    Column("category_id") == join.categoryId)
                .deleteAll(db)
        }
    }

    // MARK: - Unhide helpers

    private func unhideActivityAndEntries(
        _ db: Database, activityId: String, entryIds: [String]
    ) throws {
        try setActivityUndoHidden(db, id: activityId, hidden: false)
        for id in entryIds {
            try setEntryUndoHidden(db, id: id, hidden: false)
        }
    }

    private func unhideCategoryAndJoins(
        _ db: Database, categoryId: String, joins: [UndoHold.CategoryJoinSnapshot]
    ) throws {
        try setCategoryUndoHidden(db, id: categoryId, hidden: false)
        // Restore the join rows.
        for join in joins {
            var record = ActivityCategoryRecord(
                activityId: join.activityId,
                categoryId: join.categoryId,
                position: join.position)
            try record.save(db)
        }
    }

    // MARK: - Commit (expiry) helpers

    private func commitActivityAndEntriesDeletion(
        _ db: Database, activityId: String, entryIds: [String]
    ) throws {
        try markActivityPendingDeletion(db, id: activityId)
        for id in entryIds {
            try markEntryPendingDeletion(db, id: id)
        }
    }

    private func commitEntryDeletion(_ db: Database, id: String) throws {
        try markEntryPendingDeletion(db, id: id)
    }

    private func commitCategoryDeletion(
        _ db: Database, categoryId: String, joins: [UndoHold.CategoryJoinSnapshot]
    ) throws {
        try markCategoryPendingDeletion(db, id: categoryId)
        // Join rows were already removed at hide time; nothing to do here.
    }

    // MARK: - Low-level flag setters

    private func setActivityUndoHidden(_ db: Database, id: String, hidden: Bool) throws {
        try db.execute(
            sql: "UPDATE activities SET \(SyncMetadataColumns.isUndoHidden) = ? WHERE id = ?",
            arguments: [hidden ? 1 : 0, id])
    }

    private func setCategoryUndoHidden(_ db: Database, id: String, hidden: Bool) throws {
        try db.execute(
            sql: "UPDATE categories SET \(SyncMetadataColumns.isUndoHidden) = ? WHERE id = ?",
            arguments: [hidden ? 1 : 0, id])
    }

    private func setEntryUndoHidden(_ db: Database, id: String, hidden: Bool) throws {
        try db.execute(
            sql: "UPDATE entries SET \(SyncMetadataColumns.isUndoHidden) = ? WHERE id = ?",
            arguments: [hidden ? 1 : 0, id])
    }

    private func markActivityPendingDeletion(_ db: Database, id: String) throws {
        try db.execute(
            sql: """
            UPDATE activities SET \
            \(SyncMetadataColumns.isDeleted) = 1, \
            \(SyncMetadataColumns.syncStatus) = ?, \
            \(SyncMetadataColumns.isUndoHidden) = 0, \
            \(SyncMetadataColumns.localRevision) = \(SyncMetadataColumns.localRevision) + 1 \
            WHERE id = ?
            """,
            arguments: [SyncStatus.pending.rawValue, id])
    }

    private func markCategoryPendingDeletion(_ db: Database, id: String) throws {
        try db.execute(
            sql: """
            UPDATE categories SET \
            \(SyncMetadataColumns.isDeleted) = 1, \
            \(SyncMetadataColumns.syncStatus) = ?, \
            \(SyncMetadataColumns.isUndoHidden) = 0, \
            \(SyncMetadataColumns.localRevision) = \(SyncMetadataColumns.localRevision) + 1 \
            WHERE id = ?
            """,
            arguments: [SyncStatus.pending.rawValue, id])
    }

    private func markEntryPendingDeletion(_ db: Database, id: String) throws {
        try db.execute(
            sql: """
            UPDATE entries SET \
            \(SyncMetadataColumns.isDeleted) = 1, \
            \(SyncMetadataColumns.syncStatus) = ?, \
            \(SyncMetadataColumns.isUndoHidden) = 0, \
            \(SyncMetadataColumns.localRevision) = \(SyncMetadataColumns.localRevision) + 1 \
            WHERE id = ?
            """,
            arguments: [SyncStatus.pending.rawValue, id])
    }
}
