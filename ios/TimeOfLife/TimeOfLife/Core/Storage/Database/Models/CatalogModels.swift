import Foundation

// MARK: - Sync status

/// Synchronization state for a local record.
///
/// - `clean`: no pending changes; the record matches the server (or is
///   newly adopted from the server).
/// - `pending`: a local mutation needs to be pushed to the server.
/// - `blocked`: the server rejected the mutation (e.g. `validation_error`)
///   and the record is retained for user correction.
enum SyncStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case clean
    case pending
    case blocked
}

// MARK: - Sync metadata

/// Shared synchronization metadata carried by every synchronizable record.
struct SyncMetadata: Equatable, Sendable, Codable {
    /// `true` once the record is known to exist on the server (created or
    /// pulled at least once).
    var remoteKnown: Bool
    /// Current sync state.
    var syncStatus: SyncStatus
    /// Tombstone flag. A record with `isDeleted == true` and
    /// `syncStatus == .pending` is awaiting a DELETE push.
    var isDeleted: Bool
    /// Undo-window hide flag. While `true`, the record is excluded from
    /// user-facing queries but still present on disk.
    var isUndoHidden: Bool
    /// Monotonically increasing per-record revision. Bumped on every local
    /// mutation so a stale in-flight response cannot overwrite a newer edit.
    var localRevision: Int
    /// Last server error code recorded for this record (if blocked).
    var syncErrorCode: String?
    /// Last server error message recorded for this record (if blocked).
    var syncErrorMessage: String?

    /// Default metadata for a freshly created, never-synced record.
    static func newPending() -> SyncMetadata {
        SyncMetadata(
            remoteKnown: false,
            syncStatus: .pending,
            isDeleted: false,
            isUndoHidden: false,
            localRevision: 1,
            syncErrorCode: nil,
            syncErrorMessage: nil
        )
    }

    /// Default metadata for a record adopted from the server.
    static func adoptedClean() -> SyncMetadata {
        SyncMetadata(
            remoteKnown: true,
            syncStatus: .clean,
            isDeleted: false,
            isUndoHidden: false,
            localRevision: 0,
            syncErrorCode: nil,
            syncErrorMessage: nil
        )
    }
}

// MARK: - Activity

/// A catalog activity.
struct Activity: Identifiable, Equatable, Sendable, Codable {
    let id: String
    var name: String
    var notes: String?
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var categoryIds: [String]
    var sync: SyncMetadata
}

extension Activity {
    /// Returns `true` if the activity should appear in user-facing queries:
    /// not deleted and not in the undo-hide window.
    var isVisible: Bool { !sync.isDeleted && !sync.isUndoHidden }
}

// MARK: - Category

/// A catalog category (tag).
struct Category: Identifiable, Equatable, Sendable, Codable {
    let id: String
    var name: String
    var icon: String
    var createdAt: Date
    var updatedAt: Date
    var sync: SyncMetadata
}

extension Category {
    /// Returns `true` if the category should appear in user-facing queries:
    /// not deleted and not in the undo-hide window.
    var isVisible: Bool { !sync.isDeleted && !sync.isUndoHidden }
}

// MARK: - Entry

/// A time-tracking entry linked to an activity.
struct Entry: Identifiable, Equatable, Sendable, Codable {
    let id: String
    var activityId: String
    var startedAt: Date
    /// `nil` for a running entry (pulled from the server but not yet ended).
    var endedAt: Date?
    var durationSeconds: Double?
    var createdAt: Date
    var updatedAt: Date
    var sync: SyncMetadata
}

extension Entry {
    /// Derived duration from `endedAt - startedAt`, or `nil` while running.
    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// Returns `true` if the entry should appear in user-facing queries:
    /// not deleted and not in the undo-hide window.
    var isVisible: Bool { !sync.isDeleted && !sync.isUndoHidden }
}

// MARK: - Category tag (lightweight, used in server DTOs)

/// A lightweight category reference as returned by the server alongside
/// activities and entries.
struct CategoryTag: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let name: String
    let icon: String
}
