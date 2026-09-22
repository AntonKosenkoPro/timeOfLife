import Foundation
import GRDB

/// A many-to-many tag an entry may carry.
///
/// `icon` stores the raw SF Symbol name. It is validated against the closed
/// `CatalogIcon` set at every mutation boundary; the stored value may be a
/// catalog symbol that cannot render on this OS (rendered as `tag` fallback),
/// but it is always within the authoritative catalog.
struct Category: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "categories"
    let id: String
    var name: String
    var icon: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        icon: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One timed interval. Entries own their display name, categories, and notes
/// outright (remove-activities-layer D1/D2): `activityText` is the trimmed
/// exact text (case-sensitive identity: `Gym` ≠ `GYM`), `categoryIDs` is the
/// ordered selection (position-preserved via `entry_categories`), and `notes`
/// defaults to empty. History never mutates retroactively: editing one entry
/// changes no other entry.
///
/// `source` records provenance (where the entry came from: manual, widget,
/// siri, control, screentime, garmin, ...); `sourceRef` holds the external
/// identifier for that source and is null for manual entries. The backend
/// enforces uniqueness on (user_id, source, source_ref) for non-null
/// source_ref, preventing duplicate imports.
///
/// Not a GRDB record: `category_ids` is a join-derived value, not a column.
/// `LocalStore` maps rows manually.
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var activityText: String
    var categoryIDs: [String]
    var notes: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var source: String
    var sourceRef: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        activityText: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        source: String = "manual",
        sourceRef: String? = nil,
        categoryIDs: [String] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.activityText = activityText
        self.categoryIDs = categoryIDs
        self.notes = notes
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.source = source
        self.sourceRef = sourceRef
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case activityText = "activity_text"
        case categoryIDs = "category_ids"
        case notes
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case source
        case sourceRef = "source_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One Track recents chip (timer-capture-experience spec, D5): the newest
/// committed entry of a distinct exact `activityText`, carrying that entry's
/// ordered categories (the chip icon is the first one) and its `startedAt`.
/// Identity is trimmed exact text, case-sensitive: `Gym` and `GYM` are
/// distinct chips.
struct RecentEntry: Identifiable, Equatable, Sendable {
    let activityText: String
    let categoryIDs: [String]
    let startedAt: Date

    var id: String { activityText }
}

/// A relay deletion tombstone (cross-device-delete-propagation): the record
/// of a hard delete so a device that missed it converges by removing its
/// local copy. `resource` mirrors the sync outbox resource strings
/// (`category`, `entry`).
struct Deletion: Equatable, Sendable {
    let resource: String
    let recordID: String
    let deletedAt: Date
}
