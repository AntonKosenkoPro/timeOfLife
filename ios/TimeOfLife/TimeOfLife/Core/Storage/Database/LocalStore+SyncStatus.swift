import GRDB
import Foundation

/// Pending/blocked queries, collision remapping, and sync-status updates.
extension LocalStore {

    // MARK: - Pending / blocked queries

    /// Returns all pending categories (in dependency order: creates/updates
    /// first, then deletes). Excludes undo-hidden records.
    func pendingCategories() throws -> (createsUpdates: [Category], deletes: [Category]) {
        try dbQueue.read { db in
            let records = try CategoryRecord
                .filter(
                    Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchAll(db)
            var createsUpdates: [Category] = []
            var deletes: [Category] = []
            for record in records {
                let model = record.toModel()
                if model.sync.isDeleted {
                    deletes.append(model)
                } else {
                    createsUpdates.append(model)
                }
            }
            return (createsUpdates, deletes)
        }
    }

    /// Returns all pending activities (in dependency order: creates/updates
    /// first, then deletes). Excludes undo-hidden records.
    func pendingActivities() throws -> (createsUpdates: [Activity], deletes: [Activity]) {
        try dbQueue.read { db in
            let records = try ActivityRecord
                .filter(
                    Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchAll(db)
            var createsUpdates: [Activity] = []
            var deletes: [Activity] = []
            for record in records {
                let model = try loadActivityModel(db, record: record)
                if model.sync.isDeleted {
                    deletes.append(model)
                } else {
                    createsUpdates.append(model)
                }
            }
            return (createsUpdates, deletes)
        }
    }

    /// Returns all pending entries (in dependency order: creates/updates
    /// first, then deletes). Excludes undo-hidden records.
    func pendingEntries() throws -> (createsUpdates: [Entry], deletes: [Entry]) {
        try dbQueue.read { db in
            let records = try EntryRecord
                .filter(
                    Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchAll(db)
            var createsUpdates: [Entry] = []
            var deletes: [Entry] = []
            for record in records {
                let model = record.toModel()
                if model.sync.isDeleted {
                    deletes.append(model)
                } else {
                    createsUpdates.append(model)
                }
            }
            return (createsUpdates, deletes)
        }
    }

    /// Returns `true` if any of the given category ids has a pending (not yet
    /// created on the server) local create. Used to defer dependent activity
    /// pushes until their category tags exist server-side.
    func hasPendingCategoryCreate(for categoryIds: [String]) throws -> Bool {
        guard !categoryIds.isEmpty else { return false }
        let count = try dbQueue.read { db in
            try CategoryRecord
                .filter(
                    categoryIds.contains(Column("id")) &&
                    Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.remoteKnown) == 0)
                .fetchCount(db)
        }
        return count > 0
    }

    /// Returns all blocked records (categories, activities, entries).
    func blockedRecords() throws -> (categories: [Category], activities: [Activity], entries: [Entry]) {
        try dbQueue.read { db in
            let catRecords = try CategoryRecord
                .filter(Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue)
                .fetchAll(db)
            let actRecords = try ActivityRecord
                .filter(Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue)
                .fetchAll(db)
            let entRecords = try EntryRecord
                .filter(Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue)
                .fetchAll(db)
            var activities: [Activity] = []
            for record in actRecords {
                activities.append(try loadActivityModel(db, record: record))
            }
            return (
                catRecords.map { $0.toModel() },
                activities,
                entRecords.map { $0.toModel() }
            )
        }
    }

    // MARK: - Transactional collision remapping

    /// Transactionally replaces a losing activity with the winner, rewriting
    /// all references (entries, activity_categories) in one atomic step.
    func remapActivityId(loserId: String, winnerId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE entries SET activity_id = ? WHERE activity_id = ?",
                arguments: [winnerId, loserId])
            _ = try ActivityCategoryRecord
                .filter(Column("activity_id") == loserId).deleteAll(db)
            _ = try ActivityRecord.filter(key: loserId).deleteAll(db)
        }
    }

