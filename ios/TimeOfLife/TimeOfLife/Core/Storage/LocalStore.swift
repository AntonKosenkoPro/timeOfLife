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

    /// Generates client record IDs (UUID v7) for new relay resources —
    /// Categories, Activities, and Entries (category-management D3). One
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
            // Normalized Activity-name uniqueness (unify-activity-preparation-
            // flow spec): names are equal after trimming surrounding
            // whitespace and case-insensitive comparison, mirroring the
            // relay's per-user index for the single local catalog. The unique
            // index is the final race guard for create-or-resolve.
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
            // Normalized Category-name uniqueness (category-management D1):
            // names are equal after trimming surrounding whitespace and
            // case-insensitive comparison, mirroring the relay's per-user
            // index. The unique index is the final race guard for create and
            // rename paths.
            try db.execute(sql: """
                CREATE UNIQUE INDEX index_categories_on_lower_name
                ON categories (lower(name))
                """)
            // Local metadata (category-management D2): the
            // `category_starters_seeded` marker ensures the starter set is
            // created exactly once per local dataset.
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

    // MARK: - Record IDs (UUID v7, D3)

    /// A new UUID v7 record id from the shared injectable generator, used for
    /// new Category, Activity, and Entry relay resources.
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

    // MARK: - Activities

    /// All activities, most-recently-used first (nil last).
    func activities() throws -> [Activity] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.*, (
                    SELECT GROUP_CONCAT(ac.category_id)
                    FROM (SELECT category_id FROM activity_categories
                          WHERE activity_id = a.id ORDER BY position) ac
                ) AS category_ids
                FROM activities a
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

    /// The typed outcome of `createOrResolveActivity(named:...)`.
    enum CreateOrResolve: Equatable {
        /// A new activity was inserted (with its outbox create row).
        case created(Activity)
        /// An existing activity with the same normalized name was reused.
        case existing(Activity)
        /// A non-expired pending-deletion activity with the same normalized
        /// name exists; the caller must confirm restoration explicitly.
        case restorableDeletion(Activity)
        /// The candidate name failed validation.
        case invalid(ActivityName.Validation)
        /// The local write failed (persistence error).
        case failure
    }

    /// Atomically creates an activity or resolves an existing identity by
    /// normalized name (unify-activity-preparation-flow spec, decision 6).
    ///
    /// The operation trims and validates the candidate name, resolves an
    /// existing row using the database's case-insensitive comparison, and
    /// inserts the activity plus its outbox row in one transaction only when
    /// no active or restorable identity exists. The unique index on
    /// `lower(name)` remains the final race guard: a concurrent insert that
    /// wins the race is translated into an `existing` outcome.
    ///
    /// - Parameters:
    ///   - name: The candidate name (surrounding whitespace is trimmed).
    ///   - notes: Optional notes for a newly created activity.
    ///   - categoryIDs: Optional category ids for a newly created activity.
    ///   - now: The creation timestamp (injectable for tests).
    func createOrResolveActivity(
        named name: String,
        notes: String? = nil,
        categoryIDs: [String] = [],
        now: Date = Date()
    ) throws -> CreateOrResolve {
        let trimmed = ActivityName.normalized(name)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        return try dbQueue.write { db in
            if let existing = try Self.fetchActivity(db, name: trimmed) {
                return .existing(existing)
            }
            if let pending = try Self.fetchPendingDeletionActivity(db, name: trimmed, now: now) {
                return .restorableDeletion(pending)
            }
            let deduplicated = Self.deduplicate(categoryIDs)
            let activity = Activity(
                id: recordIDGenerator.newID(),
                name: trimmed,
                notes: notes,
                categoryIDs: deduplicated,
                createdAt: now,
                updatedAt: now
            )
            do {
                try db.execute(
                    sql: """
                        INSERT INTO activities (id, name, notes, last_used_at, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [activity.id, activity.name, activity.notes, activity.lastUsedAt, activity.createdAt, activity.updatedAt]
                )
            } catch {
                // The unique index on lower(name) is the final race guard: a
                // concurrent create-or-resolve that inserted the same
                // normalized name wins, and this attempt resolves to it.
                if let existing = try? Self.fetchActivity(db, name: trimmed) {
                    return .existing(existing)
                }
                return .failure
            }
            try Self.replaceActivityCategories(db: db, activityID: activity.id, categoryIDs: categoryIDs)
            try Self.enqueueOutbox(db: db, resource: "activity", recordID: activity.id,
                                   op: "create", payload: activity)
            return .created(activity)
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

    /// The typed outcome of `refineActivity(...)` (refine-selected-activity-
    /// from-track change, design decision 4).
    enum RefineActivity: Equatable {
        /// The activity was updated (with its outbox update row).
        case updated(Activity)
        /// The original activity no longer exists.
        case missing
        /// Another active activity owns the same normalized name.
        case collision(Activity)
        /// The draft name failed validation.
        case invalid(ActivityName.Validation)
        /// One or more selected categories do not exist locally; the edit was
        /// rolled back in full (category-management D5).
        case invalidAssociation
        /// The local write failed (persistence error).
        case failure
    }

    /// Thrown inside the refine write transaction when an association is
    /// invalid; the caller maps it to `.invalidAssociation` after the rollback.
    private enum RefineAssociationError: Error {
        case invalidCategory
    }

    /// Atomically refines an existing activity (refine-selected-activity-
    /// from-track change, design decision 4). Accepts the original activity
    /// identifier, a validated draft, and a timestamp. In one write
    /// transaction it:
    ///
    /// 1. Fetches the original activity by id; returns `.missing` if absent.
    /// 2. Normalizes and validates the draft name; returns `.invalid` on
    ///    failure.
    /// 3. Checks for another active activity with the same normalized name,
    ///    excluding the original id; returns `.collision` if one exists.
    /// 4. Updates name, notes, Categories, and `updated_at` on the original
    ///    row.
    /// 5. Enqueues one update outbox operation containing the complete updated
    ///    activity.
    /// 6. Returns the updated activity.
    ///
    /// The database unique index on `lower(name)` is the final race guard: a
    /// constraint failure is translated to `.collision` when the winning row
    /// can be resolved. The operation never creates a new identity or
    /// restores a pending deletion.
    func refineActivity( // swiftlint:disable:this function_body_length
        id: String,
        draft: ActivityDraft,
        now: Date = Date()
    ) throws -> RefineActivity {
        let trimmed = ActivityName.normalized(draft.name)
        switch ActivityName.validate(trimmed) {
        case .empty, .tooLong:
            return .invalid(ActivityName.validate(trimmed))
        case .valid:
            break
        }
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes
        do {
            return try dbQueue.write { db in
                guard let original = try Self.fetchActivity(db, id: id) else {
                    return .missing
                }
                if trimmed.caseInsensitiveCompare(original.name) != .orderedSame {
                    if let other = try Self.fetchActivity(db, name: trimmed), other.id != id {
                        return .collision(other)
                    }
                }
                let updated = Activity(
                    id: original.id,
                    name: trimmed,
                    notes: notes,
                    lastUsedAt: original.lastUsedAt,
                    categoryIDs: draft.categoryIDs,
                    createdAt: original.createdAt,
                    updatedAt: now
                )
                do {
                    try db.execute(
                        sql: """
                            UPDATE activities
                            SET name = ?, notes = ?, last_used_at = ?, updated_at = ?
                            WHERE id = ?
                            """,
                        arguments: [updated.name, updated.notes, updated.lastUsedAt, updated.updatedAt, updated.id]
                    )
                } catch {
                    if let winner = try? Self.fetchActivity(db, name: trimmed), winner.id != id {
                        return .collision(winner)
                    }
                    return .failure
                }
                do {
                    try Self.replaceActivityCategories(db: db, activityID: updated.id, categoryIDs: draft.categoryIDs)
                } catch AssociationError.invalidCategory {
                    // Throw so the transaction ROLLS BACK the activity-field
                    // update, the join deletes, and the outbox write together
                    // (category-management D5); the caller maps it.
                    throw RefineAssociationError.invalidCategory
                }
                try Self.enqueueOutbox(db: db, resource: "activity", recordID: updated.id,
                                       op: "update", payload: updated)
                return .updated(updated)
            }
        } catch RefineAssociationError.invalidCategory {
            return .invalidAssociation
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
            try db.execute(sql: "DELETE FROM activity_categories WHERE category_id = ?", arguments: [id])
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
            try db.execute(sql: "DELETE FROM activity_categories WHERE category_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
        }
    }

    /// Atomically adopts a winning Category identity after a relay
    /// `category_exists` response. The losing row is removed before the
    /// winner is inserted so the normalized-name unique index cannot turn a
    /// valid collision recovery into a stub category. Activity joins and
    /// pending Activity payloads are rewritten in the same transaction, and
    /// the losing Category's create row is discarded without emitting DELETE.
    func remapCategoryReferences( // swiftlint:disable:this function_body_length
        from oldID: String,
        to newID: String,
        winner: Category
    ) throws {
        try dbQueue.write { db in
            let affectedIDs = try String.fetchAll(db, sql: """
                SELECT activity_id FROM activity_categories
                WHERE category_id = ? ORDER BY activity_id
                """, arguments: [oldID])

            let affectedActivities = try affectedIDs.compactMap {
                try Self.fetchActivity(db, id: $0)
            }

            if oldID != newID {
                try db.execute(sql: "DELETE FROM activity_categories WHERE category_id = ?", arguments: [oldID])
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

            for activity in affectedActivities {
                var updated = activity
                updated.categoryIDs = Self.deduplicate(
                    activity.categoryIDs.map { $0 == oldID ? newID : $0 }
                )
                try Self.replaceActivityCategories(
                    db: db,
                    activityID: updated.id,
                    categoryIDs: updated.categoryIDs
                )
                let payload = try String(
                    data: JSONEncoder().encode(updated),
                    encoding: .utf8
                )
                try db.execute(
                    sql: """
                        UPDATE outbox
                        SET payload = ?
                        WHERE resource = 'activity' AND record_id = ?
                          AND op IN ('create', 'update')
                        """,
                    arguments: [payload, updated.id]
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

    /// A non-expired pending-deletion activity whose normalized name matches
    /// `name` case-insensitively, or nil (unify-activity-preparation-flow
    /// spec, decision 7). The returned activity is the full snapshot so the
    /// caller can offer explicit restoration.
    func pendingDeletionActivity(named name: String, now: Date = Date()) throws -> Activity? {
        let trimmed = ActivityName.normalized(name)
        return try dbQueue.read { db in
            try Self.fetchPendingDeletionActivity(db, name: trimmed, now: now)
        }
    }

    /// Explicitly restores the non-expired pending-deletion activity whose
    /// normalized name matches `name` case-insensitively (unify-activity-
    /// preparation-flow spec, decision 7). The snapshot records are
    /// re-inserted and the buffer row removed in one transaction; no outbox
    /// row is ever created, so the relay is never notified of the deletion.
    /// Returns the restored activity, or nil when no matching non-expired
    /// buffer row exists.
    @discardableResult
    func restorePendingDeletionActivity(named name: String, now: Date = Date()) throws -> Activity? {
        let trimmed = ActivityName.normalized(name)
        return try dbQueue.write { db in
            let cutoff = now.addingTimeInterval(-UndoBufferStore.window)
            let rows = try UndoBufferRow.fetchAll(db, sql: """
                SELECT * FROM undo_buffer WHERE deleted_at >= ?
                """, arguments: [cutoff])
            for row in rows {
                let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
                for record in snapshot.records where record.resource == "activity" {
                    let activity = try JSONDecoder().decode(Activity.self, from: record.data)
                    if activity.name.caseInsensitiveCompare(trimmed) == .orderedSame {
                        try Self.applySnapshot(db, snapshot)
                        try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [row.id])
                        return activity
                    }
                }
            }
            return nil
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
    /// foreground reconciliation (never in the background). The internal
    /// `category_associations` record is part of a category-deletion snapshot
    /// (category-management D7), not a resource — it never produces an outbox
    /// row; the single category DELETE row does.
    func undoBufferCommitExpired(now: Date) throws {
        try dbQueue.write { db in
            let expired = try UndoBufferRow.fetchAll(db, sql: """
                SELECT * FROM undo_buffer WHERE deleted_at < ?
                """, arguments: [now.addingTimeInterval(-UndoBufferStore.window)])
            for row in expired {
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

    // MARK: - Category deletion & undo (category-management D7)

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

    /// One local Category delete that is undoable for the wall-clock window.
    /// The snapshot carries the Category plus its ordered Activity
    /// associations so undo can restore both exactly.
    struct CategoryDeletionSnapshot: Codable, Equatable, Sendable {
        /// The buffer payload record resource for the ordered Activity
        /// associations (the category itself uses the standard
        /// `DeletionSnapshot` "category" record).
        static let associationsResource = "category_associations"

        let category: Category
        let activityIDs: [String]

        /// The buffer payload: a standard `DeletionSnapshot` with the
        /// category record (so the generic undo machinery keeps working) plus
        /// an associations record carrying the ordered Activity ids.
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
                    data: try JSONEncoder().encode(activityIDs)
                ),
            ]))
        }
    }

    /// Confirms a category deletion by entering the durable undo buffer and
    /// removing the category/joins in ONE transaction (category-management
    /// D7). The snapshot carries the Category and its ordered Activity
    /// associations. NO outbox row is created while the deletion is in the
    /// buffer — the relay is never notified of an undone deletion. Activities,
    /// entries, and timer state are untouched.
    func deleteCategoryUndoable(
        id: String,
        deletedAt: Date = Date()
    ) throws -> CategoryDelete {
        try dbQueue.write { db in
            guard let category = try Category.fetchOne(db, key: id) else {
                return .missing
            }
            let activityIDs = try String.fetchAll(db, sql: """
                SELECT activity_id FROM activity_categories
                WHERE category_id = ? ORDER BY position
                """, arguments: [id])
            let snapshot = CategoryDeletionSnapshot(
                category: category,
                activityIDs: activityIDs
            )
            let payload = String(data: try snapshot.bufferPayload(), encoding: .utf8)
            do {
                try db.execute(
                    sql: """
                        INSERT INTO undo_buffer (id, payload, deleted_at) VALUES (?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, payload, deletedAt]
                )
                try db.execute(sql: "DELETE FROM activity_categories WHERE category_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
            } catch {
                return .failure
            }
            return .deleted(snapshot)
        }
    }

    /// Decodes the category-deletion snapshot held in a buffer row
    /// (category-management D7). Returns nil when the row does not exist or
    /// does not carry a category deletion.
    func categoryDeletionSnapshot(bufferID: String) throws -> CategoryDeletionSnapshot? {
        try dbQueue.read { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard let categoryRecord = snapshot.records.first(where: { $0.resource == "category" }) else {
                return nil
            }
            let category = try JSONDecoder().decode(Category.self, from: categoryRecord.data)
            var activityIDs: [String] = []
            if let associations = snapshot.records.first(where: {
                $0.resource == CategoryDeletionSnapshot.associationsResource
            }) {
                activityIDs = try JSONDecoder().decode([String].self, from: associations.data)
            }
            return CategoryDeletionSnapshot(category: category, activityIDs: activityIDs)
        }
    }

    /// Undoes a category deletion within the window: restores the same
    /// Category identity and its ordered Activity associations in one
    /// transaction and removes the buffer row (category-management D7).
    /// No outbox row is ever created, so the relay is never notified of the
    /// deletion. Returns the restored category, or nil when the buffer row
    /// no longer holds a category snapshot.
    @discardableResult
    func undoCategoryDeletion(bufferID: String) throws -> Category? {
        try dbQueue.write { db in
            guard let row = try UndoBufferRow.fetchOne(db, key: bufferID) else {
                return nil
            }
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            guard let record = snapshot.records.first(where: { $0.resource == "category" }) else {
                return nil
            }
            let category = try JSONDecoder().decode(Category.self, from: record.data)
            try category.insert(db)
            if let associations = snapshot.records.first(where: {
                $0.resource == CategoryDeletionSnapshot.associationsResource
            }) {
                let activityIDs = try JSONDecoder().decode([String].self, from: associations.data)
                for (index, activityID) in activityIDs.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO activity_categories (activity_id, category_id, position)
                            VALUES (?, ?, ?)
                            """,
                        arguments: [activityID, category.id, index]
                    )
                }
            }
            try db.execute(sql: "DELETE FROM undo_buffer WHERE id = ?", arguments: [bufferID])
            return category
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
            try db.execute(sql: "DELETE FROM local_metadata")
        }
    }

    // MARK: - Internals

    /// Fetches one activity row with its category ids.
    private static func fetchActivity(_ db: Database, id: String) throws -> Activity? {
        let row = try Row.fetchOne(db, sql: """
            SELECT a.*, (
                SELECT GROUP_CONCAT(ac.category_id)
                FROM (SELECT category_id FROM activity_categories
                      WHERE activity_id = a.id ORDER BY position) ac
            ) AS category_ids
            FROM activities a
            WHERE a.id = ?
            """, arguments: [id])
        guard let row else { return nil }
        return activity(from: row)
    }

    /// Fetches one activity row by case-insensitive name.
    private static func fetchActivity(_ db: Database, name: String) throws -> Activity? {
        let row = try Row.fetchOne(db, sql: """
            SELECT a.*, (
                SELECT GROUP_CONCAT(ac.category_id)
                FROM (SELECT category_id FROM activity_categories
                      WHERE activity_id = a.id ORDER BY position) ac
            ) AS category_ids
            FROM activities a
            WHERE lower(a.name) = lower(?)
            """, arguments: [name])
        guard let row else { return nil }
        return activity(from: row)
    }

    /// Fetches one category row by case-insensitive name.
    private static func fetchCategoryByName(_ db: Database, name: String) throws -> Category? {
        try Category.fetchOne(db, sql: """
            SELECT * FROM categories WHERE lower(name) = lower(?)
            """, arguments: [name])
    }

    /// Finds a non-expired pending-deletion activity whose normalized name    /// matches `name` case-insensitively (unify-activity-preparation-flow
    /// spec, decision 7). Returns the full snapshot activity so the caller
    /// can offer explicit restoration.
    private static func fetchPendingDeletionActivity(
        _ db: Database,
        name: String,
        now: Date
    ) throws -> Activity? {
        let cutoff = now.addingTimeInterval(-UndoBufferStore.window)
        let rows = try UndoBufferRow.fetchAll(db, sql: """
            SELECT * FROM undo_buffer WHERE deleted_at >= ?
            """, arguments: [cutoff])
        for row in rows {
            let snapshot = try JSONDecoder().decode(DeletionSnapshot.self, from: Data(row.payload.utf8))
            for record in snapshot.records where record.resource == "activity" {
                let activity = try JSONDecoder().decode(Activity.self, from: record.data)
                if activity.name.caseInsensitiveCompare(name) == .orderedSame {
                    return activity
                }
            }
        }
        return nil
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

    /// Atomically replaces an activity's join rows. Every referenced category
    /// must exist locally; an invalid reference throws `AssociationError
    /// .invalidCategory` so the caller rolls back the whole activity edit
    /// (category-management D5). IDs are de-duplicated while preserving
    /// selection order.
    private static func replaceActivityCategories(
        db: Database,
        activityID: String,
        categoryIDs: [String]
    ) throws {
        try db.execute(sql: "DELETE FROM activity_categories WHERE activity_id = ?",
                       arguments: [activityID])
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
                    INSERT INTO activity_categories (activity_id, category_id, position)
                    VALUES (?, ?, ?)
                    """,
                arguments: [activityID, categoryID, position]
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

/// Errors thrown by the Activity-category association replacement
/// (category-management D5). A thrown association error rolls back the whole
/// Activity mutation (fields, joins, outbox) in the caller's transaction.
enum AssociationError: Error, Equatable, Sendable {
    /// A referenced category does not exist locally.
    case invalidCategory(String)
}
