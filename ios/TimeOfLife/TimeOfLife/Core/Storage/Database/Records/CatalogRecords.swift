import GRDB
import Foundation

// MARK: - Sync metadata columns

/// Shared sync-metadata column names used by every synchronizable record.
enum SyncMetadataColumns {
    static let remoteKnown = "remote_known"
    static let syncStatus = "sync_status"
    static let isDeleted = "is_deleted"
    static let isUndoHidden = "is_undo_hidden"
    static let localRevision = "local_revision"
    static let syncErrorCode = "sync_error_code"
    static let syncErrorMessage = "sync_error_message"
}

// MARK: - ActivityRecord

/// GRDB row representation of an activity.
struct ActivityRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "activities"

    var id: String
    var name: String
    var notes: String?
    var lastUsedAt: Double?
    var createdAt: Double
    var updatedAt: Double
    var remoteKnown: Int
    var syncStatus: String
    var isDeleted: Int
    var isUndoHidden: Int
    var localRevision: Int
    var syncErrorCode: String?
    var syncErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case remoteKnown = "remote_known"
        case syncStatus = "sync_status"
        case isDeleted = "is_deleted"
        case isUndoHidden = "is_undo_hidden"
        case localRevision = "local_revision"
        case syncErrorCode = "sync_error_code"
        case syncErrorMessage = "sync_error_message"
    }
}

extension ActivityRecord {
    /// Converts the GRDB row to the domain model.
    func toModel(categoryIds: [String]) -> Activity {
        Activity(
            id: id,
            name: name,
            notes: notes,
            lastUsedAt: lastUsedAt.map { Date(timeIntervalSinceReferenceDate: $0) },
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            categoryIds: categoryIds,
            sync: SyncMetadata(
                remoteKnown: remoteKnown != 0,
                syncStatus: SyncStatus(rawValue: syncStatus) ?? .clean,
                isDeleted: isDeleted != 0,
                isUndoHidden: isUndoHidden != 0,
                localRevision: localRevision,
                syncErrorCode: syncErrorCode,
                syncErrorMessage: syncErrorMessage
            )
        )
    }

    /// Creates a GRDB row from the domain model.
    static func from(_ model: Activity) -> ActivityRecord {
        ActivityRecord(
            id: model.id,
            name: model.name,
            notes: model.notes,
            lastUsedAt: model.lastUsedAt?.timeIntervalSinceReferenceDate,
            createdAt: model.createdAt.timeIntervalSinceReferenceDate,
            updatedAt: model.updatedAt.timeIntervalSinceReferenceDate,
            remoteKnown: model.sync.remoteKnown ? 1 : 0,
            syncStatus: model.sync.syncStatus.rawValue,
            isDeleted: model.sync.isDeleted ? 1 : 0,
            isUndoHidden: model.sync.isUndoHidden ? 1 : 0,
            localRevision: model.sync.localRevision,
            syncErrorCode: model.sync.syncErrorCode,
            syncErrorMessage: model.sync.syncErrorMessage
        )
    }
}

// MARK: - CategoryRecord

/// GRDB row representation of a category.
struct CategoryRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "categories"

    var id: String
    var name: String
    var icon: String
    var createdAt: Double
    var updatedAt: Double
    var remoteKnown: Int
    var syncStatus: String
    var isDeleted: Int
    var isUndoHidden: Int
    var localRevision: Int
    var syncErrorCode: String?
    var syncErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case remoteKnown = "remote_known"
        case syncStatus = "sync_status"
        case isDeleted = "is_deleted"
        case isUndoHidden = "is_undo_hidden"
        case localRevision = "local_revision"
        case syncErrorCode = "sync_error_code"
        case syncErrorMessage = "sync_error_message"
    }
}

extension CategoryRecord {
    func toModel() -> Category {
        Category(
            id: id,
            name: name,
            icon: icon,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            sync: SyncMetadata(
                remoteKnown: remoteKnown != 0,
                syncStatus: SyncStatus(rawValue: syncStatus) ?? .clean,
                isDeleted: isDeleted != 0,
                isUndoHidden: isUndoHidden != 0,
                localRevision: localRevision,
                syncErrorCode: syncErrorCode,
                syncErrorMessage: syncErrorMessage
            )
        )
    }

