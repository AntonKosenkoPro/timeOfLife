import Foundation
import Combine
import os
// swiftlint:disable file_length

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
///
/// Entries-only payloads (remove-activities-layer D7): entries carry
/// `activity_text`, ordered `category_ids`, and `notes`; unknown category
/// ids on merge are pruned with the remainder kept; there is no activity
/// pull/merge/remap/parent-heal and no activity tombstones. Tombstones and
/// delete-wins are scoped to entries and categories only. In-progress drafts
/// never enter the outbox, so nothing about the running timer is synced.
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

    /// Single-flight guard: concurrent triggers (foreground + connectivity +
    /// manual) share one cycle instead of racing.
    private var cycleTask: Task<Void, Never>?

    /// Cycle diagnostics (Console): secret-free strings only — the same codes
    /// and messages surfaced in UI. Never tokens, bodies, or emails.
    private static let logger = Logger(subsystem: "com.antonkosenko.timeoflifeapp", category: "sync")

    init(
        store: LocalStore,
        remote: CatalogSending,
        connectivity: Connectivity
    ) {
        self.store = store
        self.remote = remote
        self.connectivity = connectivity
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

    /// One sync cycle. First sync is pull-first (D4): the relay's ids
    /// arrive before local pushes. Tombstones apply before the drain
    /// (steady) or right after the pull (first sync): a tombstone drops
    /// stale pending create/update rows pre-drain, so a 404 is never pushed
    /// for a record the relay already deleted.
    private func runCycle(firstSync: Bool) async {
        defer { cycleTask = nil }
        guard connectivity.isConnected else {
            Self.logger.error("sync cycle skipped: offline")
            status = .error("offline")
            return
        }
        status = .syncing
        Self.logger.info("sync cycle start firstSync=\(firstSync)")
        do {
            if firstSync {
                try await pull(modifiedSince: nil)
            }
            try await applyTombstones()
            try await drainOutbox()
            if !firstSync {
                try await pull(modifiedSince: nil)
            }
            status = .idle(Date())
            Self.logger.info("sync cycle finished")
        } catch {
            Self.logger.error("sync cycle failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Pull (LWW merge, D4/D5)

    /// Pulls the relay's state and merges it locally, server-wins on
    /// `updated_at` (LWW). Advances the per-resource cursor to the max
    /// `updated_at` received.
    ///
    /// Ordering: the full Category snapshot is fetched and merged FIRST so
    /// every referenced category exists locally before Entries are merged
    /// (join foreign keys stay enforced).
    private func pull(modifiedSince: Date?) async throws {
        let categories = try await remote.fetchCategories()
        try await reconcileCategories(categories)
        for category in categories {
            try await applyServer(category)
        }

        let categoryCursor: Date?
        if let modifiedSince {
            categoryCursor = modifiedSince
        } else {
            categoryCursor = try await store.lastSyncedAt(resource: "category")
        }
        if let max = categories.map(\.updatedAt).max(), categoryCursor == nil || max > (categoryCursor ?? .distantPast) {
            try await store.setLastSyncedAt(resource: "category", date: max)
        }

        let entryCursor: Date?
        if let modifiedSince {
            entryCursor = modifiedSince
        } else {
            entryCursor = try await store.lastSyncedAt(resource: "entry")
        }
        let entries = try await remote.fetchEntries(modifiedSince: entryCursor)
        let serverCategoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for entry in entries {
            try await applyServer(entry, serverCategories: serverCategoriesByID)
        }
        if let max = entries.map(\.updatedAt).max() {
            try await store.setLastSyncedAt(resource: "entry", date: max)
        }
    }

    /// Applies a server category only if `server.updated_at > local.updated_at`.
    /// Same-name/different-id rivals resolve by newer-owns-the-name
    /// (category records keep their `category_exists` remap — the only
    /// name-identity remap left).
    private func applyServer(_ category: Category) async throws {
        // Delete-wins: the user deleted this record locally (buffered undoable
        // deletion or committed outbox delete) and the relay has not converged
        // yet. Merging the server copy back would resurrect it — the queued
        // DELETE removes it from the relay on drain instead.
        if try await store.isLocallyDeleted(resource: "category", recordID: category.id) {
            Self.logger.info("sync pull skips locally deleted category \(category.id, privacy: .public)")
            return
        }
        if let local = try await store.category(id: category.id) {
            guard category.updatedAt > local.updatedAt else { return }
        }
        if let rival = try await store.category(named: category.name), rival.id != category.id {
            if category.updatedAt > rival.updatedAt {
                try await store.remapCategoryReferences(from: rival.id, to: category.id, winner: category)
            } else {
                Self.logger.info("sync pull keeps local category \(rival.id, privacy: .public); skipping server \(category.id, privacy: .public)")
            }
            return
        }
        try await store.mergeCategory(category)
    }

    /// Applies a server entry only if `server.updated_at > local.updated_at`.
    /// Unknown category ids are pruned with the remainder kept (logged,
    /// secret-free) — the merge never fails the cycle on a dangling join.
    private func applyServer(_ entry: TimeEntry, serverCategories: [String: Category]) async throws {
        // Delete-wins (see applyServer(_:)): never resurrect a locally
        // deleted entry.
        if try await store.isLocallyDeleted(resource: "entry", recordID: entry.id) {
            Self.logger.info("sync pull skips locally deleted entry \(entry.id, privacy: .public)")
            return
        }
        if let local = try await store.entry(id: entry.id) {
            guard entry.updatedAt > local.updatedAt else { return }
        }
        var pruned = entry
        let knownIDs = entry.categoryIDs.filter { id in
            if serverCategories[id] != nil { return true }
            Self.logger.info("sync pull prunes unknown category \(id, privacy: .public) from entry \(entry.id, privacy: .public)")
            return false
        }
        if knownIDs.count != entry.categoryIDs.count {
            pruned.categoryIDs = knownIDs
        }
        try await store.mergeEntry(pruned)
    }

    // MARK: - Category snapshot reconciliation (category-management D6)

    /// Reconciles the authoritative full Category snapshot: LWW-merges the
    /// relay's categories, then removes clean local Categories absent from
    /// the snapshot. Categories with pending create/update outbox work are
    /// preserved (their create has not reached the relay yet). No outbox row
    /// is ever created for the removals — the relay already lacks them.
    private func reconcileCategories(_ categories: [Category]) async throws {
        let relayIDs = Set(categories.map(\.id))
        try await store.removeCategoriesAbsentFromRelay(relayIDs)
    }

    // MARK: - Deletion tombstones (cross-device-delete-propagation)

    /// Fetches and applies the relay's deletion tombstones since the
    /// `deletions` cursor, in server (oldest-first) order. Advances the
    /// cursor to the max `deleted_at` received, and keeps it unchanged when
    /// the list is empty (the no-change-keeps-cursor convention). A
    /// tombstone for an unknown id is a no-op that still advances the
    /// cursor. Only entry and category tombstones exist (activity
    /// tombstones are gone); unknown resources are ignored defensively.
    private func applyTombstones() async throws {
        let cursor = try await store.lastSyncedAt(resource: "deletions")
        let deletions: [Deletion]
        do {
            deletions = try await remote.fetchDeletions(since: cursor)
        } catch let error as APIError where error.code == "not_found" {
            // Pre-tombstone relay (no /deletions route): skip statelessly and
            // run drain+pull anyway — a later relay upgrade just starts
            // working, and push-404 convergence below still heals per-record
            // wedges against such relays. Any other fetch error still fails
            // the cycle.
            Self.logger.info("sync tombstones unsupported by relay; skipping")
            return
        }
        let known = deletions.filter { deletion in
            guard deletion.resource == "entry" || deletion.resource == "category" else {
                Self.logger.info("sync ignores unknown tombstone resource \(deletion.resource, privacy: .public)")
                return false
            }
            return true
        }
        for deletion in known {
            try await store.applyDeletionTombstone(deletion)
        }
        if let max = deletions.map(\.deletedAt).max() {
            try await store.setLastSyncedAt(resource: "deletions", date: max)
        }
        if !known.isEmpty {
            Self.logger.info("sync applied \(known.count) deletion tombstones")
        }
    }

    // MARK: - Outbox drain (idempotent replay, D2)

    /// Drains the outbox in `created_at` order, one HTTP request per row.
    /// POST is idempotent on `id` and PATCH carries `updated_at` (LWW), so a
    /// replay after a crash or relapse produces the same result as the first
    /// attempt.
    private func drainOutbox() async throws {
        let rows = try await store.outboxRows()
        for queuedRow in rows {
            // Conflict recovery can remove or rewrite a later row while this
            // drain is still iterating the initial snapshot. Always push the
            // current persisted payload rather than a stale in-memory copy.
            guard let row = try await store.outboxRow(id: queuedRow.id) else {
                continue
            }
            // Stale updates for locally-missing records (updates superseded
            // by a queued delete) can never succeed: drop without pushing
            // instead of discovering it via a doomed 404.
            if row.op == "update", try await isLocallyMissing(row) {
                Self.logger.info("sync drain drops stale update for missing \(row.resource, privacy: .public) \(row.recordID, privacy: .public)")
                try await store.removeOutboxRow(id: row.id)
                continue
            }
            do {
                try await push(row)
                try await store.removeOutboxRow(id: row.id)
            } catch let error as APIError {
                switch error.code {
                case "conflict", "category_exists", "duplicate_import":
                    try await resolveConflict(row, code: error.code ?? "", details: error.details)
                case "not_found":
                    // 404 on DELETE → treat as success (already gone). A push
                    // for a tombstone-less relay-missing record resurrects
                    // from local data and retries once (see
                    // resurrectAndRetry) instead of wedging the cycle on a
                    // doomed retry; anything else still throws.
                    if row.op == "delete" {
                        try await store.removeOutboxRow(id: row.id)
                    } else if try await resurrectAndRetry(row) {
                        break
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

    /// Whether an update row references a record with no local row: an
    /// update superseded by a queued delete. Unknown resources return false
    /// so the push path still rejects them loudly.
    private func isLocallyMissing(_ row: OutboxRow) async throws -> Bool {
        switch row.resource {
        case "category":
            return try await store.category(id: row.recordID) == nil
        case "entry":
            return try await store.entry(id: row.recordID) == nil
        default:
            return false
        }
    }

    /// Resurrects a push for a record the relay lacks with no tombstone on
    /// file (pre-deployment ghost, wipe/restore, or a seconds-wide
    /// delete-vs-push race) and retries exactly once. Tombstoned records
    /// never reach here (tombstones-first drops their rows pre-drain), so a
    /// 404 here always meets the fuller local record — resurrecting heals
    /// relay and device together, while deleting would silently discard user
    /// data (and strand future sessions against the surviving ghost).
    /// Returns whether the row was resolved (anything else rethrows the
    /// original error loudly — nothing is ever silently dropped).
    ///
    /// - entry/category update + `not_found`: re-post the full local row as
    ///   a create (idempotent; queued updates PATCH normally afterward).
    /// - entry/category create + 404: impossible per routes: returns false.
    private func resurrectAndRetry(_ row: OutboxRow) async throws -> Bool {
        switch (row.resource, row.op) {
        case ("entry", "update"), ("category", "update"):
            return try await repushRecordAsCreate(row)
        default:
            return false
        }
    }

    /// Re-posts a full local entry/category row as a create (idempotent;
    /// queued updates PATCH normally afterward). A 409 reuses the existing
    /// conflict resolver; a locally-missing row just clears its rows.
    private func repushRecordAsCreate(_ row: OutboxRow) async throws -> Bool {
        switch row.resource {
        case "entry":
            guard let entry = try await store.entry(id: row.recordID) else {
                try await store.removeOutboxRow(resource: row.resource, recordID: row.recordID)
                return true
            }
            do {
                try await remote.createEntry(entry)
            } catch let error as APIError {
                guard error.code == "duplicate_import" else { return false }
                try await resolveConflict(row, code: "duplicate_import", details: error.details)
            }
        case "category":
            guard let category = try await store.category(id: row.recordID) else {
                try await store.removeOutboxRow(resource: row.resource, recordID: row.recordID)
                return true
            }
            do {
                try await remote.createCategory(category)
            } catch let error as APIError {
                guard error.code == "category_exists" else { return false }
                try await resolveConflict(row, code: "category_exists", details: error.details)
            }
        default:
            return false
        }
        try await store.removeOutboxRow(id: row.id)
        return true
    }

    /// Resolves a push conflict per the sync-client spec:
    /// - 409 `conflict` → adopt the server's version (keep-latest) + clear the row.
    /// - 409 `category_exists` → remap local entry joins to the winning id
    ///   + clear the row.
    /// - 409 `duplicate_import` → the relay already has the record; clear the row.
    private func resolveConflict(_ row: OutboxRow, code: String, details: [String: String]) async throws {
        switch code {
        case "conflict":
            try await adoptServerVersion(row)
        case "category_exists":
            if let winningID = details["id"] {
                try await remapCategoryReferences(from: row.recordID, to: winningID)
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
    /// Skipped when the record was deleted locally after the conflicting row
    /// was queued: adopting would resurrect it, and the queued DELETE row
    /// converges the relay on its own.
    private func adoptServerVersion(_ row: OutboxRow) async throws {
        let deleted = try await store.isLocallyDeleted(resource: row.resource, recordID: row.recordID)
        if deleted {
            Self.logger.info("sync conflict keeps local deletion of \(row.resource, privacy: .public) \(row.recordID, privacy: .public)")
            return
        }
        switch row.resource {
        case "category":
            let server = try await remote.fetchCategory(id: row.recordID)
            try await store.mergeCategory(server)
        case "entry":
            let server = try await remote.fetchEntry(id: row.recordID)
            try await store.mergeEntry(await prunedEntry(server))
        default:
            break
        }
    }

    /// Re-maps local entry joins from a losing category id to the winning id
    /// after a `category_exists` 409 (category-management D6). The winning
    /// record is fetched and merged first (the relay is authoritative; the
    /// FK on joins requires it to exist). Never synthesizes record content:
    /// a winner-fetch failure rethrows, so the outbox row stays queued and
    /// the next cycle retries with local names intact.
    private func remapCategoryReferences(from oldID: String, to newID: String) async throws {
        let winner = try await remote.fetchCategory(id: newID)
        try await store.remapCategoryReferences(from: oldID, to: newID, winner: winner)
    }

    /// Prunes unknown category ids from a server entry before merge: any id
    /// absent from the fresh category snapshot is dropped, the remainder is
    /// kept (secret-free log), and the merge never fails the cycle.
    private func prunedEntry(_ entry: TimeEntry) async throws -> TimeEntry {
        guard !entry.categoryIDs.isEmpty else { return entry }
        let snapshot = try await remote.fetchCategories()
        let knownIDs = Set(snapshot.map(\.id))
        let known = entry.categoryIDs.filter { knownIDs.contains($0) }
        if known.count == entry.categoryIDs.count {
            return entry
        }
        var pruned = entry
        for id in entry.categoryIDs where !knownIDs.contains(id) {
            Self.logger.info("sync merge prunes unknown category \(id, privacy: .public) from entry \(entry.id, privacy: .public)")
        }
        pruned.categoryIDs = known
        return pruned
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
