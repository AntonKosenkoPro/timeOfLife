import GRDB
import Foundation

/// The initial database schema for the per-account SQLite store.
///
/// One migration creates all tables. Every synchronizable record
/// (`activities`, `categories`, `entries`) carries the same sync-metadata
/// columns so the `SyncCoordinator` can track state uniformly.
enum DatabaseSchema {

    /// Registers and runs the initial migration on the given database.
    /// - Throws: `DatabaseError` if the migration fails.
    static func migrate(_ db: Database) throws {
        try createActivitiesTable(db)
        try createCategoriesTable(db)
        try createActivityCategoriesTable(db)
        try createEntriesTable(db)
        try createUndoHoldTable(db)
        try createMetadataTable(db)
    }

    // MARK: - Table creation

    private static func createActivitiesTable(_ db: Database) throws {
        try db.create(table: "activities", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("notes", .text)
            t.column("last_used_at", .double)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
            addSyncMetadataColumns(to: t)
        }
        try db.create(
            index: "activities_last_used",
            on: "activities",
            columns: ["last_used_at"],
            ifNotExists: true)
    }

    private static func createCategoriesTable(_ db: Database) throws {
        try db.create(table: "categories", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("icon", .text).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
            addSyncMetadataColumns(to: t)
        }
        try db.create(
            index: "categories_name",
            on: "categories",
            columns: ["name"],
            ifNotExists: true)
    }

    private static func createActivityCategoriesTable(_ db: Database) throws {
        try db.create(table: "activity_categories", ifNotExists: true) { t in
            t.column("activity_id", .text).notNull()
                .references("activities", onDelete: .cascade)
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["activity_id", "category_id"])
        }
    }

    private static func createEntriesTable(_ db: Database) throws {
        try db.create(table: "entries", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("activity_id", .text).notNull()
                .references("activities", onDelete: .cascade)
            t.column("started_at", .double).notNull()
            t.column("ended_at", .double)
            t.column("duration_seconds", .double)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
            addSyncMetadataColumns(to: t)
        }
        try db.create(
            index: "entries_started",
            on: "entries",
            columns: ["started_at", "id"],
            ifNotExists: true)
        try db.create(
            index: "entries_activity",
            on: "entries",
            columns: ["activity_id"],
            ifNotExists: true)
    }

    private static func createUndoHoldTable(_ db: Database) throws {
        try db.create(table: "undo_hold", ifNotExists: true) { t in
            t.column("id", .integer).primaryKey(autoincrement: true)
            t.column("hold_type", .text).notNull()
            t.column("payload", .text).notNull()
            t.column("created_at", .double).notNull()
            t.column("expires_at", .double).notNull()
        }
    }

    private static func createMetadataTable(_ db: Database) throws {
        try db.create(table: "metadata", ifNotExists: true) { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
        }
    }

    // MARK: - Shared columns

    /// Adds the sync-metadata columns shared by all synchronizable tables.
    private static func addSyncMetadataColumns(to t: TableDefinition) {
        t.column("remote_known", .integer).notNull().defaults(to: 0)
        t.column("sync_status", .text).notNull().defaults(to: "clean")
        t.column("is_deleted", .integer).notNull().defaults(to: 0)
        t.column("is_undo_hidden", .integer).notNull().defaults(to: 0)
        t.column("local_revision", .integer).notNull().defaults(to: 0)
        t.column("sync_error_code", .text)
        t.column("sync_error_message", .text)
    }
}
