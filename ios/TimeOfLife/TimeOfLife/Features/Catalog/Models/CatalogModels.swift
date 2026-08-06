import Foundation
import GRDB

/// A saved, reusable time-tracking target (Epic 1 catalog).
///
/// Not a GRDB record: `category_ids` is a join-derived value, not a column.
/// `LocalStore` maps rows manually.
struct Activity: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var notes: String?
    var lastUsedAt: Date?
    var categoryIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        notes: String? = nil,
        lastUsedAt: Date? = nil,
        categoryIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.lastUsedAt = lastUsedAt
        self.categoryIDs = categoryIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastUsedAt = "last_used_at"
        case categoryIDs = "category_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A many-to-many tag an activity may carry (Epic 1 catalog).
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

/// One timed interval (Epic 1 catalog). `source` records provenance (where
/// the entry came from: manual, widget, siri, control, screentime, garmin, ...);
/// `sourceRef` holds the external identifier for that source and is null for
/// manual entries. The backend enforces uniqueness on (user_id, source,
/// source_ref) for non-null source_ref, preventing duplicate imports.
///
/// Not a GRDB record: `activity_name` is a join-derived value, not a column.
/// `LocalStore` maps rows manually.
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var activityID: String
    var activityName: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var source: String
    var sourceRef: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        activityID: String,
        activityName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        source: String = "manual",
        sourceRef: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.activityID = activityID
        self.activityName = activityName
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
        case activityID = "activity_id"
        case activityName = "activity_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case source
        case sourceRef = "source_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }
}
