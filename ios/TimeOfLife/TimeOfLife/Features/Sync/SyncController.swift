import Foundation
import Combine

/// The optional background sync layer (sync-client spec): when the user is
/// signed in, drains the transactional outbox to the backend relay and pulls
/// deltas via `?modified_since=`, keeping the local database and the relay
/// eventually consistent. Activated on sign-in, deactivated on sign-out; the
/// app works fully without it.
///
/// Distinct from request-response services (`AuthService`, `TimerService`) —
/// it is a background reconciler, not a per-action call. Session-gated because
/// sync is the paid feature; connectivity-gated because drain should wait for
/// `.satisfied`.
@MainActor
final class SyncController: ObservableObject {
    /// Sync status surfaced in Settings (sync-client spec).
    enum SyncStatus: Equatable {
        /// Not signed in — sync is off.
        case inactive
        /// A drain+pull cycle is in progress.
        case syncing
        /// The last cycle completed at `date`.
        case idle(Date)
        /// The last cycle failed with `message`; "Sync now" remains enabled.
        case error(String)
    }

    @Published private(set) var status: SyncStatus = .inactive

    private let store: LocalStore
    private let remote: CatalogSending
    private let connectivity: Connectivity
    private let undoBuffer: UndoBufferStore

    /// Single-flight guard: concurrent triggers (foreground + connectivity +
    /// manual) share one cycle instead of racing.
    private var cycleTask: Task<Void, Never>?

    init(
        store: LocalStore,
        remote: CatalogSending,
        connectivity: Connectivity,
        undoBuffer: UndoBufferStore
    ) {
        self.store = store
        self.remote = remote
        self.connectivity = connectivity
        self.undoBuffer = undoBuffer
    }

    // MARK: - Lifecycle (driven by SessionStore.state)

    /// Activates sync on sign-in: performs a first-sync (pull-then-push) and
    /// begins responding to triggers.
    func activate() {
        guard status == .inactive else { return }
        status = .syncing
        cycleTask = Task { [weak self] in
            await self?.runCycle(firstSync: true)
        }
    }

    /// Deactivates sync on sign-out. Local data and the outbox are preserved
    /// (local-first-store spec); the outbox accumulates until the next sign-in.
    func deactivate() {
        cycleTask?.cancel()
        cycleTask = nil
        status = .inactive
    }

    /// Manual "Sync now" from Settings. Runs the same drain+pull path as the
    /// automatic triggers.
    func syncNow() async {
        guard status != .inactive else { return }
        await runCycle(firstSync: false)
    }

    /// Foreground / connectivity-restored trigger.
    func trigger() {
        guard status != .inactive else { return }
        guard cycleTask == nil else { return }
        cycleTask = Task { [weak self] in
            await self?.runCycle(firstSync: false)
        }
    }

    // MARK: - Cycle

