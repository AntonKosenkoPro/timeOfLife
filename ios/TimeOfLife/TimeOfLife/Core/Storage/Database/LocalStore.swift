import GRDB
import Foundation

/// A snapshot of categories, activities, and entries fetched from the server,
/// staged before being merged in one transaction.
struct ServerSnapshot: Sendable {
    var categories: [CategoryDTO]
    var activities: [ActivityDTO]
    var entries: [EntryDTO]
}

/// The result of adopting a canonical server response for a single record.
struct AdoptionResult<T: Sendable>: Sendable {
    /// The adopted domain model, or `nil` if the local revision is newer.
    let model: T?
    /// `true` if the local record was stale and was overwritten.
    let didOverwrite: Bool
}

/// Optional synchronous seed used by deterministic DEBUG UI composition.
struct LocalStoreSeed: Sendable {
    let categories: [Category]
    let activities: [Activity]
    let entries: [Entry]
}

/// The sole owner of catalog and entry persistence.
///
/// One actor-backed `DatabaseQueue` per authenticated user. All multi-record
/// mutations execute inside a single SQLite transaction so the database is
/// never left in a partial state on crash. Views and view models never
/// import GRDB or touch the database directly — they go through this actor.
actor LocalStore {

    /// The GRDB queue. `internal` so same-module extensions can access it.
    let dbQueue: DatabaseQueue

    /// Opens (or creates) the per-account database at the given URL and runs
    /// the initial migration.
    /// - Parameter url: The `file:` URL returned by `AccountDatabasePath`.
    /// - Throws: `DatabaseError` if the file cannot be opened or migrated.
    init(databaseURL url: URL) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        // A busy timeout serializes access when a previous queue for the same
        // file is still being torn down (e.g. re-login as the same user
        // before the old actor is fully deallocated).
        configuration.busyMode = .timeout(2.0)
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: configuration)
        try dbQueue.write { db in
            try DatabaseSchema.migrate(db)
        }
    }

    /// Creates an in-memory store for tests that don't need durability.
    init(inMemory: Bool = true, seed: LocalStoreSeed? = nil) throws {
        precondition(inMemory, "Use init(databaseURL:) for a file-backed store")
        self.dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try DatabaseSchema.migrate(db)
            guard let seed else { return }

            for category in seed.categories {
                var record = CategoryRecord.from(category)
                try record.save(db)
            }
            for activity in seed.activities {
                var record = ActivityRecord.from(activity)
                try record.save(db)
                for (position, categoryId) in activity.categoryIds.enumerated() {
                    var join = ActivityCategoryRecord(
                        activityId: activity.id,
                        categoryId: categoryId,
                        position: position)
                    try join.save(db)
                }
            }
            for entry in seed.entries {
                var record = EntryRecord.from(entry)
                try record.save(db)
            }
        }
    }

    // MARK: - Account lifecycle

    /// Closes the database connection. Called during account switch before
    /// opening the next account's database.
    ///
    /// After a successful close, every further database access on this store
    /// throws `SQLITE_MISUSE` (GRDB contract), so callers must drop the
    /// store reference immediately after closing.
    func close() {
        try? dbQueue.close()
    }

    // MARK: - Metadata

    /// Reads a metadata value for the given key.
    func metadataValue(forKey key: String) throws -> String? {
        try dbQueue.read { db in
            try MetadataRecord
                .filter(Column("key") == key)
                .fetchOne(db)?
                .value
        }
    }

    /// Writes a metadata value.
    func setMetadataValue(_ value: String, forKey key: String) throws {
        try dbQueue.write { db in
            var record = MetadataRecord(key: key, value: value)
            try record.save(db)
        }
    }

    // MARK: - Undo hold

    /// Writes a single undo-hold row, replacing any existing one.
    func setUndoHold(_ record: UndoHoldRecord) throws {
        try dbQueue.write { db in
            _ = try UndoHoldRecord.deleteAll(db)
            var rec = record
            try rec.save(db)
        }
    }

    /// Returns the current undo-hold row, or `nil` if none.
    func currentUndoHold() throws -> UndoHoldRecord? {
        try dbQueue.read { db in
            try UndoHoldRecord.fetchOne(db)
        }
    }

    /// Clears the undo-hold row (no payload change).
    func clearUndoHold() throws {
        try dbQueue.write { db in
            _ = try UndoHoldRecord.deleteAll(db)
        }
    }

    // MARK: - Internal helpers (used by extensions in other files)

    /// Loads the full activity model including its category ids.
    func loadActivityModel(_ db: Database, record: ActivityRecord) throws -> Activity {
        let joins = try ActivityCategoryRecord
            .filter(Column("activity_id") == record.id)
            .order(Column("position").asc)
            .fetchAll(db)
        let categoryIds = joins.map(\.categoryId)
        return record.toModel(categoryIds: categoryIds)
    }

    /// Replaces all `activity_categories` rows for the given activity.
    ///
    /// Tag ids that reference a category missing from the local store are
    /// skipped rather than inserted — the category may have been deleted on
    /// the server between the snapshot's category fetch and this merge, and
    /// a dangling join row would violate the FK and abort the entire
    /// reconciliation transaction.
    func replaceActivityCategories(
        _ db: Database,
        activityId: String,
        categoryIds: [String]
    ) throws {
        _ = try ActivityCategoryRecord
            .filter(Column("activity_id") == activityId)
            .deleteAll(db)
        var position = 0
        for categoryId in categoryIds {
            guard try CategoryRecord.filter(key: categoryId).fetchOne(db) != nil else {
                continue
            }
            var join = ActivityCategoryRecord(
                activityId: activityId,
                categoryId: categoryId,
                position: position)
            try join.save(db)
            position += 1
        }
    }
}

// MARK: - String primary-key filter helpers

extension ActivityRecord {
    static func filter(key id: String) -> QueryInterfaceRequest<ActivityRecord> {
        filter(Column("id") == id)
    }
}

extension CategoryRecord {
    static func filter(key id: String) -> QueryInterfaceRequest<CategoryRecord> {
        filter(Column("id") == id)
    }
}

extension EntryRecord {
    static func filter(key id: String) -> QueryInterfaceRequest<EntryRecord> {
        filter(Column("id") == id)
    }
}