    static func from(_ model: Category) -> CategoryRecord {
        CategoryRecord(
            id: model.id,
            name: model.name,
            icon: model.icon,
            createdAt: model.createdAt.timeIntervalSinceReferenceDate,
            updatedAt: model.updatedAt.timeIntervalSinceReferenceDate,
            remoteKnown: model.sync.remoteKnown ? 1 : 0,
            syncStatus: model.sync.syncStatus.rawValue,
            isDeleted: model.sync.isDeleted ? 1 : 0,
            isUndoHidden: model.sync.isUndoHidden ? 1 : 0,
            localRevision: model.sync.localRevision,
            syncErrorCode: model.sync.syncErrorCode,
            syncErrorMessage: model.sync.syncErrorMessage
        )
    }
}

// MARK: - EntryRecord

/// GRDB row representation of a time entry.
struct EntryRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "entries"

    var id: String
    var activityId: String
    var startedAt: Double
    var endedAt: Double?
    var durationSeconds: Double?
    var createdAt: Double
    var updatedAt: Double
    var remoteKnown: Int
    var syncStatus: String
    var isDeleted: Int
    var isUndoHidden: Int
    var localRevision: Int
    var syncErrorCode: String?
    var syncErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case remoteKnown = "remote_known"
        case syncStatus = "sync_status"
        case isDeleted = "is_deleted"
        case isUndoHidden = "is_undo_hidden"
        case localRevision = "local_revision"
        case syncErrorCode = "sync_error_code"
        case syncErrorMessage = "sync_error_message"
    }
}

extension EntryRecord {
    func toModel() -> Entry {
        Entry(
            id: id,
            activityId: activityId,
            startedAt: Date(timeIntervalSinceReferenceDate: startedAt),
            endedAt: endedAt.map { Date(timeIntervalSinceReferenceDate: $0) },
            durationSeconds: durationSeconds,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            sync: SyncMetadata(
                remoteKnown: remoteKnown != 0,
                syncStatus: SyncStatus(rawValue: syncStatus) ?? .clean,
                isDeleted: isDeleted != 0,
                isUndoHidden: isUndoHidden != 0,
                localRevision: localRevision,
                syncErrorCode: syncErrorCode,
                syncErrorMessage: syncErrorMessage
            )
        )
    }

    static func from(_ model: Entry) -> EntryRecord {
        EntryRecord(
            id: model.id,
            activityId: model.activityId,
            startedAt: model.startedAt.timeIntervalSinceReferenceDate,
            endedAt: model.endedAt?.timeIntervalSinceReferenceDate,
            durationSeconds: model.durationSeconds,
            createdAt: model.createdAt.timeIntervalSinceReferenceDate,
            updatedAt: model.updatedAt.timeIntervalSinceReferenceDate,
            remoteKnown: model.sync.remoteKnown ? 1 : 0,
            syncStatus: model.sync.syncStatus.rawValue,
            isDeleted: model.sync.isDeleted ? 1 : 0,
            isUndoHidden: model.sync.isUndoHidden ? 1 : 0,
            localRevision: model.sync.localRevision,
            syncErrorCode: model.sync.syncErrorCode,
            syncErrorMessage: model.sync.syncErrorMessage
        )
    }
}

// MARK: - ActivityCategoryRecord (join)

/// GRDB row representation of an `activity_categories` join row.
struct ActivityCategoryRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "activity_categories"

    var activityId: String
    var categoryId: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case categoryId = "category_id"
        case position
    }
}

// MARK: - UndoHoldRecord

/// GRDB row representation of an `undo_hold` row.
struct UndoHoldRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "undo_hold"

    var id: Int64?
    var holdType: String
    var payload: String
    var createdAt: Double
    var expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case holdType = "hold_type"
        case payload
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - MetadataRecord

/// GRDB row representation of a `metadata` row.
struct MetadataRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "metadata"

    var key: String
    var value: String
}
