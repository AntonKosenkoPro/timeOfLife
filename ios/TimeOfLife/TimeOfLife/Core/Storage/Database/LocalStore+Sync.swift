import GRDB
import Foundation

/// Category, activity, and entry CRUD + specialized queries.
extension LocalStore {

    // MARK: - Category CRUD

    /// Returns all visible categories (not deleted, not undo-hidden),
    /// ordered by name ascending.
    func categoriesSortedByName() throws -> [Category] {
        try dbQueue.read { db in
            let records = try CategoryRecord
                .filter(
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("name").asc)
                .fetchAll(db)
            return records.map { $0.toModel() }
        }
    }

    /// Returns a single category by id, regardless of visibility flags.
    func category(id: String) throws -> Category? {
        try dbQueue.read { db in
            try CategoryRecord
                .filter(key: id)
                .fetchOne(db)?
                .toModel()
        }
    }

    /// Case-insensitive, normalized name lookup for collision detection.
    func category(normalizedName: String) throws -> Category? {
        try dbQueue.read { db in
            let records = try CategoryRecord
                .filter(
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchAll(db)
            return records
                .first { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName }?
                .toModel()
        }
    }

    /// Upserts a category (insert or replace by id).
    func upsertCategory(_ category: Category) throws {
        try dbQueue.write { db in
            var catRec = CategoryRecord.from(category); try catRec.save(db)
        }
    }

    /// Deletes a category hard (physical delete) — used for collision remap.
    func hardDeleteCategory(id: String) throws {
        try dbQueue.write { db in
            _ = try CategoryRecord.filter(key: id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("category_id") == id)
                .deleteAll(db)
        }
    }

    // MARK: - Activity CRUD

    /// Returns all visible activities (not deleted, not undo-hidden),
    /// ordered by `last_used_at` descending with a deterministic name
    /// tie-break for equal timestamps.
    func activitiesSortedByLastUsedAt() throws -> [Activity] {
        try dbQueue.read { db in
            let records = try ActivityRecord
                .filter(
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("last_used_at").desc, Column("name").asc)
                .fetchAll(db)
            return try records.map { try loadActivityModel(db, record: $0) }
        }
    }

    /// Returns up to `limit` visible activities ordered by `last_used_at`
    /// descending (name tie-break) — the timer suggestion query (F5).
    ///
    /// Unlike `activitiesSortedByLastUsedAt`, this loads category joins in a
    /// single `IN` query so ranking stays well under the 50 ms budget for
    /// 1,000+ activities (AC10).
    func suggestionActivities(limit: Int) throws -> [Activity] {
        try dbQueue.read { db in
            let records = try ActivityRecord
                .filter(
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("last_used_at").desc, Column("name").asc)
                .limit(limit)
                .fetchAll(db)
            guard !records.isEmpty else { return [] }
            let ids = records.map(\.id)
            let joins = try ActivityCategoryRecord
                .filter(ids.contains(Column("activity_id")))
                .order(Column("activity_id").asc, Column("position").asc)
                .fetchAll(db)
            let joinsByActivity = Dictionary(grouping: joins, by: \.activityId)
            return records.map { record in
                let categoryIds = joinsByActivity[record.id]?.map(\.categoryId) ?? []
                return record.toModel(categoryIds: categoryIds)
            }
        }
    }

    /// Returns a single activity by id, regardless of visibility flags.
    func activity(id: String) throws -> Activity? {
        try dbQueue.read { db in
            guard let record = try ActivityRecord.filter(key: id).fetchOne(db) else {
                return nil
            }
            return try loadActivityModel(db, record: record)
        }
    }

    /// Case-insensitive, normalized name lookup for collision detection.
    func activity(normalizedName: String) throws -> Activity? {
        try dbQueue.read { db in
            let records = try ActivityRecord
                .filter(
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchAll(db)
            return try records
                .first { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName }
                .map { try loadActivityModel(db, record: $0) }
        }
    }

    /// Upserts an activity and its category-tag relationships.
    func upsertActivity(_ activity: Activity) throws {
        try dbQueue.write { db in
            var actRec = ActivityRecord.from(activity); try actRec.save(db)
            try replaceActivityCategories(
                db, activityId: activity.id, categoryIds: activity.categoryIds)
        }
    }

    /// Hard-deletes an activity and cascades to entries + join rows.
    func hardDeleteActivity(id: String) throws {
        try dbQueue.write { db in
            _ = try EntryRecord.filter(Column("activity_id") == id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("activity_id") == id).deleteAll(db)
            _ = try ActivityRecord.filter(key: id).deleteAll(db)
        }
    }

    // MARK: - Entry CRUD

    /// Returns all visible entries for the given activity, ordered by
    /// `(started_at DESC, id DESC)`.
    func entries(forActivityId activityId: String) throws -> [Entry] {
        try dbQueue.read { db in
            let records = try EntryRecord
                .filter(
                    Column("activity_id") == activityId &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("started_at").desc, Column("id").desc)
                .fetchAll(db)
            return records.map { $0.toModel() }
        }
    }

    /// Returns a single entry by id, regardless of visibility flags.
    func entry(id: String) throws -> Entry? {
        try dbQueue.read { db in
            try EntryRecord.filter(key: id).fetchOne(db)?.toModel()
        }
    }

    /// Returns the count of visible entries for the given activity.
    func entryCount(forActivityId activityId: String) throws -> Int {
        try dbQueue.read { db in
            try EntryRecord
                .filter(
                    Column("activity_id") == activityId &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .fetchCount(db)
        }
    }

    /// Returns the newest visible entry for the given activity, deterministically
    /// ordered by `(started_at DESC, id DESC)`.
    func latestEntry(forActivityId activityId: String) throws -> Entry? {
        try dbQueue.read { db in
            try EntryRecord
                .filter(
                    Column("activity_id") == activityId &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("started_at").desc, Column("id").desc)
                .fetchOne(db)?
                .toModel()
        }
    }

    /// Upserts an entry.
    func upsertEntry(_ entry: Entry) throws {
        try dbQueue.write { db in
            var entRec = EntryRecord.from(entry); try entRec.save(db)
        }
    }

    /// Hard-deletes an entry.
    func hardDeleteEntry(id: String) throws {
        try dbQueue.write { db in
            _ = try EntryRecord.filter(key: id).deleteAll(db)
        }
    }

    // MARK: - Undo snapshot queries

    /// Returns the ids of all visible entries for the given activity, in
    /// `(started_at DESC, id DESC)` order. Used to build an undo snapshot
    /// for a whole-activity deletion.
    func entryIds(forActivityId activityId: String) throws -> [String] {
        try dbQueue.read { db in
            try EntryRecord
                .filter(
                    Column("activity_id") == activityId &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("started_at").desc, Column("id").desc)
                .fetchAll(db)
                .map(\.id)
        }
    }

    /// Returns the `activity_categories` join rows for the given category,
    /// used to build an undo snapshot for a category deletion.
    func categoryJoins(forCategoryId categoryId: String) throws -> [UndoHold.CategoryJoinSnapshot] {
        try dbQueue.read { db in
            try ActivityCategoryRecord
                .filter(Column("category_id") == categoryId)
                .order(Column("position").asc)
                .fetchAll(db)
                .map {
                    UndoHold.CategoryJoinSnapshot(
                        activityId: $0.activityId,
                        categoryId: $0.categoryId,
                        position: $0.position)
                }
        }
    }

    /// Returns the newest visible entry id for the given activity,
    /// deterministically ordered by `(started_at DESC, id DESC)`.
    func latestEntryId(forActivityId activityId: String) throws -> String? {
        try dbQueue.read { db in
            try EntryRecord
                .filter(
                    Column("activity_id") == activityId &&
                    Column(SyncMetadataColumns.isDeleted) == 0 &&
                    Column(SyncMetadataColumns.isUndoHidden) == 0)
                .order(Column("started_at").desc, Column("id").desc)
                .fetchOne(db)?
                .id
        }
    }
}
