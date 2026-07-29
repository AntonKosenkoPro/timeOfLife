import Foundation

/// A recorded time-tracking session.
///
/// `synced` is false while the entry is stored locally only; it flips to true
/// after the remote repository confirms persistence.
///
/// `activityId` links to the `Activity` catalog. `activityName(lookup:)` is a
/// derived convenience resolved at query time via the injected lookup (not the
/// source of truth). `categories` is optional and resolved at query time (nil
/// while offline-only).
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date
    let synced: Bool
    var categories: [Category]?

    /// Resolved activity name. Looks up the `Activity` via `activityId` at
    /// query time using the injected `lookup` closure.
    func activityName(lookup: (UUID) -> Activity?) -> String {
        lookup(activityId)?.name ?? "Activity"
    }

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
            categories: categories
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case synced
        case categories
    }

    init(
        id: UUID,
        activityId: UUID,
        startedAt: Date,
        endedAt: Date,
        synced: Bool,
        categories: [Category]? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.synced = synced
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.activityId = try c.decode(UUID.self, forKey: .activityId)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endedAt = try c.decode(Date.self, forKey: .endedAt)
        self.synced = try c.decode(Bool.self, forKey: .synced)
        self.categories = try c.decodeIfPresent([Category].self, forKey: .categories)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(synced, forKey: .synced)
        try c.encodeIfPresent(categories, forKey: .categories)
    }
}