    /// Transactionally replaces a losing category with the winner, rewriting
    /// `activity_categories` rows in one atomic step. Entries are unaffected.
    ///
    /// After the remap, per-activity positions are re-assigned sequentially so
    /// the tag order shown in the editor stays gap-free and matches the user's
    /// original ordering (the surviving winner row keeps its old position,
    /// which would otherwise leave gaps and drift the order).
    func remapCategoryId(loserId: String, winnerId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM activity_categories
                WHERE category_id = ?
                  AND activity_id IN (
                      SELECT activity_id FROM activity_categories WHERE category_id = ?
                  )
                """,
                arguments: [loserId, winnerId])
            try db.execute(
                sql: "UPDATE activity_categories SET category_id = ? WHERE category_id = ?",
                arguments: [winnerId, loserId])
            _ = try CategoryRecord.filter(key: loserId).deleteAll(db)

            // Renumber positions per activity so the join table stays gap-free
            // and ordered exactly as the user originally tagged.
            let affected = try ActivityCategoryRecord
                .filter(Column("category_id") == winnerId)
                .fetchAll(db)
            let activities = Set(affected.map(\.activityId))
            for activityId in activities {
                let joins = try ActivityCategoryRecord
                    .filter(Column("activity_id") == activityId)
                    .order(Column("position").asc)
                    .fetchAll(db)
                for (newPosition, join) in joins.enumerated()
                where join.position != newPosition {
                    var updated = join
                    updated.position = newPosition
                    try updated.save(db)
                }
            }
        }
    }

    // MARK: - Mark clean / blocked

    /// Marks a category as clean (successfully synced) and clears any error.
    func markCategoryClean(id: String) throws {
        try updateSyncStatus(table: "categories", id: id, status: .clean, clearError: true, setRemoteKnown: true)
    }

    /// Marks an activity as clean and clears any error.
    func markActivityClean(id: String) throws {
        try updateSyncStatus(table: "activities", id: id, status: .clean, clearError: true, setRemoteKnown: true)
    }

    /// Marks an entry as clean and clears any error.
    func markEntryClean(id: String) throws {
        try updateSyncStatus(table: "entries", id: id, status: .clean, clearError: true, setRemoteKnown: true)
    }

    /// Marks a category as blocked with the given server error.
    func markCategoryBlocked(id: String, code: String, message: String) throws {
        try updateSyncStatus(table: "categories", id: id, status: .blocked, clearError: false, setRemoteKnown: false, errorCode: code, errorMessage: message)
    }

    /// Marks an activity as blocked with the given server error.
    func markActivityBlocked(id: String, code: String, message: String) throws {
        try updateSyncStatus(table: "activities", id: id, status: .blocked, clearError: false, setRemoteKnown: false, errorCode: code, errorMessage: message)
    }

    /// Marks an entry as blocked with the given server error.
    func markEntryBlocked(id: String, code: String, message: String) throws {
        try updateSyncStatus(table: "entries", id: id, status: .blocked, clearError: false, setRemoteKnown: false, errorCode: code, errorMessage: message)
    }

    // MARK: - Complete deletion (after successful DELETE)

    /// Completes a pending activity deletion: hard-deletes the activity and
    /// cascades to entries + join rows.
    func completeActivityDeletion(id: String) throws {
        try hardDeleteActivity(id: id)
    }

    /// Completes a pending category deletion: hard-deletes the category and
    /// its join rows (entries unaffected).
    func completeCategoryDeletion(id: String) throws {
        try hardDeleteCategory(id: id)
    }

    /// Completes a pending entry deletion: hard-deletes the entry.
    func completeEntryDeletion(id: String) throws {
        try hardDeleteEntry(id: id)
    }

    // MARK: - Private

    /// The synchronizable tables `updateSyncStatus` may touch. This is the
    /// allow-list backing the interpolated `UPDATE` statement — no other
    /// table name is ever accepted.
    private static let syncStatusTables: Set<String> = ["categories", "activities", "entries"]

    /// Shared SQL for updating sync status on a single record.
    private func updateSyncStatus(
        table: String,
        id: String,
        status: SyncStatus,
        clearError: Bool,
        setRemoteKnown: Bool,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) throws {
        guard Self.syncStatusTables.contains(table) else {
            assertionFailure("updateSyncStatus called with unexpected table: \(table)")
            return
        }
        try dbQueue.write { db in
            var sql = "UPDATE \(table) SET \(SyncMetadataColumns.syncStatus) = ?"
            var args: [DatabaseValueConvertible] = [status.rawValue]
            if setRemoteKnown {
                sql += ", \(SyncMetadataColumns.remoteKnown) = 1"
            }
            if clearError {
                sql += ", \(SyncMetadataColumns.syncErrorCode) = NULL"
                sql += ", \(SyncMetadataColumns.syncErrorMessage) = NULL"
            } else {
                // Nil payloads persist as SQL NULL, not empty strings, so a
                // "blocked with no error" record does not round-trip as a
                // non-nil empty error.
                sql += ", \(SyncMetadataColumns.syncErrorCode) = ?"
                sql += ", \(SyncMetadataColumns.syncErrorMessage) = ?"
                args.append(errorCode ?? DatabaseValue.null)
                args.append(errorMessage ?? DatabaseValue.null)
            }
            sql += " WHERE id = ?"
            args.append(id)
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }
}
