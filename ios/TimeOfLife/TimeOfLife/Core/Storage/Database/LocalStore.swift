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
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: configuration)
        try dbQueue.write { db in
            try DatabaseSchema.migrate(db)
        }
    }

    /// Creates an in-memory store for tests that don't need durability.
    init(inMemory: Bool = true) throws {
        precondition(inMemory, "Use init(databaseURL:) for a file-backed store")
        self.dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try DatabaseSchema.migrate(db)
        }
    }

    // MARK: - Account lifecycle

    /// Closes the database. Called during account switch before opening the
    /// next account's database.
    func close() {
        // `DatabaseQueue` releases its connection when deallocated; nothing
        // to do here explicitly. The actor keeps the queue alive until the
        // caller drops its reference.
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
    func replaceActivityCategories(
        _ db: Database,
        activityId: String,
        categoryIds: [String]
    ) throws {
        _ = try ActivityCategoryRecord
            .filter(Column("activity_id") == activityId)
            .deleteAll(db)
        for (index, categoryId) in categoryIds.enumerated() {
            var join = ActivityCategoryRecord(
                activityId: activityId,
                categoryId: categoryId,
                position: index)
            try join.save(db)
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
