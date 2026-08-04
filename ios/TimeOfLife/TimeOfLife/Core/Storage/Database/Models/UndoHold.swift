import Foundation

/// The kind of deletion captured by an undo hold (AC7).
enum UndoHoldType: String, Codable, Sendable, CaseIterable {
    /// Whole activity + all of its entries.
    case activityWithEntries = "activity_with_entries"
    /// A single latest entry (newest by `(started_at DESC, id DESC)`).
    case latestEntry = "latest_entry"
    /// Category + its `activity_categories` join rows (entries unaffected).
    case category = "category"
}

/// A snapshot of one undoable deletion, persisted in the `undo_hold` table.
///
/// Only the most recent undoable deletion is restorable (U7). The hold
/// keeps the affected records hidden via `is_undo_hidden` during the 30 s
/// window; on undo the hidden state is cleared, on expiry/supersession the
/// records are converted to durable pending deletion state and the
/// `SyncCoordinator` is triggered (AC7).
struct UndoHold: Equatable, Sendable, Codable {
    let type: UndoHoldType
    /// The activity id for `activityWithEntries`/`latestEntry`, the category
    /// id for `category`.
    let targetId: String
    /// For `activityWithEntries`: the ids of the entries captured alongside
    /// the activity. For `category`: the `(activityId, position)` join rows
    /// that were removed so they can be restored on undo. Empty for
    /// `latestEntry`.
    let entryIds: [String]
    let categoryJoins: [CategoryJoinSnapshot]
    let createdAt: Date
    let expiresAt: Date

    /// One captured `activity_categories` row for category-delete undo.
    struct CategoryJoinSnapshot: Equatable, Sendable, Codable {
        let activityId: String
        let categoryId: String
        let position: Int
    }

    /// Convenience: the deletion is expired relative to `now`.
    func isExpired(at now: Date = Date()) -> Bool {
        now >= expiresAt
    }
}

extension UndoHold {
    /// Encodes the hold to the JSON payload column of `undo_hold`.
    func encodePayload() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decodes a hold from the JSON payload column.
    static func decodePayload(_ payload: String) throws -> UndoHold {
        guard let data = payload.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [], debugDescription: "undo_hold payload is not UTF-8"))
        }
        return try JSONDecoder().decode(UndoHold.self, from: data)
    }
}
