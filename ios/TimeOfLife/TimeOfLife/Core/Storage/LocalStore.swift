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
    static let appGroupID = "group.com.antonkosenko.timeoflifeapp"

    /// The database file name inside the App Group container.
    static let databaseFileName = "timeoflife.sqlite"

    /// The database queue. `DatabaseQueue` is sufficient: the app is the only
    /// writer in practice, and cross-process access is serialized by SQLite's
    /// own file locking.
    private let dbQueue: DatabaseQueue

    /// Generates client record IDs (UUID v7) for new relay resources —
    /// Categories and Entries (category-management D3). One
    /// dependency-injectable generator is shared by every creation path so
    /// tests can inject deterministic ids.
    private let recordIDGenerator: RecordIDGenerating

    /// Opens (creating if needed) the database in the App Group container and
    /// migrates it to the latest schema.
    ///
    /// - Parameters:
    ///   - url: Override for the database file location. Tests pass a
    ///     temporary URL; production uses the App Group container.
    ///   - recordIDGenerator: The UUID v7 record-ID generator (injectable for
    ///     tests; defaults to the real time-ordered generator).
    init(
        url: URL? = nil,
        recordIDGenerator: RecordIDGenerating = UUIDv7Generator()
    ) throws {
        self.recordIDGenerator = recordIDGenerator
        let databaseURL = url ?? Self.defaultDatabaseURL()
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Foreign keys are enforced so a delete of a category or entry
            // cascades to its join rows, mirroring the backend relay.
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

    /// The typed schema (local-first-store spec, remove-activities-layer
    /// D1/D2/D8): state tables (categories, entry_categories, entries,
    /// timer_state), the transactional outbox, the durable undo buffer, and
    /// per-resource sync cursors. v2 transposes the schema: entries own
    /// `activity_text`, their ordered categories (via `entry_categories`),
    /// and `notes`; the `activities`/`activity_categories` entity layer is
    /// gone. Pre-release rule: no backward-compat branches — v1 databases
    /// backfill once and the old tables are dropped.
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
            try db.execute(sql: """
                CREATE UNIQUE INDEX index_activities_on_lower_name
                ON activities (lower(name))
                """)
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX index_categories_on_lower_name
                ON categories (lower(name))
                """)
            try db.create(table: "local_metadata") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
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
            try db.create(indexOn: "entries", columns: ["source", "source_ref"], options: [.unique])
            try db.create(indexOn: "entries", columns: ["activity_id"])
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
        migrator.registerMigration("v2") { db in
            // The old table keeps its `activity_id` for the backfill joins —
            // rename it out of the way first.
            try db.rename(table: "entries", to: "entries_old")
            // New entries shape: text, notes, and timing only — the display
            // name moves onto the entry (D1). `notes` defaults to ''.
            try db.create(table: "entries_new") { t in
                t.column("id", .text).primaryKey()
                t.column("activity_text", .text).notNull()
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("duration_seconds", .integer)
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("source_ref", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            // Backfill each entry from its activity's CURRENT name and notes
            // (D8): history freezes the values as of the migration.
            try db.execute(sql: """
                INSERT INTO entries_new
                    (id, activity_text, notes, started_at, ended_at, duration_seconds,
                     source, source_ref, created_at, updated_at)
                SELECT e.id, COALESCE(a.name, ''), COALESCE(a.notes, ''),
                       e.started_at, e.ended_at, e.duration_seconds,
                       e.source, e.source_ref, e.created_at, e.updated_at
                FROM entries_old e
                LEFT JOIN activities a ON a.id = e.activity_id
                """)
            // Copy the old per-activity category order into a staging table
            // BEFORE entries_old is dropped (its cascading foreign keys would
            // otherwise delete the freshly backfilled entries when it goes).
            try db.create(table: "entry_categories_staging") { t in
                t.column("entry_id", .text).notNull()
                t.column("category_id", .text).notNull()
                t.column("position", .integer).notNull()
                t.primaryKey(["entry_id", "category_id"])
            }
            try db.execute(sql: """
                INSERT INTO entry_categories_staging (entry_id, category_id, position)
                SELECT e.id, ac.category_id, ac.position
                FROM entries_new e
                JOIN entries_old o ON o.id = e.id
                JOIN activity_categories ac ON ac.activity_id = o.activity_id
                """)
            // Recents-query index (D5): per-user exact-text grouping ordered
            // by the newest commit. A single local user exists, so user_id is
            // constant — the index leads with it to mirror the relay. The
            // leading column is an expression constant (SQLite identifiers
            // and quoted strings share the `"` form in indexes).
            try db.execute(sql: """
                CREATE INDEX index_entries_on_user_activity_text_started_at
                ON entries_new (cast('__local_user__' AS TEXT), activity_text, started_at)
                """)
            try db.drop(table: "entries_old")
            try db.rename(table: "entries_new", to: "entries")
            try db.create(indexOn: "entries", columns: ["source", "source_ref"], options: [.unique])
            // Ordered per-entry categories (D2): the old
            // activity_categories(position) shape, re-anchored to entries —
            // now with the live cascade to the final `entries` table.
            try db.create(table: "entry_categories") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", onDelete: .cascade)
                t.column("category_id", .text).notNull()
                    .references("categories", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.primaryKey(["entry_id", "category_id"])
            }
            try db.execute(sql: """
                INSERT INTO entry_categories (entry_id, category_id, position)
                SELECT entry_id, category_id, position FROM entry_categories_staging
                """)
            try db.drop(table: "entry_categories_staging")
            // Transposed timer draft (D3): the running draft holds the locked
            // text and the live ordered category-id snapshot. A running
            // v1 draft cannot be mapped (its activity may backfill to a
            // different text) — it is discarded with the old table.
            try db.drop(table: "timer_state")
            try db.create(table: "timer_state") { t in
                t.column("id", .text).primaryKey()
                t.column("activity_text", .text)
                t.column("category_ids", .text)
                t.column("started_at", .datetime)
                t.column("status", .text).notNull()
            }
            // The entity layer is gone (D8). Orphan activities (no entries
            // backfilled from them) vanish with the table.
            try db.drop(table: "activity_categories")
            try db.drop(table: "activities")
            // Buffered activity snapshots reference a dropped record type:
            // commit them (they only ever fan out to activity/entry delete
            // rows) so a restart cannot trip on undecodable payloads.
            try Self.dropActivityUndoRows(db)
        }
        return migrator
    }

    /// Removes undo-buffer rows owned by the deleted activity surface inside
    /// the v2 migration. Only rows whose payload decodes as an activity-owned
    /// snapshot (a resource set containing "activity") are removed; entry-
    /// and category-owned rows are left for their owners.
    private static func dropActivityUndoRows(_ db: Database) throws {
        let rows = try UndoBufferRow.fetchAll(db, sql: "SELECT * FROM undo_buffer")
        for row in rows {
            guard let data = row.payload.data(using: .utf8),
                  let snapshot = try? JSONDecoder().decode(DeletionSnapshot.self, from: data),
                  snapshot.records.contains(where: { $0.resource == "activity" })
            else { continue }
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [row.id])
        }
    }

    // MARK: - Record IDs (UUID v7, D3)

    /// A new UUID v7 record id from the shared injectable generator, used for
    /// new Category and Entry relay resources.
    func newRecordID() -> String {
        recordIDGenerator.newID()
    }

    // MARK: - Starter category seeding (category-management D2)

    /// The local-metadata key marking that the starter category set has been
    /// created for this local dataset.
    static let categoryStartersSeededKey = "category_starters_seeded"

    /// One starter category definition: the fixed icon plus the name supplied
    /// by the composition root in the app's active supported language.
    struct StarterCategory: Sendable {
        let name: String
        let icon: CatalogIcon
    }

    /// The seven starter category icons in creation order
    /// (category-management spec, seed requirement). Names are supplied by
    /// the composition root in the active supported language.
    static let starterCategoryIcons: [CatalogIcon] = [
        .briefcase,      // Work
        .paintbrush,     // Hobby
        .figureRun,      // Sport
        .book,           // Education
        .cupAndSaucer,   // Relax
        .bedDouble,      // Sleep
        .tv,             // Entertainment
    ]

    /// The outcome of `seedStarterCategoriesIfNeeded`.
    enum SeedResult: Equatable {
        /// The starter set was created in this call (marker + records + outbox).
        case seeded([Category])
        /// The starter set already exists for this local dataset; nothing changed.
        case alreadySeeded
    }

    /// Invalid composition-root input for starter seeding.
    enum SeedError: Error, Equatable, Sendable {
        case invalidNameCount
    }

    /// Creates the starter category set exactly once per local dataset
    /// (category-management D2). One transaction checks the
    /// `category_starters_seeded` marker, inserts all seven ordinary
    /// categories, creates their category-create outbox rows, and writes the
    /// marker. A failed transaction writes none of them; a successful
    /// transaction is never replayed, even if every seed is later deleted.
    /// Clearing all local data removes the marker, so the next new local
    /// dataset receives a new starter set.
    ///
    /// Names already present (normalized match — e.g. relay-merged rows after
    /// an erase) are skipped, not re-inserted: a blind insert would violate
    /// the normalized-name unique index and abort the whole seeding, leaving
    /// the dataset seedless with no error.
    ///
    /// - Parameters:
    ///   - names: The seven localized starter names in the active supported
    ///     language, in `starterCategoryIcons` order. Materialized once at
    ///     creation; records are not renamed when the locale changes.
    ///   - now: Creation timestamp (injectable for tests).
    func seedStarterCategoriesIfNeeded(
        names: [String],
        now: Date = Date()
    ) throws -> SeedResult {
        guard names.count == Self.starterCategoryIcons.count else {
            throw SeedError.invalidNameCount
        }
        let marker = Self.categoryStartersSeededKey
        return try dbQueue.write { db in
            if try Self.metadataValue(db: db, key: marker) != nil {
                return .alreadySeeded
            }
            var seeded: [Category] = []
            for (index, icon) in Self.starterCategoryIcons.enumerated() {
                if try Self.fetchCategoryByName(db, name: names[index]) != nil {
                    continue
                }
                let category = Category(
                    id: recordIDGenerator.newID(),
                    name: names[index],
                    icon: icon.rawValue,
                    createdAt: now,
                    updatedAt: now
                )
                try category.insert(db)
                try Self.enqueueOutbox(db: db, resource: "category",
                                       recordID: category.id, op: "create",
                                       payload: category)
                seeded.append(category)
            }
            try db.execute(
                sql: "INSERT INTO local_metadata (key, value) VALUES (?, ?)",
                arguments: [marker, "true"]
            )
            return .seeded(seeded)
        }
    }

    /// Whether the starter category set has been created for this dataset.
    func categoryStartersSeeded() throws -> Bool {
        try dbQueue.read { db in
            try Self.metadataValue(db: db, key: Self.categoryStartersSeededKey) != nil
        }
    }

    /// Reads a local-metadata value, or nil when the key is absent.
    private static func metadataValue(db: Database, key: String) throws -> String? {
        try String.fetchOne(db, sql: """
            SELECT value FROM local_metadata WHERE key = ?
            """, arguments: [key])
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

    /// One category by case-insensitive normalized name, or nil.
    func category(named name: String) throws -> Category? {
        let trimmed = CategoryName.normalized(name)
        return try dbQueue.read { db in
            try Category.fetchOne(db, sql: """
                SELECT * FROM categories WHERE lower(name) = lower(?)
                """, arguments: [trimmed])
        }
    }

    /// The typed outcome of `createCategory(named:icon:)` and
    /// `updateCategory(...)` (category-management D1): distinct failures let
    /// the UI show one localized error per field and keep the draft intact.
    enum CategoryMutation: Equatable {
        /// The category was created/updated (with its outbox row).
        case saved(Category)
        /// Another category owns the same normalized name.
        case duplicate(Category)
        /// The input failed validation.
        case invalid(CategoryName.Validation)
        /// The write was stale (LWW): the local row is newer than the
        /// candidate's `updatedAt`.
        case stale
        /// The category being edited no longer exists.
        case missing
        /// The local write failed (persistence error).
        case failure
    }

    /// Validates a draft and atomically creates a category plus its outbox
    /// create row. The normalized-name unique index is the final race guard:
    /// a concurrent insert is translated to `.duplicate`.
    @discardableResult
    func createCategory(
        draft: CategoryDraft,
        id: String,
        now: Date = Date()
    ) throws -> CategoryMutation {
        let trimmed = CategoryName.normalized(draft.name)
        switch CategoryName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(CategoryName.validate(trimmed))
        case .valid:
            break
        }
        return try dbQueue.write { db in
            if let clash = try Self.fetchCategoryByName(db, name: trimmed) {
                return .duplicate(clash)
            }
            let category = Category(
                id: id,
                name: trimmed,
                icon: draft.icon.rawValue,
                createdAt: now,
                updatedAt: now
            )
            do {
                try category.insert(db)
            } catch {
                if let clash = try? Self.fetchCategoryByName(db, name: trimmed) {
                    return .duplicate(clash)
                }
                return .failure
            }
            try Self.enqueueOutbox(db: db, resource: "category", recordID: category.id,
                                   op: "create", payload: category)
            return .saved(category)
        }
    }

    /// Atomically updates a category's name/icon and enqueues an update
    /// outbox row. Returns `.duplicate` on a normalized-name collision,
    /// `.stale` when `updatedAt` is not newer than the stored version,
    /// `.missing` when the category no longer exists.
    @discardableResult
    func updateCategory(
        id: String,
        draft: CategoryDraft,
        now: Date = Date()
    ) throws -> CategoryMutation {
        let trimmed = CategoryName.normalized(draft.name)
        switch CategoryName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(CategoryName.validate(trimmed))
        case .valid:
            break
        }
        return try dbQueue.write { db in
            guard let original = try Category.fetchOne(db, key: id) else {
                return .missing
            }
            if trimmed.caseInsensitiveCompare(original.name) != .orderedSame {
                if let other = try Self.fetchCategoryByName(db, name: trimmed), other.id != id {
                    return .duplicate(other)
                }
            }
            let updated = Category(
                id: original.id,
                name: trimmed,
                icon: draft.icon.rawValue,
                createdAt: original.createdAt,
                updatedAt: now
            )
            do {
                try db.execute(
                    sql: "UPDATE categories SET name = ?, icon = ?, updated_at = ? WHERE id = ? AND updated_at < ?",
                    arguments: [updated.name, updated.icon, updated.updatedAt, updated.id, updated.updatedAt]
                )
            } catch {
                if let winner = try? Self.fetchCategoryByName(db, name: trimmed), winner.id != id {
                    return .duplicate(winner)
                }
                return .failure
            }
            guard db.changesCount > 0 else {
                return .stale
            }
            try Self.enqueueOutbox(db: db, resource: "category", recordID: updated.id,
                                   op: "update", payload: updated)
            return .saved(updated)
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
            try db.execute(sql: "DELETE FROM entry_categories WHERE category_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
            try Self.enqueueOutbox(db: db, resource: "category", recordID: id, op: "delete", payload: nil)
        }
    }

    /// Removes a category row and its join rows WITHOUT creating an outbox
    /// row — used by name-collision recovery, where the losing create row is
    /// cleared separately and no delete may reach the relay
    /// (category-management D6).
    func removeCategoryLocal(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entry_categories WHERE category_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
        }
    }

    /// Atomically adopts a winning Category identity after a relay
    /// `category_exists` response. The losing row is removed before the
    /// winner is inserted so the normalized-name unique index cannot turn a
    /// valid collision recovery into a stub category. Entry joins and
    /// pending Entry payloads are rewritten in the same transaction, and
    /// the losing Category's create row is discarded without emitting DELETE.
    func remapCategoryReferences( // swiftlint:disable:this function_body_length
        from oldID: String,
        to newID: String,
        winner: Category
    ) throws {
        try dbQueue.write { db in
            let affectedIDs = try String.fetchAll(db, sql: """
                SELECT entry_id FROM entry_categories
                WHERE category_id = ? ORDER BY entry_id
                """, arguments: [oldID])

            let affectedEntries = try affectedIDs.compactMap {
                try Self.fetchEntryRow(db, id: $0)
            }

            if oldID != newID {
                try db.execute(sql: "DELETE FROM entry_categories WHERE category_id = ?", arguments: [oldID])
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [oldID])
            }

            try db.execute(
                sql: """
                    INSERT INTO categories (id, name, icon, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        icon = excluded.icon,
                        updated_at = excluded.updated_at
                    """,
                arguments: [winner.id, winner.name, winner.icon, winner.createdAt, winner.updatedAt]
            )

            for snapshot in affectedEntries {
                let updatedCategoryIDs = Self.deduplicate(
                    snapshot.categoryIDs.map { $0 == oldID ? newID : $0 }
                )
                try Self.replaceEntryCategories(
                    db: db,
                    entryID: snapshot.id,
                    categoryIDs: updatedCategoryIDs
                )
                var updated = snapshot.entry
                updated.categoryIDs = updatedCategoryIDs
                let payload = try String(
                    data: JSONEncoder().encode(updated),
                    encoding: .utf8
                )
                try db.execute(
                    sql: """
                        UPDATE outbox
                        SET payload = ?
                        WHERE resource = 'entry' AND record_id = ?
                          AND op IN ('create', 'update')
                        """,
                    arguments: [payload, snapshot.id]
                )
            }

            try db.execute(
                sql: "DELETE FROM outbox WHERE resource = 'category' AND record_id = ?",
                arguments: [oldID]
            )
        }
    }

    /// Removes an outbox row by (resource, record_id) — used to clear a
    /// losing category-create row after collision remapping (category-
    /// management D6).
    func removeOutboxRow(resource: String, recordID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE resource = ? AND record_id = ?",
                arguments: [resource, recordID]
            )
        }
    }

    /// Authoritative Category-snapshot reconciliation (category-management
    /// D6): removes clean local Categories absent from the relay snapshot.
    /// A Category with a pending create/update outbox operation is preserved
    /// (it has not reached the relay yet), as is any Category covered by an
    /// active undo snapshot (a pending-deletion row has no live record, so it
    /// is already invisible to this deletion). Join rows cascade; no outbox
    /// row is ever created.
    func removeCategoriesAbsentFromRelay(_ relayIDs: Set<String>) throws {
        try dbQueue.write { db in
            let dirty = "SELECT record_id FROM outbox WHERE resource = 'category' AND op IN ('create', 'update')"
            if relayIDs.isEmpty {
                try db.execute(sql: "DELETE FROM categories WHERE id NOT IN (\(dirty))")
                return
            }
            let placeholders = Array(repeating: "?", count: relayIDs.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM categories WHERE id NOT IN (\(dirty)) AND id NOT IN (\(placeholders))",
                arguments: StatementArguments(Array(relayIDs))
            )
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

    /// All committed entries, newest first. Categories resolve from the
    /// entry's own `entry_categories` rows (per-entry snapshot rule — no
    /// query-time resolution through any other record).
    func entries() throws -> [TimeEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM entries ORDER BY started_at DESC
                """)
            return try rows.map { try Self.entry(from: $0, db: db) }
        }
    }

    /// One entry by id, or nil.
    func entry(id: String) throws -> TimeEntry? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM entries WHERE id = ?
                """, arguments: [id]) else { return nil }
            return try Self.entry(from: row, db: db)
        }
    }

    /// Maps an entries row into a TimeEntry, resolving its ordered categories
    /// from `entry_categories`.
    private static func entry(from row: Row, db: Database) throws -> TimeEntry {
        let categoryIDs = try String.fetchAll(db, sql: """
            SELECT category_id FROM entry_categories
            WHERE entry_id = ? ORDER BY position
            """, arguments: [row["id"]])
        return TimeEntry(
            id: row["id"],
            activityText: row["activity_text"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            durationSeconds: row["duration_seconds"],
            source: row["source"],
            sourceRef: row["source_ref"],
            categoryIDs: categoryIDs,
            notes: row["notes"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    /// The typed outcome of `createEntry(_:)`.
    enum EntryMutation: Equatable {
        /// The entry was created (with its outbox create row).
        case created(TimeEntry)
        /// A pending-deletion entry with the same id exists in the undo
        /// buffer; the caller must confirm restoration explicitly.
        case restorableDeletion(TimeEntry)
        /// The text failed validation (non-empty trim, 60 chars).
        case invalid(ActivityName.Validation)
        /// The local write failed (persistence error).
        case failure
    }

    /// Creates an entry (text + ordered categories + notes) and enqueues the
    /// single outbox row in one transaction. Idempotent on `id`: a replay
    /// returns the existing record. Referenced categories must exist locally;
    /// an unknown id throws `AssociationError.invalidCategory` and rolls the
    /// whole write back (category-management D5).
    @discardableResult
    func createEntry(_ entry: TimeEntry) throws -> EntryMutation {
        let trimmed = ActivityName.normalized(entry.activityText)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        return try dbQueue.write { db in
            if let row = try Row.fetchOne(db, sql: """
                SELECT * FROM entries WHERE id = ?
                """, arguments: [entry.id]) {
                // Idempotent replay: return the existing committed record.
                return .created(try Self.entry(from: row, db: db))
            }
            do {
                try db.execute(
                    sql: """
                        INSERT INTO entries (id, activity_text, notes, started_at, ended_at, duration_seconds,
                                             source, source_ref, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id, trimmed, entry.notes, entry.startedAt, entry.endedAt,
                        entry.durationSeconds, entry.source, entry.sourceRef,
                        entry.createdAt, entry.updatedAt,
                    ]
                )
                try Self.replaceEntryCategories(db: db, entryID: entry.id, categoryIDs: entry.categoryIDs)
            } catch let error as AssociationError {
                throw error
            } catch {
                return .failure
            }
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: entry.id,
                                   op: "create", payload: entry)
            var saved = entry
            saved.activityText = trimmed
            saved.categoryIDs = Self.deduplicate(entry.categoryIDs)
            return .created(saved)
        }
    }

    /// Applies a last-write-wins update to every entry-owned field (text,
    /// ordered categories, notes, timing). Returns false when stale. Referenced
    /// categories must exist locally; an unknown id throws
    /// `AssociationError.invalidCategory` and rolls the whole write back.
    @discardableResult
    func updateEntry(_ entry: TimeEntry) throws -> Bool {
        let trimmed = ActivityName.normalized(entry.activityText)
        guard case .valid = ActivityName.validate(trimmed) else { return false }
        return try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE entries
                    SET activity_text = ?, notes = ?, started_at = ?, ended_at = ?,
                        duration_seconds = ?, updated_at = ?
                    WHERE id = ? AND updated_at < ?
                    """,
                arguments: [
                    trimmed, entry.notes, entry.startedAt, entry.endedAt,
                    entry.durationSeconds, entry.updatedAt, entry.id, entry.updatedAt,
                ]
            )
            guard db.changesCount > 0 else { return false }
            do {
                try Self.replaceEntryCategories(db: db, entryID: entry.id, categoryIDs: entry.categoryIDs)
            } catch let error as AssociationError {
                throw error
            }
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: entry.id,
                                   op: "update", payload: entry)
            return true
        }
    }

    /// Deletes an entry (its join rows cascade), enqueuing a delete outbox row.
    func deleteEntry(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: id, op: "delete", payload: nil)
        }
    }

    /// Upserts a server entry during a pull-merge without an outbox row (the
    /// relay already holds this version). LWW check is the caller's job.
    /// Category ids the relay still references but the local catalog lacks
    /// are PRUNED (remainder kept, logged by the caller per D7) instead of
    /// failing the merge on the join foreign key.
    func mergeEntry(_ entry: TimeEntry) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entries (id, activity_text, notes, started_at, ended_at, duration_seconds,
                                         source, source_ref, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        activity_text = excluded.activity_text,
                        notes = excluded.notes,
                        started_at = excluded.started_at,
                        ended_at = excluded.ended_at,
                        duration_seconds = excluded.duration_seconds,
                        source = excluded.source,
                        source_ref = excluded.source_ref,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    entry.id, entry.activityText, entry.notes, entry.startedAt,
                    entry.endedAt, entry.durationSeconds, entry.source, entry.sourceRef,
                    entry.createdAt, entry.updatedAt,
                ]
            )
            let known = try entry.categoryIDs.filter { categoryID in
                try Category.fetchOne(db, key: categoryID) != nil
            }
            try Self.replaceEntryCategories(db: db, entryID: entry.id, categoryIDs: known)
        }
    }

    /// Fetches one entry row (for remap payload rewriting). Categories are
    /// resolved lazily by the caller when needed.
    private struct EntryRowSnapshot {
        let id: String
        let categoryIDs: [String]
        let entry: TimeEntry
    }

    /// Loads one entry with its categories as a remappable snapshot.
    private static func fetchEntryRow(_ db: Database, id: String) throws -> EntryRowSnapshot? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM entries WHERE id = ?
            """, arguments: [id]) else { return nil }
        let categoryIDs = try String.fetchAll(db, sql: """
            SELECT category_id FROM entry_categories
            WHERE entry_id = ? ORDER BY position
            """, arguments: [id])
        let entry = TimeEntry(
            id: row["id"],
            activityText: row["activity_text"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            durationSeconds: row["duration_seconds"],
            source: row["source"],
            sourceRef: row["source_ref"],
            categoryIDs: categoryIDs,
            notes: row["notes"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
        return EntryRowSnapshot(id: entry.id, categoryIDs: categoryIDs, entry: entry)
    }

    // MARK: - Recents (timer-capture-experience D5)

    /// The recents chips: one `RecentEntry` per distinct exact
    /// `activity_text`, keeping the row with the newest `started_at` of each
    /// group (its casing, ordered categories, and date), groups ordered by
    /// that max DESC, capped at `limit`. Index
    /// `index_entries_on_user_activity_text_started_at` keeps the scan cheap.
    func recents(limit: Int = 6) throws -> [RecentEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.activity_text, e.started_at, e.id
                FROM entries e
                WHERE e.id = (
                    SELECT e2.id FROM entries e2
                    WHERE e2.activity_text = e.activity_text
                    ORDER BY e2.started_at DESC, e2.id DESC
                    LIMIT 1
                )
                ORDER BY e.started_at DESC, e.id DESC
                LIMIT ?
                """, arguments: [limit])
            return try rows.map { row in
                let text: String = row["activity_text"]
                let categoryIDs = try String.fetchAll(db, sql: """
                    SELECT category_id FROM entry_categories
                    WHERE entry_id = ? ORDER BY position
                    """, arguments: [row["id"]])
                let startedAt: Date = row["started_at"]
                return RecentEntry(
                    activityText: text,
                    categoryIDs: categoryIDs,
                    startedAt: startedAt
                )
            }
        }
    }

    // MARK: - Timer draft (running timer persistence, D3/D4)

    /// The persisted running-timer draft, or nil when no timer is running.
    /// `categoryIDs` is the live ordered snapshot; `activityText` is locked
    /// from Start until Stop.
    func timerDraft() throws -> RunningTimerDraft? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM timer_state WHERE id = 'singleton'
                """) else { return nil }
            let text: String? = row["activity_text"]
            let joined: String? = row["category_ids"]
            let startedAt: Date? = row["started_at"]
            let status: String = row["status"]
            return RunningTimerDraft(
                activityText: text ?? "",
                categoryIDs: Self.categoryIDs(from: joined),
                startedAt: startedAt,
                status: status
            )
        }
    }

    /// Persists the running draft (Start): locked text plus the initial
    /// ordered category snapshot. The singleton row is upserted; any prior
    /// draft is replaced.
    func saveTimerDraft(
        activityText: String,
        categoryIDs: [String],
        startedAt: Date
    ) throws {
        let trimmed = ActivityName.normalized(activityText)
        let joined = Self.deduplicate(categoryIDs).joined(separator: ",")
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO timer_state (id, activity_text, category_ids, started_at, status)
                    VALUES ('singleton', ?, ?, ?, 'running')
                    ON CONFLICT(id) DO UPDATE SET
                        activity_text = excluded.activity_text,
                        category_ids = excluded.category_ids,
                        started_at = excluded.started_at,
                        status = 'running'
                    """,
                arguments: [trimmed, joined, startedAt]
            )
        }
    }

    /// Rewrites only the running draft's live category snapshot (a mid-run
    /// toggle, D4). The locked text and `started_at` are untouched. A no-op
    /// when no draft exists.
    func updateTimerDraftCategoryIDs(_ categoryIDs: [String]) throws {
        let joined = Self.deduplicate(categoryIDs).joined(separator: ",")
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE timer_state SET category_ids = ? WHERE id = 'singleton'",
                arguments: [joined]
            )
        }
    }

    /// Clears the persisted running draft (Stop). Creating the entry from the
    /// draft is the caller's separate transaction (one outbox row per entry).
    func clearTimerDraft() throws {
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

    /// Reads one pending outbox row by id. A drain re-reads rows after each
    /// operation because conflict recovery may rewrite a later payload in the
    /// same in-memory drain pass.
    func outboxRow(id: String) throws -> OutboxRow? {
        try dbQueue.read { db in
            try OutboxRow.fetchOne(db, key: id)
        }
    }

    /// Removes an outbox row after it has been pushed (or resolved).
    func removeOutboxRow(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Local deletion tombstones (delete-wins on pull)

    /// Whether `(resource, recordID)` has a pending outbox DELETE: a
    /// committed local deletion that has not reached the relay yet. A pull
    /// that runs before the drain pushes it (first-sync is pull-first) still
    /// sees the record on the relay and must not merge it back.
    func hasPendingDelete(resource: String, recordID: String) throws -> Bool {
        try dbQueue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM outbox
                WHERE resource = ? AND record_id = ? AND op = 'delete'
                """, arguments: [resource, recordID]) ?? 0
            return count > 0
        }
    }

    /// Whether `(resource, recordID)` sits in the durable undo buffer: a
    /// deletion the user can still undo, with no outbox row yet. The relay
    /// still holds the record, so an unguarded pull would resurrect it and
    /// the later commit would leave a permanent zombie behind.
    func isBufferedForDeletion(resource: String, recordID: String) throws -> Bool {
        try dbQueue.read { db in
            let rows = try UndoBufferRow.fetchAll(db, sql: "SELECT * FROM undo_buffer")
            for row in rows {
                guard let data = row.payload.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(DeletionSnapshot.self, from: data),
                      snapshot.records.contains(where: { $0.resource == resource && $0.recordID == recordID })
                else { continue }
                return true
            }
            return false
        }
    }

    /// Whether a pull-merge must skip this record: the user deleted it
    /// locally (buffered undoable deletion or committed outbox delete) and
    /// the relay has not converged yet. Undo restores the row and clears the
    /// buffer, and a successful drain clears the outbox row — both lift the
    /// guard, so newer server versions merge normally afterwards.
    func isLocallyDeleted(resource: String, recordID: String) throws -> Bool {
        try hasPendingDelete(resource: resource, recordID: recordID)
            || isBufferedForDeletion(resource: resource, recordID: recordID)
    }

    /// Applies one relay deletion tombstone (cross-device-delete-propagation):
    /// removes the local row — entry-category joins cascade for entries —
    /// WITHOUT creating an outbox row (the relay already lacks the record),
    /// and drops every pending create/update outbox row for the affected id.
    /// Pending DELETE rows are left untouched — the drain converges them via
    /// the existing 404-as-success rule. A clean local row newer than the
    /// tombstone (`updated_at > deleted_at`, no pending create/update) is
    /// kept: a stale tombstone after a recreation (R1). An unknown id is a
    /// no-op. Activity tombstones no longer exist; the "activity" resource is
    /// an unknown id and a no-op.
    func applyDeletionTombstone(_ deletion: Deletion) throws {
        try dbQueue.write { db in
            switch deletion.resource {
            case "entry":
                if let row = try Row.fetchOne(db, sql: """
                    SELECT updated_at FROM entries WHERE id = ?
                    """, arguments: [deletion.recordID]),
                   try !Self.hasPendingCreateOrUpdate(db, resource: "entry", recordID: deletion.recordID),
                   let updatedAt: Date = row["updated_at"],
                   updatedAt > deletion.deletedAt {
                    return // R1: the recreation already won.
                }
                try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [deletion.recordID])
                try Self.dropPendingCreateOrUpdate(db, resource: "entry", recordID: deletion.recordID)
            case "category":
                if let local = try Category.fetchOne(db, key: deletion.recordID),
                   try !Self.hasPendingCreateOrUpdate(db, resource: "category", recordID: local.id),
                   local.updatedAt > deletion.deletedAt {
                    return // R1: the recreation already won.
                }
                try db.execute(sql: "DELETE FROM entry_categories WHERE category_id = ?", arguments: [deletion.recordID])
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [deletion.recordID])
                try Self.dropPendingCreateOrUpdate(db, resource: "category", recordID: deletion.recordID)
            default:
                break
            }
        }
    }

    /// Whether `(resource, record_id)` has a pending create or update outbox
    /// row (an unpushed local mutation that the relay does not know yet).
    private static func hasPendingCreateOrUpdate(
        _ db: Database,
        resource: String,
        recordID: String
    ) throws -> Bool {
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM outbox
            WHERE resource = ? AND record_id = ? AND op IN ('create', 'update')
            """, arguments: [resource, recordID]) ?? 0
        return count > 0
    }

    /// Removes every pending create/update outbox row for
    /// `(resource, record_id)`. Pending DELETE rows are left alone: the drain
    /// converges them via the existing 404-as-success rule.
    private static func dropPendingCreateOrUpdate(
        _ db: Database,
        resource: String,
        recordID: String
    ) throws {
        try db.execute(
            sql: "DELETE FROM outbox WHERE resource = ? AND record_id = ? AND op IN ('create', 'update')",
            arguments: [resource, recordID]
        )
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

    // MARK: - Sync state (per-resource cursors)

    /// The `local_metadata` key holding the user id the sync cursors and
    /// outbox convergence belong to. Cursors are per-device rows, so without
    /// account scoping a sign-in to a *different* account (OTP vs SiWA are
    /// separate identities by design) would reuse the old account's
    /// `modified_since`/`deleted_since` and — worse — reconcile the local
    /// catalog against the new account's (possibly empty) snapshot.
    static let syncAccountIdKey = "sync_account_id"

    /// The account id the current sync cursors belong to, or nil when no
    /// account has synced yet on this dataset.
    func syncAccountId() throws -> String? {
        try dbQueue.read { db in
            try Self.metadataValue(db: db, key: Self.syncAccountIdKey)
        }
    }

    func setSyncAccountId(_ id: String?) throws {
        try dbQueue.write { db in
            if let id {
                try db.execute(
                    sql: "INSERT INTO local_metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    arguments: [Self.syncAccountIdKey, id]
                )
            } else {
                try db.execute(sql: "DELETE FROM local_metadata WHERE key = ?", arguments: [Self.syncAccountIdKey])
            }
        }
    }

    /// Switches the sync scope to `newId`. When the account actually changed,
    /// clears the per-resource cursors (next pull is a full pull against the
    /// new account) and adopts every live local category/entry that has no
    /// pending create or delete row under a freshly-minted record id: record
    /// ids are relay-global, so pushing the old account's ids into the new
    /// account would collide with another user's rows
    /// (fix-cross-account-id-collision). Names, texts, icons, and notes are
    /// preserved; entry→category references are rewritten to the fresh
    /// category ids (live joins and kept payloads alike). Records that
    /// already carry a create row (device-minted ids that were never pushed)
    /// or a delete row keep both their rows and their ids untouched — the
    /// drain's self-heal converges them. Stale update rows for adopted-away
    /// old ids are dropped without pushing (the adoption create carries the
    /// current state); pending delete rows are preserved so deletions still
    /// propagate (a 404 there is success). Returns whether the account
    /// changed. Runs exactly once per account transition; re-sign-in to the
    /// same account id is a no-op.
    @discardableResult
    func switchSyncAccountIfNeeded(to newId: String?) throws -> Bool {
        guard let newId else { return false }
        let current = try syncAccountId()
        guard current != newId else { return false }
        try dbQueue.write { db in
            try Self.adoptRecordsForAccountSwitch(db: db, idGenerator: recordIDGenerator)
            try db.execute(sql: "DELETE FROM sync_state")
            try db.execute(
                sql: "INSERT INTO local_metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [Self.syncAccountIdKey, newId]
            )
        }
        return true
    }

    /// Adopts live local rows into a new sync account under fresh record ids,
    /// in one chokepoint transaction (see `switchSyncAccountIfNeeded`).
    /// Categories go first so entries can follow the fresh ids in the same
    /// pass; the running timer draft's category snapshot follows them too.
    private static func adoptRecordsForAccountSwitch(db: Database, idGenerator: RecordIDGenerating) throws {
        var categoryMap: [String: String] = [:]
        for category in try Category.fetchAll(db, sql: "SELECT * FROM categories") {
            guard try !Self.hasPendingCreateOrDelete(db, resource: "category", recordID: category.id) else { continue }
            let freshID = idGenerator.newID()
            let fresh = try Self.rekeyCategory(db, old: category, freshID: freshID)
            try Self.enqueueOutbox(db: db, resource: "category", recordID: freshID, op: "create", payload: fresh)
            try Self.dropPendingCreateOrUpdate(db, resource: "category", recordID: category.id)
            categoryMap[category.id] = freshID
        }
        let entryIDs = try String.fetchAll(db, sql: "SELECT id FROM entries")
        for entryID in entryIDs {
            guard let snapshot = try Self.fetchEntryRow(db, id: entryID),
                  try !Self.hasPendingCreateOrDelete(db, resource: "entry", recordID: snapshot.id)
            else { continue }
            let freshID = idGenerator.newID()
            let remapped = Self.deduplicate(snapshot.categoryIDs.map { categoryMap[$0] ?? $0 })
            let fresh = try Self.rekeyEntry(db, old: snapshot.entry, categoryIDs: remapped, freshID: freshID)
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: freshID, op: "create", payload: fresh)
            try Self.dropPendingCreateOrUpdate(db, resource: "entry", recordID: snapshot.id)
        }
        if !categoryMap.isEmpty {
            // Kept (create-row) entries whose references moved under fresh
            // category ids: their live joins already follow via `rekeyCategory`,
            // but their queued payloads still name the old ids.
            let freshIDs = Array(categoryMap.values)
            let placeholders = freshIDs.map { _ in "?" }.joined(separator: ",")
            let touched = try String.fetchAll(db, sql: """
                SELECT DISTINCT entry_id FROM entry_categories
                WHERE category_id IN (\(placeholders))
                """, arguments: StatementArguments(freshIDs))
            try Self.refreshEntryPayloads(db, entryIDs: touched)
            // The running draft's category snapshot must follow as well, or
            // the next Stop would fail on the dangling reference.
            if let row = try Row.fetchOne(db, sql: "SELECT category_ids FROM timer_state WHERE id = 'singleton'"),
               let joined: String = row["category_ids"] {
                let ids = Self.categoryIDs(from: joined)
                let remapped = Self.deduplicate(ids.map { categoryMap[$0] ?? $0 })
                if remapped != ids {
                    try db.execute(
                        sql: "UPDATE timer_state SET category_ids = ? WHERE id = 'singleton'",
                        arguments: [remapped.joined(separator: ",")]
                    )
                }
            }
        }
    }

    /// Whether `(resource, record_id)` has a pending create or delete outbox
    /// row. Creates carry device-minted ids that were never pushed (safe to
    /// keep under their ids); deletes must still propagate to the relay.
    private static func hasPendingCreateOrDelete(
        _ db: Database,
        resource: String,
        recordID: String
    ) throws -> Bool {
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM outbox
            WHERE resource = ? AND record_id = ? AND op IN ('create', 'delete')
            """, arguments: [resource, recordID]) ?? 0
        return count > 0
    }

    /// Rekeys one category to a fresh id: deletes the old row (its joins
    /// cascade), inserts the identical row under the fresh id, re-inserts
    /// every affected entry's joins with the reference rewritten, and
    /// refreshes the affected entries' pending payloads from the live join
    /// state. Returns the fresh record.
    private static func rekeyCategory(_ db: Database, old: Category, freshID: String) throws -> Category {
        let affected = try String.fetchAll(db, sql: """
            SELECT DISTINCT entry_id FROM entry_categories WHERE category_id = ?
            """, arguments: [old.id])
        var joins: [String: [String]] = [:]
        for entryID in affected {
            let ids = try String.fetchAll(db, sql: """
                SELECT category_id FROM entry_categories
                WHERE entry_id = ? ORDER BY position
                """, arguments: [entryID])
            joins[entryID] = Self.deduplicate(ids.map { $0 == old.id ? freshID : $0 })
        }
        try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [old.id])
        let fresh = Category(
            id: freshID, name: old.name, icon: old.icon,
            createdAt: old.createdAt, updatedAt: old.updatedAt
        )
        try fresh.insert(db)
        for (entryID, categoryIDs) in joins {
            try Self.replaceEntryCategories(db: db, entryID: entryID, categoryIDs: categoryIDs)
        }
        try Self.refreshEntryPayloads(db, entryIDs: affected)
        return fresh
    }

    /// Rekeys one entry to a fresh id, preserving every owned field and the
    /// given ordered category set (which must reference existing categories).
    /// Returns the fresh record.
    private static func rekeyEntry(
        _ db: Database,
        old: TimeEntry,
        categoryIDs: [String],
        freshID: String
    ) throws -> TimeEntry {
        let fresh = TimeEntry(
            id: freshID,
            activityText: old.activityText,
            startedAt: old.startedAt,
            endedAt: old.endedAt,
            durationSeconds: old.durationSeconds,
            source: old.source,
            sourceRef: old.sourceRef,
            categoryIDs: categoryIDs,
            notes: old.notes,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt
        )
        // Delete first: the (source, source_ref) unique index would reject
        // cloning a non-null provenance pair while the old row still exists.
        try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [old.id])
        try db.execute(
            sql: """
                INSERT INTO entries (id, activity_text, notes, started_at, ended_at, duration_seconds,
                                     source, source_ref, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                fresh.id, fresh.activityText, fresh.notes, fresh.startedAt,
                fresh.endedAt, fresh.durationSeconds, fresh.source,
                fresh.sourceRef, fresh.createdAt, fresh.updatedAt,
            ]
        )
        try Self.replaceEntryCategories(db: db, entryID: freshID, categoryIDs: categoryIDs)
        return fresh
    }

    /// Rewrites pending entry create/update payloads from the current live
    /// join state, so a later drain pushes corrected references instead of
    /// stale ones (used after a category rekey moves joins).
    private static func refreshEntryPayloads(_ db: Database, entryIDs: [String]) throws {
        for entryID in entryIDs {
            guard let snapshot = try Self.fetchEntryRow(db, id: entryID) else { continue }
            let payload = try String(data: JSONEncoder().encode(snapshot.entry), encoding: .utf8)
            try db.execute(
                sql: """
                    UPDATE outbox SET payload = ?
                    WHERE resource = 'entry' AND record_id = ? AND op IN ('create', 'update')
                    """,
                arguments: [payload, entryID]
            )
        }
    }

    /// Heals an unresolvable category id collision by rekeying the local row
    /// onto a freshly-minted id (fix-cross-account-id-collision): every
    /// pending create/update outbox row for the old id is dropped (the fresh
    /// create below carries the current state — observably the stuck row
    /// rewritten in place), local joins and pending entry payloads follow
    /// the fresh id, and a create for the fresh id is enqueued for the
    /// caller's retry push. Pending delete rows are preserved. Returns the
    /// fresh record, or nil when no local row remains (the caller applies
    /// delete-wins / loud-failure rules).
    func healCategoryCollision(recordID: String) throws -> Category? {
        try dbQueue.write { db in
            guard let old = try Category.fetchOne(db, key: recordID) else { return nil }
            let fresh = try Self.rekeyCategory(db, old: old, freshID: recordIDGenerator.newID())
            try Self.dropPendingCreateOrUpdate(db, resource: "category", recordID: recordID)
            try Self.enqueueOutbox(db: db, resource: "category", recordID: fresh.id, op: "create", payload: fresh)
            return fresh
        }
    }

    /// Heals an unresolvable entry id collision: same shape as
    /// `healCategoryCollision` (rekey, drop superseded create/update rows,
    /// enqueue a fresh create for the caller's retry push). The fresh clone
    /// keeps text, notes, timing, provenance, and categories intact.
    /// Returns the fresh record, or nil when no local row remains.
    func healEntryCollision(recordID: String) throws -> TimeEntry? {
        try dbQueue.write { db in
            guard let snapshot = try Self.fetchEntryRow(db, id: recordID) else { return nil }
            let fresh = try Self.rekeyEntry(
                db, old: snapshot.entry,
                categoryIDs: snapshot.categoryIDs,
                freshID: recordIDGenerator.newID()
            )
            try Self.dropPendingCreateOrUpdate(db, resource: "entry", recordID: recordID)
            try Self.enqueueOutbox(db: db, resource: "entry", recordID: fresh.id, op: "create", payload: fresh)
            return fresh
        }
    }

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

    /// Set while a buffered deletion's relay push is in flight
    /// (propagate-buffered-deletes D3): undo of that row is refused for the
    /// ~100ms the push takes, closing the restore-vs-DELETE race where the
    /// relay deletes a record the user just restored with no outbox row left
    /// to repair the divergence. `LocalStore` is an actor, so plain stored
    /// state is already serialized — no extra lock needed.
    private var undoPushInFlight = false

    /// Marks the start/end of a buffered-deletion push loop. While set,
    /// `undoBufferRestore`, `undoEntryDeletion`, and `undoCategoryDeletion`
    /// refuse with `UndoError.pushInFlight`.
    func setUndoPushInFlight(_ inFlight: Bool) {
        undoPushInFlight = inFlight
    }

    /// One snapshotted record awaiting push-then-commit.
    struct BufferedDeletion: Equatable, Sendable {
        /// The `undo_buffer` row holding the snapshot.
        let bufferID: String
        let resource: String
        let recordID: String
    }

    /// Every snapshotted real record in the buffer, flattened across rows
    /// (entry order preserved per row). The internal `category_associations`
    /// pseudo-record is excluded — it never produces a push, same as
    /// `undoBufferCommitAll`.
    func bufferedDeletions() throws -> [BufferedDeletion] {
        try dbQueue.read { db in
            let rows = try UndoBufferRow.fetchAll(db, sql: """
                SELECT * FROM undo_buffer ORDER BY deleted_at ASC, id ASC
                """)
            var result: [BufferedDeletion] = []
            for row in rows {
                let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
                for record in snapshot.records
                where record.resource != CategoryDeletionSnapshot.associationsResource {
                    result.append(BufferedDeletion(bufferID: row.id, resource: record.resource, recordID: record.recordID))
                }
            }
            return result
        }
    }

    /// Drops one buffer row after all its records pushed successfully
    /// (push-then-commit). A partial failure keeps the whole row buffered —
    /// never half-committed.
    func undoBufferRemove(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [id])
        }
    }

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
    /// Refuses with `UndoError.pushInFlight` while a buffered-deletion push
    /// is in flight (propagate-buffered-deletes D3).
    func undoBufferRestore(id: String) throws {
        guard !undoPushInFlight else { throw UndoError.pushInFlight }
        try dbQueue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: id) else { return }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            try Self.applySnapshot(db, snapshot)
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [id])
        }
    }

    /// Commits every buffered row: deletes each buffer row and inserts
    /// the outbox rows for the deletion in one transaction. Called on
    /// cold launch (an app restart finalizes whatever is still buffered),
    /// never while the process is alive. The internal
    /// `category_associations` record is part of a category-deletion snapshot
    /// (category-management D7), not a resource — it never produces an outbox
    /// row; the single category DELETE row does.
    func undoBufferCommitAll() throws {
        try dbQueue.write { db in
            let buffered = try UndoBufferRow.fetchAll(db, sql: """
                SELECT * FROM undo_buffer
                """)
            for row in buffered {
                let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
                for record in snapshot.records
                where record.resource != CategoryDeletionSnapshot.associationsResource {
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
                        INSERT OR IGNORE INTO entries (id, activity_text, notes, started_at, ended_at, duration_seconds,
                                                       source, source_ref, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id, entry.activityText, entry.notes, entry.startedAt,
                        entry.endedAt, entry.durationSeconds, entry.source,
                        entry.sourceRef, entry.createdAt, entry.updatedAt,
                    ]
                )
                for (index, categoryID) in entry.categoryIDs.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entry_categories (entry_id, category_id, position)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [entry.id, categoryID, index]
                    )
                }
            default:
                break
            }
        }
    }

    // MARK: - Category deletion & undo (category-management D7)

    /// Which deletion owns a buffer payload (unify-catalog-deletion D10).
    /// Ownership is exclusive and deterministic — category wins over entry
    /// (the `category_associations` pseudo-record never owns a row alone).
    /// Every typed decoder and undo below honors only rows owned by its own
    /// resource, so no surface can claim or shred another surface's buffered
    /// deletion.
    private static func owner(of snapshot: DeletionSnapshot) -> String? {
        let resources = Set(snapshot.records.map(\.resource))
        if resources.contains("category") { return "category" }
        if resources.contains("entry") { return "entry" }
        return nil
    }

    /// The outcome of `deleteCategoryUndoable(...)`.
    enum CategoryDelete: Equatable {
        /// The category was removed; the snapshot is in the durable undo
        /// buffer (no outbox row yet).
        case deleted(CategoryDeletionSnapshot)
        /// The category no longer exists.
        case missing
        /// The local write failed (persistence error).
        case failure
    }

    /// One local Category delete that is undoable until its push succeeds
    /// (buffered deletions push on the next sync; cold launch stays the
    /// backstop).
    /// The snapshot carries the Category plus its ordered entry associations
    /// so undo can restore both exactly.
    struct CategoryDeletionSnapshot: Codable, Equatable, Sendable {
        /// The buffer payload record resource for the ordered entry
        /// associations (the category itself uses the standard
        /// `DeletionSnapshot` "category" record).
        static let associationsResource = "category_associations"

        let category: Category
        let entryIDs: [String]

        /// The buffer payload: a standard `DeletionSnapshot` with the
        /// category record (so the generic undo machinery keeps working) plus
        /// an associations record carrying the ordered entry ids.
        func bufferPayload() throws -> Data {
            try JSONEncoder().encode(DeletionSnapshot(records: [
                DeletionSnapshot.Record(
                    resource: "category",
                    recordID: category.id,
                    data: try JSONEncoder().encode(category)
                ),
                DeletionSnapshot.Record(
                    resource: Self.associationsResource,
                    recordID: category.id,
                    data: try JSONEncoder().encode(entryIDs)
                ),
            ]))
        }
    }

    /// Confirms a category deletion by entering the durable undo buffer and
    /// removing the category/joins in ONE transaction (category-management
    /// D7). The snapshot carries the Category and its ordered entry
    /// associations. NO outbox row is created while the deletion is in the
    /// buffer — the relay is never notified of an undone deletion. Entries,
    /// their texts/notes/timings, and the timer draft are untouched; only the
    /// join rows disappear.
    func deleteCategoryUndoable(
        id: String,
        deletedAt: Date = Date()
    ) throws -> CategoryDelete {
        try dbQueue.write { db in
            guard let category = try Category.fetchOne(db, key: id) else {
                return .missing
            }
            let entryIDs = try String.fetchAll(db, sql: """
                SELECT entry_id FROM entry_categories
                WHERE category_id = ? ORDER BY position
                """, arguments: [id])
            let snapshot = CategoryDeletionSnapshot(
                category: category,
                entryIDs: entryIDs
            )
            let payload = String(data: try snapshot.bufferPayload(), encoding: .utf8)
            do {
                try db.execute(
                    sql: """
                        INSERT INTO undo_buffer (id, payload, deleted_at) VALUES (?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, payload, deletedAt]
                )
                try db.execute(sql: "DELETE FROM entry_categories WHERE category_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
            } catch {
                return .failure
            }
            return .deleted(snapshot)
        }
    }

    /// Decodes the category-deletion snapshot held in a buffer row
    /// (category-management D7). Returns nil when the row does not exist or
    /// does not carry a category-OWNED deletion (D10 — entry rows
    /// are left for their owners).
    func categoryDeletionSnapshot(bufferID: String) throws -> CategoryDeletionSnapshot? {
        try dbQueue.read { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == "category" else { return nil }
            guard let categoryRecord = snapshot.records.first(where: { $0.resource == "category" }) else {
                return nil
            }
            let category = try JSONDecoder().decode(Category.self, from: categoryRecord.data)
            var entryIDs: [String] = []
            if let associations = snapshot.records.first(where: {
                $0.resource == CategoryDeletionSnapshot.associationsResource
            }) {
                entryIDs = try JSONDecoder().decode([String].self, from: associations.data)
            }
            return CategoryDeletionSnapshot(category: category, entryIDs: entryIDs)
        }
    }

    /// Undoes a category deletion: restores the same
    /// Category identity and its ordered entry associations in one
    /// transaction and removes the buffer row (category-management D7).
    /// No outbox row is ever created, so the relay is never notified of the
    /// deletion. Returns the restored category, or nil when the buffer row
    /// no longer holds a category-OWNED snapshot (D10).
    /// Refuses with `UndoError.pushInFlight` while a buffered-deletion push
    /// is in flight (propagate-buffered-deletes D3).
    @discardableResult
    func undoCategoryDeletion(bufferID: String) throws -> Category? {
        guard !undoPushInFlight else { throw UndoError.pushInFlight }
        return try dbQueue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == "category" else { return nil }
            guard let record = snapshot.records.first(where: { $0.resource == "category" }) else {
                return nil
            }
            let category = try JSONDecoder().decode(Category.self, from: record.data)
            try category.insert(db)
            if let associations = snapshot.records.first(where: {
                $0.resource == CategoryDeletionSnapshot.associationsResource
            }) {
                let entryIDs = try JSONDecoder().decode([String].self, from: associations.data)
                for (index, entryID) in entryIDs.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entry_categories (entry_id, category_id, position)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [entryID, category.id, index]
                    )
                }
            }
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [bufferID])
            return category
        }
    }

    // MARK: - Entry deletion & undo (entry-editor)

    /// The outcome of `deleteEntryUndoable(...)`.
    enum EntryDelete: Equatable {
        /// The entry was removed; the snapshot is in the durable undo
        /// buffer (no outbox row yet).
        case deleted(TimeEntry)
        /// The entry no longer exists.
        case missing
        /// The local write failed (persistence error).
        case failure
    }

    /// One local Entry delete that is undoable until its push succeeds
    /// (buffered deletions push on the next sync; cold launch stays the
    /// backstop).
    /// The snapshot carries the full TimeEntry (with its ordered categories)
    /// so undo restores it exactly. Removes the entry in ONE transaction with
    /// the buffer insert. NO outbox row is created while the deletion is in
    /// the buffer — the relay is never notified of an undone deletion.
    func deleteEntryUndoable(
        id: String,
        deletedAt: Date = Date()
    ) throws -> EntryDelete {
        try dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM entries WHERE id = ?
                """, arguments: [id]) else {
                return .missing
            }
            let entry = try Self.entry(from: row, db: db)
            let payload = String(data: try JSONEncoder().encode(DeletionSnapshot(records: [
                DeletionSnapshot.Record(
                    resource: "entry",
                    recordID: entry.id,
                    data: try JSONEncoder().encode(entry)
                ),
            ])), encoding: .utf8)
            do {
                try db.execute(
                    sql: """
                        INSERT INTO undo_buffer (id, payload, deleted_at) VALUES (?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, payload, deletedAt]
                )
                try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
            } catch {
                return .failure
            }
            return .deleted(entry)
        }
    }

    /// Decodes the entry-deletion snapshot held in a buffer row. Returns nil
    /// when the row does not exist or does not carry an entry-OWNED deletion
    /// (D10 — category rows are left for their owners).
    func entryDeletionSnapshot(bufferID: String) throws -> TimeEntry? {
        try dbQueue.read { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == "entry" else { return nil }
            guard let record = snapshot.records.first(where: { $0.resource == "entry" }) else {
                return nil
            }
            return try JSONDecoder().decode(TimeEntry.self, from: record.data)
        }
    }

    /// Undoes an entry deletion: re-inserts the entry with its ordered
    /// categories and removes the buffer row in one transaction. No outbox
    /// row is ever created, so the relay is never notified of the deletion.
    /// Returns the restored entry, or nil when the buffer row no longer holds
    /// an entry-OWNED snapshot (D10 — refusing here is what keeps an entry
    /// undo from shredding a category snapshot into an orphan entry).
    /// Refuses with `UndoError.pushInFlight` while a buffered-deletion push
    /// is in flight (propagate-buffered-deletes D3).
    @discardableResult
    func undoEntryDeletion(bufferID: String) throws -> TimeEntry? {
        guard !undoPushInFlight else { throw UndoError.pushInFlight }
        return try dbQueue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard Self.owner(of: snapshot) == "entry" else { return nil }
            guard let record = snapshot.records.first(where: { $0.resource == "entry" }) else {
                return nil
            }
            let entry = try JSONDecoder().decode(TimeEntry.self, from: record.data)
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO entries (id, activity_text, notes, started_at, ended_at, duration_seconds,
                                                   source, source_ref, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    entry.id, entry.activityText, entry.notes, entry.startedAt,
                    entry.endedAt, entry.durationSeconds, entry.source,
                    entry.sourceRef, entry.createdAt, entry.updatedAt,
                ]
            )
            for (index, categoryID) in entry.categoryIDs.enumerated() {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entry_categories (entry_id, category_id, position)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [entry.id, categoryID, index]
                )
            }
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [bufferID])
            return entry
        }
    }

    // MARK: - Erase local data (destructive, Settings)

    /// Wipes the entire local database (state + outbox + undo_buffer +
    /// sync_state). Used by the "Erase local data" Settings action.
    func eraseAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM entry_categories")
            try db.execute(sql: "DELETE FROM entries")
            try db.execute(sql: "DELETE FROM categories")
            try db.execute(sql: "DELETE FROM timer_state")
            try db.execute(sql: "DELETE FROM outbox")
            try db.execute(sql: "DELETE FROM undo_buffer")
            try db.execute(sql: "DELETE FROM sync_state")
            try db.execute(sql: "DELETE FROM local_metadata")
        }
    }

    // MARK: - Internals

    /// Fetches one category row by case-insensitive name.
    private static func fetchCategoryByName(_ db: Database, name: String) throws -> Category? {
        try Category.fetchOne(db, sql: """
            SELECT * FROM categories WHERE lower(name) = lower(?)
            """, arguments: [name])
    }

    /// Splits a joined category-ids string into ids (empty → []).
    private static func categoryIDs(from joined: String?) -> [String] {
        guard let joined, !joined.isEmpty else { return [] }
        return joined.split(separator: ",").map(String.init)
    }

    /// De-duplicates category ids while preserving first-seen order
    /// (category-management D5).
    static func deduplicate(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    /// Atomically replaces an entry's join rows. Every referenced category
    /// must exist locally; an invalid reference throws `AssociationError
    /// .invalidCategory` so the caller rolls back the whole entry write
    /// (category-management D5). IDs are de-duplicated while preserving
    /// selection order.
    private static func replaceEntryCategories(
        db: Database,
        entryID: String,
        categoryIDs: [String]
    ) throws {
        try db.execute(sql: "DELETE FROM entry_categories WHERE entry_id = ?",
                       arguments: [entryID])
        var seen = Set<String>()
        var position = 0
        for categoryID in categoryIDs {
            if seen.contains(categoryID) {
                continue
            }
            seen.insert(categoryID)
            guard try Category.fetchOne(db, key: categoryID) != nil else {
                throw AssociationError.invalidCategory(categoryID)
            }
            try db.execute(
                sql: """
                    INSERT INTO entry_categories (entry_id, category_id, position)
                    VALUES (?, ?, ?)
                    """,
                arguments: [entryID, categoryID, position]
            )
            position += 1
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

/// The persisted running-timer draft (remove-activities-layer D3/D4): the
/// locked trimmed text plus the live ordered category-id snapshot. Backed by
/// the `timer_state` singleton row; readable by widgets and lock-screen
/// Controls.
struct RunningTimerDraft: Codable, Equatable, Sendable {
    /// The locked trimmed entry text.
    var activityText: String
    /// The live ordered category-id snapshot (rewritable while running).
    var categoryIDs: [String]
    var startedAt: Date?
    var status: String
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
/// Errors thrown when an undo is refused (never a persistence failure).
enum UndoError: Error, Equatable {
    /// A buffered-deletion relay push is in flight; the row may be committed
    /// at any moment, so restoring it now could diverge from the relay
    /// (propagate-buffered-deletes D3). Transient — retry after the sync
    /// cycle finishes.
    case pushInFlight
}

struct UndoBufferRow: Codable, Equatable, FetchableRecord, PersistableRecord {    static let databaseTableName = "undo_buffer"

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

/// Errors thrown by the entry-category association replacement
/// (category-management D5). A thrown association error rolls back the whole
/// entry mutation (fields, joins, outbox) in the caller's transaction.
enum AssociationError: Error, Equatable, Sendable {
    /// A referenced category does not exist locally.
    case invalidCategory(String)
}
