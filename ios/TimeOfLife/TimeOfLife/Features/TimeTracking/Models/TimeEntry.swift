import Foundation

/// A recorded time-tracking session.
///
/// `synced` is false while the entry is stored locally only; it flips to true
/// after the remote repository confirms persistence.
///
/// `syncFailed` is true when the entry received a permanent server error
/// (e.g. `validation_error`) and should not be retried automatically.
///
/// `syncAttempts` counts how many times a deferrable permanent error
/// (e.g. `activity_not_found`) has been retried. After `maxSyncAttempts`
/// the entry is marked `syncFailed` to stop the deferral loop.
///
/// `activityId` links to the `Activity` catalog. `categories` is optional and
/// resolved at query time (nil while offline-only).
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date
    let synced: Bool
    let syncFailed: Bool
    let syncAttempts: Int
    var categories: [Category]?

    static let maxSyncAttempts = 10

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    func markSynced() -> Self {
        Self(
            id: id,
            activityId: activityId,
            startedAt: startedAt,
            endedAt: endedAt,
            synced: true,
            syncFailed: syncFailed,
            syncAttempts: syncAttempts,
            categories: categories
        )
    }

    func markSyncFailed() -> Self {
        Self(
            id: id,
            activityId: activityId,
            startedAt: startedAt,
            endedAt: endedAt,
            synced: synced,
            syncFailed: true,
            syncAttempts: syncAttempts,
            categories: categories
        )
    }

    func incrementSyncAttempts() -> Self {
        Self(
            id: id,
            activityId: activityId,
            startedAt: startedAt,
            endedAt: endedAt,
            synced: synced,
            syncFailed: syncFailed,
            syncAttempts: syncAttempts + 1,
            categories: categories
        )
    }

    func replacingActivityId(with activityId: UUID) -> Self {
        Self(
            id: id, activityId: activityId, startedAt: startedAt,
            endedAt: endedAt, synced: synced, syncFailed: syncFailed,
            syncAttempts: syncAttempts, categories: categories
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case synced
        case syncFailed = "sync_failed"
        case syncAttempts = "sync_attempts"
        case categories
    }

    init(
        id: UUID,
        activityId: UUID,
        startedAt: Date,
        endedAt: Date,
        synced: Bool,
        syncFailed: Bool = false,
        syncAttempts: Int = 0,
        categories: [Category]? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.synced = synced
        self.syncFailed = syncFailed
        self.syncAttempts = syncAttempts
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.activityId = try c.decode(UUID.self, forKey: .activityId)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endedAt = try c.decode(Date.self, forKey: .endedAt)
        self.synced = try c.decode(Bool.self, forKey: .synced)
        self.syncFailed = try c.decodeIfPresent(Bool.self, forKey: .syncFailed) ?? false
        self.syncAttempts = try c.decodeIfPresent(Int.self, forKey: .syncAttempts) ?? 0
        self.categories = try c.decodeIfPresent([Category].self, forKey: .categories)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(synced, forKey: .synced)
        try c.encode(syncFailed, forKey: .syncFailed)
        try c.encode(syncAttempts, forKey: .syncAttempts)
        try c.encodeIfPresent(categories, forKey: .categories)
    }
}
