// swiftlint:disable file_length
import Foundation
import GRDB

/// The on-device source of truth (local-first-store spec): a SQLite database
/// in the App Group shared container that the app, widgets, extensions, and
/// lock-screen Controls all read and write cross-process.
///
/// `LocalStore` is the single chokepoint for all mutations: every state
/// change and its outbox row commit in one transaction, so the tables and the
/// "need to push" queue can never drift. No raw GRDB writes are allowed
/// outside this type.
///
/// The database is opened with `.completeUntilFirstUserAuthentication` (the
/// App Group container default), so it is accessible to `alwaysAllowed`
/// lock-screen Control intents after the device has been unlocked at least
/// once since boot.
actor LocalStore {
    /// The App Group shared container identifier (local-first-store spec).
    static let appGroupID = "group.com.antonkosenko.timeoflife"

    /// The database file name inside the App Group container.
    static let databaseFileName = "timeoflife.sqlite"

    /// The database queue. `DatabaseQueue` is sufficient: the app is the only
    /// writer in practice, and cross-process access is serialized by SQLite's
    /// own file locking.
    private let dbQueue: DatabaseQueue

    /// Opens (creating if needed) the database in the App Group container and
    /// migrates it to the latest schema.
    ///
    /// - Parameter url: Override for the database file location. Tests pass a
    ///   temporary URL; production uses the App Group container.
    init(url: URL? = nil) throws {
        let databaseURL = url ?? Self.defaultDatabaseURL()
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Foreign keys are enforced so a delete of an activity cascades to
            // its entries and join rows, mirroring the backend relay.
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator().migrate(dbQueue)
    }

    /// The production database URL inside the App Group shared container.
    static func defaultDatabaseURL() -> URL {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        let base = container ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(databaseFileName)
    }

    // MARK: - Schema

    /// The typed schema (local-first-store spec): state tables (activities,
    /// categories, activity_categories, entries, timer_state), the
    /// transactional outbox, the durable undo buffer, and per-resource sync
    /// cursors.
    static func migrator() -> DatabaseMigrator { // swiftlint:disable:this function_body_length
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "activities") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("notes", .text)
                t.column("last_used_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "activity_categories") { t in
                t.column("activity_id", .text).notNull()
                    .references("activities", onDelete: .cascade)
                t.column("category_id", .text).notNull()
                    .references("categories", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.primaryKey(["activity_id", "category_id"])
            }
            try db.create(table: "entries") { t in
                t.column("id", .text).primaryKey()
                t.column("activity_id", .text).notNull()
                    .references("activities", onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("duration_seconds", .integer)
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("source_ref", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            // Duplicate-import prevention (entry-provenance spec): a source
            // re-sending the same record must not create a duplicate. SQLite
            // has no partial indexes, so the unique index covers all rows and
            // NULL source_ref values are exempt by SQL semantics (NULLs never
            // collide in a UNIQUE index).
            try db.create(indexOn: "entries", columns: ["source", "source_ref"], options: [.unique])
            try db.create(table: "timer_state") { t in
                t.column("id", .text).primaryKey()
                t.column("activity_id", .text)
                t.column("activity_name", .text)
                t.column("started_at", .datetime)
                t.column("status", .text).notNull()
            }
            try db.create(table: "outbox") { t in
                t.column("id", .text).primaryKey()
                t.column("resource", .text).notNull()
                t.column("record_id", .text).notNull()
                t.column("op", .text).notNull()
                t.column("payload", .text)
                t.column("created_at", .datetime).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "undo_buffer") { t in
                t.column("id", .text).primaryKey()
                t.column("payload", .text).notNull()
                t.column("deleted_at", .datetime).notNull()
            }
            try db.create(table: "sync_state") { t in
                t.column("resource", .text).primaryKey()
                t.column("last_synced_at", .datetime)
            }
        }
        return migrator
    }

    // MARK: - Activities

    /// All activities, most-recently-used first (nil last).
    func activities() throws -> [Activity] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.*, GROUP_CONCAT(ac.category_id) AS category_ids
                FROM activities a
                LEFT JOIN activity_categories ac ON ac.activity_id = a.id
                GROUP BY a.id
                ORDER BY (a.last_used_at IS NULL), a.last_used_at DESC, a.updated_at DESC
                """)
            return rows.map { row in
                Activity(
                    id: row["id"],
                    name: row["name"],
                    notes: row["notes"],
                    lastUsedAt: row["last_used_at"],
                    categoryIDs: Self.categoryIDs(from: row["category_ids"]),
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
            }
        }
    }

    /// One activity by id, or nil.
    func activity(id: String) throws -> Activity? {
        try dbQueue.read { db in
            try Self.fetchActivity(db, id: id)
        }
    }

    /// One activity by case-insensitive name, or nil.
    func activity(named name: String) throws -> Activity? {
        try dbQueue.read { db in
            try Self.fetchActivity(db, name: name)
        }
    }

    /// Creates an activity and enqueues the outbox row in one transaction.
    /// Idempotent on `id`: a replay returns the existing record.
    func createActivity(_ activity: Activity) throws {
        try dbQueue.write { db in
            if try Self.fetchActivity(db, id: activity.id) != nil {
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO activities (id, name, notes, last_used_at, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [activity.id, activity.name, activity.notes, activity.lastUsedAt, activity.createdAt, activity.updatedAt]
            )
            try Self.replaceActivityCategories(db: db, activityID: activity.id, categoryIDs: activity.categoryIDs)
            try Self.enqueueOutbox(db: db, resource: "activity", recordID: activity.id,
                                   op: "create", payload: activity)
        }
    }

    /// Applies a last-write-wins update: the write applies only if
    /// `activity.updatedAt` is newer than the stored `updated_at`. Returns
    /// false when the write was stale (the local version is kept).
    @discardableResult
    func updateActivity(_ activity: Activity) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET name = ?, notes = ?, last_used_at = ?, updated_at = ?
                    WHERE id = ? AND updated_at < ?
                    """,
                arguments: [activity.name, activity.notes, activity.lastUsedAt, activity.updatedAt, activity.id, activity.updatedAt]
            )
            guard db.changesCount > 0 else { return false }
            try Self.replaceActivityCategories(db: db, activityID: activity.id, categoryIDs: activity.categoryIDs)
            try Self.enqueueOutbox(db: db, resource: "activity", recordID: activity.id,
                                   op: "update", payload: activity)
            return true
        }
    }

    /// Deletes an activity and its child rows (entries + join rows) in one
    /// transaction, enqueuing a delete outbox row. The outbox row persists
    /// even though the activity row is gone (deletes are first-class).
    func deleteActivity(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE activity_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM activity_categories WHERE activity_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM activities WHERE id = ?", arguments: [id])
            try Self.enqueueOutbox(db: db, resource: "activity", recordID: id, op: "delete", payload: nil)
        }
    }

    /// Upserts a server record during a pull-merge: replaces the local row
    /// (or inserts it) WITHOUT enqueuing an outbox row — the relay already
    /// holds this version. The LWW check is done by the caller
    /// (`SyncController` applies only when `server.updated_at > local.updated_at`).
    func mergeActivity(_ activity: Activity) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activities (id, name, notes, last_used_at, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        notes = excluded.notes,
                        last_used_at = excluded.last_used_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: [activity.id, activity.name, activity.notes, activity.lastUsedAt, activity.createdAt, activity.updatedAt]
            )
            try Self.replaceActivityCategories(db: db, activityID: activity.id, categoryIDs: activity.categoryIDs)
        }
    }

    // MARK: - Categories

    /// All categories, name-ordered.
    func categories() throws -> [Category] {
        try dbQueue.read { db in
            try Category.fetchAll(db, sql: """
                SELECT * FROM categories ORDER BY lower(name)
                """)
        }
    }

    /// One category by id, or nil.
    func category(id: String) throws -> Category? {
        try dbQueue.read { db in
            try Category.fetchOne(db, key: id)
        }
    }

    /// Creates a category and enqueues the outbox row in one transaction.
    /// Idempotent on `id`: a replay returns the existing record.
    func createCategory(_ category: Category) throws {
        try dbQueue.write { db in
            if try Category.fetchOne(db, key: category.id) != nil {
                return
            }
            try category.insert(db)
            try Self.enqueueOutbox(db: db, resource: "category", recordID: category.id,
                                   op: "create", payload: category)
        }
    }

    /// Applies a last-write-wins update. Returns false when stale.
    @discardableResult
    func updateCategory(_ category: Category) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE categories SET name = ?, icon = ?, updated_at = ?
                    WHERE id = ? AND updated_at < ?
                    """,
                arguments: [category.name, category.icon, category.updatedAt, category.id, category.updatedAt]
            )
            guard db.changesCount > 0 else { return false }
            try Self.enqueueOutbox(db: db, resource: "category", recordID: category.id,
                                   op: "update", payload: category)
            return true
        }
    }

    /// Deletes a category and its join rows (entries unaffected), enqueuing a
    /// delete outbox row.
    func deleteCategory(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM activity_categories WHERE category_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
            try Self.enqueueOutbox(db: db, resource: "category", recordID: id, op: "delete", payload: nil)
        }
    }

    /// Upserts a server category during a pull-merge without an outbox row
    /// (the relay already holds this version). LWW check is the caller's job.
    func mergeCategory(_ category: Category) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO categories (id, name, icon, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        icon = excluded.icon,
                        updated_at = excluded.updated_at
                    """,
                arguments: [category.id, category.name, category.icon, category.createdAt, category.updatedAt]
            )
        }
    }

    // MARK: - Entries

    /// All entries, newest first.
    func entries() throws -> [TimeEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.*, a.name AS activity_name
                FROM entries e
                JOIN activities a ON a.id = e.activity_id
                ORDER BY e.started_at DESC
                """)
            return rows.map(Self.entry(from:))
        }
    }

    /// One entry by id, or nil.
    func entry(id: String) throws -> TimeEntry? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT e.*, a.name AS activity_name
                FROM entries e
                JOIN activities a ON a.id = e.activity_id
                WHERE e.id = ?
                """, arguments: [id]) else { return nil }
            return Self.entry(from: row)
        }
    }

    /// Maps an entries row (with the joined activity_name) into a TimeEntry.
    private static func entry(from row: Row) -> TimeEntry {
        TimeEntry(
            id: row["id"],
            activityID: row["activity_id"],
            activityName: row["activity_name"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            durationSeconds: row["duration_seconds"],
            source: row["source"],
            sourceRef: row["source_ref"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    /// Creates an entry and enqueues the outbox row in one transaction.
    /// Idempotent on `id`: a replay returns the existing record. Bumps the
    /// activity's `last_used_at` (recency for suggestions, F5).
    func createEntry(_ entry: TimeEntry) throws {
        try dbQueue.write { db in
            if try Row.fetchOne(db, sql: "SELECT id FROM entries WHERE id = ?",
                                arguments: [entry.id]) != nil {
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO entries (id, activity_id, started_at, ended_at, duration_seconds,
                                         source, source_ref, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [entry.id, entry.activityID, entry.startedAt, entry.endedAt, entry.durationSeconds, entry.source, entry.sourceRef, entry.createdAt, entry.updatedAt]
            )
            try db.execute(
                sql: """
                    UPDATE activities SET last_used_at = ?
                    WHERE id = ? AND (last_used_at IS NULL OR ? > last_used_at)
                    """,
                arguments: [entry.startedAt, entry.activityID, entry.startedAt]
            )
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: entry.id,
                                   op: "create", payload: entry)
        }
    }

    /// Applies a last-write-wins update. Returns false when stale.
    @discardableResult
    func updateEntry(_ entry: TimeEntry) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE entries
                    SET activity_id = ?, started_at = ?, ended_at = ?, duration_seconds = ?, updated_at = ?
                    WHERE id = ? AND updated_at < ?
                    """,
                arguments: [entry.activityID, entry.startedAt, entry.endedAt, entry.durationSeconds, entry.updatedAt, entry.id, entry.updatedAt]
            )
            guard db.changesCount > 0 else { return false }
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: entry.id,
                                   op: "update", payload: entry)
            return true
        }
    }

    /// Deletes an entry, enqueuing a delete outbox row.
    func deleteEntry(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: id, op: "delete", payload: nil)
        }
    }

    /// Upserts a server entry during a pull-merge without an outbox row (the
    /// relay already holds this version). LWW check is the caller's job.
    func mergeEntry(_ entry: TimeEntry) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entries (id, activity_id, started_at, ended_at, duration_seconds,
                                         source, source_ref, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        activity_id = excluded.activity_id,
                        started_at = excluded.started_at,
                        ended_at = excluded.ended_at,
                        duration_seconds = excluded.duration_seconds,
                        source = excluded.source,
                        source_ref = excluded.source_ref,
                        updated_at = excluded.updated_at
                    """,
                arguments: [entry.id, entry.activityID, entry.startedAt, entry.endedAt, entry.durationSeconds, entry.source, entry.sourceRef, entry.createdAt, entry.updatedAt]
            )
        }
    }

    // MARK: - Timer state (running timer persistence, D8)

    /// The persisted running-timer state, or nil when no timer is running.
    func timerState() throws -> RunningTimerState? {
        try dbQueue.read { db in
            try RunningTimerState.fetchOne(db)
        }
    }

    /// Persists the running timer (start). The singleton row is upserted.
    func startTimer(activityID: String, activityName: String, startedAt: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO timer_state (id, activity_id, activity_name, started_at, status)
                    VALUES ('singleton', ?, ?, ?, 'running')
                    ON CONFLICT(id) DO UPDATE SET
                        activity_id = excluded.activity_id,
                        activity_name = excluded.activity_name,
                        started_at = excluded.started_at,
                        status = 'running'
                    """,
                arguments: [activityID, activityName, startedAt]
            )
        }
    }

    /// Clears the persisted running timer (stop).
    func stopTimer() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM timer_state WHERE id = 'singleton'")
        }
    }

    // MARK: - Outbox

    /// All pending outbox rows, oldest first (created_at order within a
    /// resource, per the sync-client spec).
    func outboxRows() throws -> [OutboxRow] {
        try dbQueue.read { db in
            try OutboxRow.fetchAll(db, sql: """
                SELECT * FROM outbox ORDER BY created_at, id
                """)
        }
    }

    /// Removes an outbox row after it has been pushed (or resolved).
    func removeOutboxRow(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE id = ?", arguments: [id])
        }
    }

    /// Increments the attempt counter on an outbox row (retry bookkeeping).
    func incrementOutboxAttempts(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE outbox SET attempts = attempts + 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Rewrites the payload of every pending outbox row for (resource,
    /// record_id) — used after a name-collision remap so a later drain pushes
    /// the corrected reference instead of the stale one.
    func rewriteOutboxPayload(resource: String, recordID: String, payload: (any Encodable)?) throws {
        try dbQueue.write { db in
            let payloadData: String?
            if let payload {
                payloadData = try String(data: JSONEncoder().encode(AnyEncodable(payload)), encoding: .utf8)
            } else {
                payloadData = nil
            }
            try db.execute(
                sql: "UPDATE outbox SET payload = ? WHERE resource = ? AND record_id = ?",
                arguments: [payloadData, resource, recordID]
            )
        }
    }

    /// Updates an entry row locally WITHOUT enqueuing an outbox row — used by
    /// sync conflict remapping, where the pending outbox payload is rewritten
    /// in place instead (the record has not been pushed yet).
    func updateEntryLocal(_ entry: TimeEntry) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE entries
                    SET activity_id = ?, started_at = ?, ended_at = ?, duration_seconds = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [entry.activityID, entry.startedAt, entry.endedAt, entry.durationSeconds, entry.updatedAt, entry.id]
            )
        }
    }

    /// Updates an activity row locally WITHOUT enqueuing an outbox row — used
    /// by sync conflict remapping (see `updateEntryLocal`).
    func updateActivityLocal(_ activity: Activity) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET name = ?, notes = ?, last_used_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [activity.name, activity.notes, activity.lastUsedAt, activity.updatedAt, activity.id]
            )
            try Self.replaceActivityCategories(db: db, activityID: activity.id,
                                               categoryIDs: activity.categoryIDs)
        }
    }

    // MARK: - Sync state (per-resource cursors)

    /// The last-synced cursor for a resource, or nil on first sync.
    func lastSyncedAt(resource: String) throws -> Date? {
        try dbQueue.read { db in
            try Date.fetchOne(db, sql: """
                SELECT last_synced_at FROM sync_state WHERE resource = ?
                """, arguments: [resource])
        }
    }

    /// Advances the per-resource cursor to `date`.
    func setLastSyncedAt(resource: String, date: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_state (resource, last_synced_at) VALUES (?, ?)
                    ON CONFLICT(resource) DO UPDATE SET last_synced_at = ?
                    """,
                arguments: [resource, date, date]
            )
        }
    }

    // MARK: - Undo buffer (durable, D3)

    /// The most recent buffer row (the only one undoable via shake/toast, U7).
    func undoBufferMostRecent() throws -> UndoBufferRow? {
        try dbQueue.read { db in
            try UndoBufferRow.fetchOne(db, sql: """
                SELECT * FROM undo_buffer ORDER BY deleted_at DESC, id DESC LIMIT 1
                """)
        }
    }

    /// Enters a pending deletion: inserts the buffer row in one transaction.
    /// The caller has already deleted the records (or does so in the same
    /// logical operation); no outbox row is created.
    func undoBufferEnter(payload: Data, deletedAt: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO undo_buffer (id, payload, deleted_at) VALUES (?, ?, ?)
                    """,
                arguments: [UUID().uuidString, String(data: payload, encoding: .utf8), deletedAt]
            )
        }
    }

    /// Restores the records from a buffer row's payload and deletes the
    /// buffer row in one transaction. No outbox row is ever created.
    func undoBufferRestore(id: String) throws {
        try dbQueue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: id) else { return }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            try Self.applySnapshot(db, snapshot)
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [id])
        }
    }

    /// Commits every expired buffer row: deletes the buffer row and inserts
    /// the outbox rows for the deletion in one transaction. Called on
    /// foreground reconciliation (never in the background).
    func undoBufferCommitExpired(now: Date) throws {
        try dbQueue.write { db in
            let expired = try UndoBufferRow.fetchAll(db, sql: """
                SELECT * FROM undo_buffer WHERE deleted_at < ?
                """, arguments: [now.addingTimeInterval(-UndoBufferStore.window)])
            for row in expired {
                let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
                for record in snapshot.records {
                    try Self.enqueueOutbox(db: db, resource: record.resource, recordID: record.recordID,
                                           op: "delete", payload: nil)
                }
                try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [row.id])
            }
        }
    }

    /// Re-inserts the records captured in a deletion snapshot (undo restore).
    private static func applySnapshot(_ db: Database, _ snapshot: DeletionSnapshot) throws {
        for record in snapshot.records {
            switch record.resource {
            case "activity":
                let activity = try JSONDecoder().decode(Activity.self, from: record.data)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO activities (id, name, notes, last_used_at, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [activity.id, activity.name, activity.notes, activity.lastUsedAt, activity.createdAt, activity.updatedAt]
                )
                for (index, categoryID) in activity.categoryIDs.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO activity_categories (activity_id, category_id, position)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [activity.id, categoryID, index]
                    )
                }
            case "category":
                let category = try JSONDecoder().decode(Category.self, from: record.data)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO categories (id, name, icon, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [category.id, category.name, category.icon, category.createdAt, category.updatedAt]
                )
            case "entry":
                let entry = try JSONDecoder().decode(TimeEntry.self, from: record.data)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries (id, activity_id, started_at, ended_at, duration_seconds,
                                                       source, source_ref, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [entry.id, entry.activityID, entry.startedAt, entry.endedAt, entry.durationSeconds, entry.source, entry.sourceRef, entry.createdAt, entry.updatedAt]
                )
            default:
                break
            }
        }
    }

    // MARK: - Erase local data (destructive, Settings)

    /// Wipes the entire local database (state + outbox + undo_buffer +
    /// sync_state). Used by the "Erase local data" Settings action.
    func eraseAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entries")
            try db.execute(sql: "DELETE FROM activity_categories")
            try db.execute(sql: "DELETE FROM activities")
            try db.execute(sql: "DELETE FROM categories")
            try db.execute(sql: "DELETE FROM timer_state")
            try db.execute(sql: "DELETE FROM outbox")
            try db.execute(sql: "DELETE FROM undo_buffer")
            try db.execute(sql: "DELETE FROM sync_state")
        }
    }

    // MARK: - Internals

    /// Fetches one activity row with its category ids.
    private static func fetchActivity(_ db: Database, id: String) throws -> Activity? {
        let row = try Row.fetchOne(db, sql: """
            SELECT a.*, GROUP_CONCAT(ac.category_id) AS category_ids
            FROM activities a
            LEFT JOIN activity_categories ac ON ac.activity_id = a.id
            WHERE a.id = ?
            GROUP BY a.id
            """, arguments: [id])
        guard let row else { return nil }
        return activity(from: row)
    }

    /// Fetches one activity row by case-insensitive name.
    private static func fetchActivity(_ db: Database, name: String) throws -> Activity? {
        let row = try Row.fetchOne(db, sql: """
            SELECT a.*, GROUP_CONCAT(ac.category_id) AS category_ids
            FROM activities a
            LEFT JOIN activity_categories ac ON ac.activity_id = a.id
            WHERE lower(a.name) = lower(?)
            GROUP BY a.id
            """, arguments: [name])
        guard let row else { return nil }
        return activity(from: row)
    }

    /// Maps an activities row (with the joined category_ids) into an Activity.
    private static func activity(from row: Row) -> Activity {
        Activity(
            id: row["id"],
            name: row["name"],
            notes: row["notes"],
            lastUsedAt: row["last_used_at"],
            categoryIDs: Self.categoryIDs(from: row["category_ids"]),
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    /// Splits a GROUP_CONCAT string into category ids (empty → []).
    private static func categoryIDs(from joined: String?) -> [String] {
        guard let joined, !joined.isEmpty else { return [] }
        return joined.split(separator: ",").map(String.init)
    }

    /// Atomically replaces an activity's join rows (validating ownership is
    /// implicit — the activity row was just written by the caller).
    private static func replaceActivityCategories(
        db: Database,
        activityID: String,
        categoryIDs: [String]
    ) throws {
        try db.execute(sql: "DELETE FROM activity_categories WHERE activity_id = ?",
                       arguments: [activityID])
        for (index, categoryID) in categoryIDs.enumerated() {
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO activity_categories (activity_id, category_id, position)
                    VALUES (?, ?, ?)
                    """,
                arguments: [activityID, categoryID, index]
            )
        }
    }

    /// The transactional outbox chokepoint: every mutation writes its outbox
    /// row in the same transaction as the state change (D2).
    private static func enqueueOutbox(
        db: Database,
        resource: String,
        recordID: String,
        op: String,
        payload: (any Encodable)?
    ) throws {
        let payloadData: String?
        if let payload {
            payloadData = try String(data: JSONEncoder().encode(AnyEncodable(payload)), encoding: .utf8)
        } else {
            payloadData = nil
        }
        try db.execute(
            sql: """
                INSERT INTO outbox (id, resource, record_id, op, payload, created_at, attempts)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                """,
            arguments: [UUID().uuidString, resource, recordID, op, payloadData, Date()]
        )
    }
}

// MARK: - GRDB records

/// GRDB record for the `timer_state` singleton row (D8).
struct RunningTimerState: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "timer_state"

    var id: String
    var activityID: String?
    var activityName: String?
    var startedAt: Date?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activity_id"
        case activityName = "activity_name"
        case startedAt = "started_at"
        case status
    }
}

/// GRDB record for the transactional outbox (D2).
struct OutboxRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "outbox"

    let id: String
    let resource: String
    let recordID: String
    let op: String
    let payload: String?
    let createdAt: Date
    let attempts: Int

    enum CodingKeys: String, CodingKey {
        case id, resource, op, payload, attempts
        case recordID = "record_id"
        case createdAt = "created_at"
    }
}

/// GRDB record for the durable undo buffer (D3).
struct UndoBufferRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "undo_buffer"

    let id: String
    let payload: String
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, payload
        case deletedAt = "deleted_at"
    }
}

/// A full serialized snapshot of the records deleted by one undoable deletion.
/// Held in the undo buffer so an undo can restore them exactly.
struct DeletionSnapshot: Codable, Equatable, Sendable {
    struct Record: Codable, Equatable, Sendable {
        let resource: String
        let recordID: String
        let data: Data
    }

    let records: [Record]
}