    /// One drain+pull cycle. First sync is pull-first (D4): the relay's ids
    /// arrive before local pushes, so cross-device name collisions mostly
    /// resolve during merge rather than on push.
    private func runCycle(firstSync: Bool) async {
        defer { cycleTask = nil }
        guard connectivity.isConnected else {
            status = .error("offline")
            return
        }
        status = .syncing
        do {
            if firstSync {
                try await pull(modifiedSince: nil)
            }
            try await drainOutbox()
            if !firstSync {
                try await pull(modifiedSince: nil)
            }
            status = .idle(Date())
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Pull (LWW merge, D4/D5)

    /// Pulls the relay's state and merges it locally, server-wins on
    /// `updated_at` (LWW). Advances the per-resource cursor to the max
    /// `updated_at` received.
    private func pull(modifiedSince: Date?) async throws {
        let activityCursor: Date?
        if let modifiedSince {
            activityCursor = modifiedSince
        } else {
            activityCursor = try await store.lastSyncedAt(resource: "activity")
        }
        let activities = try await remote.fetchActivities(modifiedSince: activityCursor)
        for activity in activities {
            try await applyServer(activity)
        }
        if let max = activities.map(\.updatedAt).max() {
            try await store.setLastSyncedAt(resource: "activity", date: max)
        }

        let categories = try await remote.fetchCategories()
        for category in categories {
            try await applyServer(category)
        }

        let entryCursor: Date?
        if let modifiedSince {
            entryCursor = modifiedSince
        } else {
            entryCursor = try await store.lastSyncedAt(resource: "entry")
        }
        let entries = try await remote.fetchEntries(modifiedSince: entryCursor)
        for entry in entries {
            try await applyServer(entry)
        }
        if let max = entries.map(\.updatedAt).max() {
            try await store.setLastSyncedAt(resource: "entry", date: max)
        }
    }

    /// Applies a server activity only if `server.updated_at > local.updated_at`.
    /// Uses the no-outbox merge path: the relay already holds this version.
    private func applyServer(_ activity: Activity) async throws {
        if let local = try await store.activity(id: activity.id) {
            guard activity.updatedAt > local.updatedAt else { return }
        }
        try await store.mergeActivity(activity)
    }

    /// Applies a server category only if `server.updated_at > local.updated_at`.
    private func applyServer(_ category: Category) async throws {
        if let local = try await store.category(id: category.id) {
            guard category.updatedAt > local.updatedAt else { return }
        }
        try await store.mergeCategory(category)
    }

    /// Applies a server entry only if `server.updated_at > local.updated_at`.
    private func applyServer(_ entry: TimeEntry) async throws {
        if let local = try await store.entry(id: entry.id) {
            guard entry.updatedAt > local.updatedAt else { return }
        }
        try await store.mergeEntry(entry)
    }

    // MARK: - Outbox drain (idempotent replay, D2)

    /// Drains the outbox in `created_at` order, one HTTP request per row.
    /// POST is idempotent on `id` and PATCH carries `updated_at` (LWW), so a
    /// replay after a crash or relapse produces the same result as the first
    /// attempt.
    private func drainOutbox() async throws {
        let rows = try await store.outboxRows()
        for row in rows {
            do {
                try await push(row)
                try await store.removeOutboxRow(id: row.id)
            } catch let error as APIError {
                switch error.code {
                case "conflict", "activity_exists", "category_exists", "duplicate_import":
                    try await resolveConflict(row, code: error.code ?? "", details: error.details)
                case "not_found":
                    // 404 on DELETE → treat as success (already gone).
                    if row.op == "delete" {
                        try await store.removeOutboxRow(id: row.id)
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            }
        }
    }

    /// Pushes one outbox row to the relay.
    private func push(_ row: OutboxRow) async throws {
        switch (row.resource, row.op) {
        case ("activity", "create"):
            let activity = try decodePayload(row, as: Activity.self)
            try await remote.createActivity(activity)
        case ("activity", "update"):
            let activity = try decodePayload(row, as: Activity.self)
            try await remote.updateActivity(activity)
        case ("activity", "delete"):
            try await remote.deleteActivity(id: row.recordID)
        case ("category", "create"):
            let category = try decodePayload(row, as: Category.self)
            try await remote.createCategory(category)
        case ("category", "update"):
            let category = try decodePayload(row, as: Category.self)
            try await remote.updateCategory(category)
        case ("category", "delete"):
            try await remote.deleteCategory(id: row.recordID)
        case ("entry", "create"):
            let entry = try decodePayload(row, as: TimeEntry.self)
            try await remote.createEntry(entry)
        case ("entry", "update"):
            let entry = try decodePayload(row, as: TimeEntry.self)
            try await remote.updateEntry(entry)
        case ("entry", "delete"):
            try await remote.deleteEntry(id: row.recordID)
        default:
            throw SyncError.unknownOutboxOp(row.resource, row.op)
        }
    }

    /// Resolves a push conflict per the sync-client spec:
    /// - 409 `conflict` → adopt the server's version (keep-latest) + clear the row.
    /// - 409 `activity_exists`/`category_exists` → remap local refs to the
    ///   winning id + clear the row.
    /// - 409 `duplicate_import` → the relay already has the record; clear the row.
    private func resolveConflict(_ row: OutboxRow, code: String, details: [String: String]) async throws {
        switch code {
        case "conflict":
            try await adoptServerVersion(row)
        case "activity_exists", "category_exists":
            if let winningID = details["id"] {
                try await remapReferences(from: row.recordID, to: winningID, resource: row.resource)
            }
        case "duplicate_import":
            break // relay already has the record; nothing to do
        default:
            break
        }
        try await store.removeOutboxRow(id: row.id)
    }

    /// Adopts the server's current version of a record (keep-latest). Uses
    /// the no-outbox merge path — the relay already holds this version.
    private func adoptServerVersion(_ row: OutboxRow) async throws {
        switch row.resource {
        case "activity":
            let server = try await remote.fetchActivity(id: row.recordID)
            try await store.mergeActivity(server)
        case "category":
            let server = try await remote.fetchCategory(id: row.recordID)
            try await store.mergeCategory(server)
        case "entry":
            let server = try await remote.fetchEntry(id: row.recordID)
            try await store.mergeEntry(server)
        default:
            break
        }
    }

    /// Re-maps local references (entries, tags) from a losing id to the
    /// winning id after a name-collision 409. The winning record is merged
    /// locally first (the relay holds it; the FK on entries requires it to
    /// exist), and pending outbox payloads are rewritten in place so a later
    /// drain pushes the corrected references.
    private func remapReferences(from oldID: String, to newID: String, resource: String) async throws {
        switch resource {
        case "activity":
            // Merge a stub of the winning activity (the relay is authoritative;
            // a full pull will replace it with the server's real version).
            if try await store.activity(id: newID) == nil {
                try await store.mergeActivity(Activity(
                    id: newID, name: oldID, createdAt: Date(), updatedAt: Date()
                ))
            }
            let entries = try await store.entries()
            for entry in entries where entry.activityID == oldID {
                var updated = entry
                updated.activityID = newID
                try await store.updateEntryLocal(updated)
                try await store.rewriteOutboxPayload(resource: "entry", recordID: entry.id, payload: updated)
            }
        case "category":
            let activities = try await store.activities()
            for activity in activities where activity.categoryIDs.contains(oldID) {
                var updated = activity
                updated.categoryIDs = activity.categoryIDs.map { $0 == oldID ? newID : $0 }
                try await store.updateActivityLocal(updated)
                try await store.rewriteOutboxPayload(resource: "activity", recordID: activity.id, payload: updated)
            }
        default:
            break
        }
    }

    /// Decodes an outbox row's payload into a model.
    private func decodePayload<T: Decodable>(_ row: OutboxRow, as type: T.Type) throws -> T {
        guard let payload = row.payload, let data = payload.data(using: .utf8) else {
            throw SyncError.missingPayload(row.resource, row.op)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Errors surfaced by the sync layer.
enum SyncError: Error, Equatable, Sendable {
    case unknownOutboxOp(String, String)
    case missingPayload(String, String)
}
