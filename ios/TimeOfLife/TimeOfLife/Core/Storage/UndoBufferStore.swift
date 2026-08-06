import Foundation
import GRDB

/// The durable undo buffer (D3): deletions enter the `undo_buffer` table with
/// a full serialized snapshot of the deleted records; the 30-second window is
/// wall-clock (`deleted_at + 30s`), not a `Timer`. No outbox row is created
/// while a deletion is in the buffer — the backend relay is never notified of
/// a deletion that gets undone.
///
/// Expired buffers commit to the outbox on the next foreground
/// (`commitExpired()`), never in the background. The buffer survives
/// suspension, kill, and cold launch.
actor UndoBufferStore {
    /// The undo window (wall-clock seconds).
    static let window: TimeInterval = 30

    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    /// A deletion snapshot held in the buffer.
    struct BufferEntry: Codable, Equatable, Sendable {
        let id: String
        let payload: Data
        let deletedAt: Date

        /// True when the wall-clock window has elapsed.
        func isExpired(now: Date) -> Bool {
            deletedAt.addingTimeInterval(UndoBufferStore.window) < now
        }
    }

    /// The most recent buffer row (the only one undoable via shake/toast, U7).
    func mostRecent() async throws -> BufferEntry? {
        guard let row = try await store.undoBufferMostRecent() else { return nil }
        return BufferEntry(id: row.id, payload: Data(row.payload.utf8), deletedAt: row.deletedAt)
    }

    /// Enters a pending deletion: inserts the buffer row and deletes the
    /// records in one transaction. No outbox row is created.
    func enter(payload: Data, deletedAt: Date = Date()) async throws {
        try await store.undoBufferEnter(payload: payload, deletedAt: deletedAt)
    }

    /// Undoes a deletion within the window: restores the records from the
    /// payload and deletes the buffer row in one transaction. No outbox row
    /// is ever created, so the relay is never notified of the deletion.
    func undo(id: String) async throws {
        try await store.undoBufferRestore(id: id)
    }

    /// Commits every expired buffer row: deletes the buffer row and inserts
    /// the outbox rows for the deletion in one transaction. Called on
    /// foreground reconciliation (never in the background).
    func commitExpired(now: Date = Date()) async throws {
        try await store.undoBufferCommitExpired(now: now)
    }
}
