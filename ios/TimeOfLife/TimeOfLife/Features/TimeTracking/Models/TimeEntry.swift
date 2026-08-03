import Foundation

/// A recorded time-tracking session.
///
/// `synced` is false while the entry is stored locally only; it flips to true
/// after the remote repository confirms persistence.
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let activityName: String
    let startedAt: Date
    let endedAt: Date
    let synced: Bool

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    func markSynced() -> Self {
        Self(
            id: id,
            activityName: activityName,
            startedAt: startedAt,
            endedAt: endedAt,
            synced: true
        )
    }
}
