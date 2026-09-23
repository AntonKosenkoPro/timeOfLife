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

    /// Manual "Sync now" from Settings, and History pull-to-refresh
    /// (sync-client spec): runs the same drain+pull path as the automatic
    /// triggers. A call arriving while a cycle is already in flight joins it
    /// (awaits the in-flight cycle's result) instead of starting a second
    /// concurrent cycle; the fresh cycle registers itself so later callers
    /// can join it too. The boundary race (cycle ending between the check
    /// and the attach) degrades to a cheap fresh cycle — cursors just
    /// advanced, so it is a no-op round-trip.
    func syncNow() async {
        guard status != .inactive else { return }
        if let inFlight = cycleTask {
            await inFlight.value
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.runCycle(firstSync: false)
        }
        cycleTask = task
        await task.value
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
    /// for a record the relay already deleted. Buffered (undoable) deletions
    /// push right after tombstones and before the drain (push-then-commit):
    /// the delete lands first, so the drain's stale-update drop then clears
    /// any superseded queued update for the same id without pushing.
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
            try await pushBufferedDeletions()
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
    /// Relay-known-but-locally-missing category ids are adopted or remapped
    /// (see `resolveEntryCategoryIDs`) instead of stripped; snapshot-unknown
    /// ids are pruned with the remainder kept (logged, secret-free) — the
    /// merge never fails the cycle on a dangling join. When the server
    /// version is not newer but the local category set strictly supersets it
    /// via clean local rows, a healing update is enqueued instead (see
    /// `healCategoryForkIfNeeded`) and the local copy is kept.
    private func applyServer(_ entry: TimeEntry, serverCategories: [String: Category]) async throws {
        // Delete-wins (see applyServer(_:)): never resurrect a locally
        // deleted entry.
        if try await store.isLocallyDeleted(resource: "entry", recordID: entry.id) {
            Self.logger.info("sync pull skips locally deleted entry \(entry.id, privacy: .public)")
            return
        }
        if let local = try await store.entry(id: entry.id) {
            guard entry.updatedAt > local.updatedAt else {
                try await healCategoryForkIfNeeded(
                    server: entry, local: local, isTie: entry.updatedAt == local.updatedAt,
                    serverCategories: serverCategories
                )
                return
            }
        }
        var merged = entry
        merged.categoryIDs = try await resolveEntryCategoryIDs(entry, serverCategories: serverCategories)
        try await store.mergeEntry(merged)
    }

    /// Resolves an entry's category ids against the relay snapshot,
    /// order-preserved and deduped. Snapshot-unknown ids are dropped (logged);
    /// locally-present ids are kept; locally-deleted ids are dropped
    /// (delete-wins); an id missing locally but present in the snapshot is
    /// remapped to a same-name local rival when one exists (local-only
    /// rewrite — the caller merges with no outbox row, so it is never
    /// enqueued) or merged from the snapshot row otherwise. Shared by the
    /// pull merge and the conflict-adoption path so both converge identically.
    private func resolveEntryCategoryIDs(
        _ entry: TimeEntry,
        serverCategories: [String: Category]
    ) async throws -> [String] {
        var resolved: [String] = []
        for id in entry.categoryIDs {
            guard let snapshotRow = serverCategories[id] else {
                Self.logger.info("sync pull prunes unknown category \(id, privacy: .public) from entry \(entry.id, privacy: .public)")
                continue
            }
            if try await store.category(id: id) != nil {
                if !resolved.contains(id) {
                    resolved.append(id)
                }
                continue
            }
            if try await store.isLocallyDeleted(resource: "category", recordID: id) {
                Self.logger.info("sync pull skips locally deleted category \(id, privacy: .public) for entry \(entry.id, privacy: .public)")
                continue
            }
            if let rival = try await store.category(named: snapshotRow.name), rival.id != id {
                Self.logger.info("sync pull remaps category \(id, privacy: .public) to local rival \(rival.id, privacy: .public) for entry \(entry.id, privacy: .public)")
                if !resolved.contains(rival.id) {
                    resolved.append(rival.id)
                }
                continue
            }
            try await store.mergeCategory(snapshotRow)
            if !resolved.contains(id) {
                resolved.append(id)
            }
        }
        return resolved
    }

    /// Heals a silently forked category set: the server version is not newer
    /// (tie or older, so LWW keeps local) but the local category set strictly
    /// supersets the server set. Only extras backed by existing clean local
    /// rows (none pending deletion) count; when the server holds any id the
    /// local copy lacks, the sets are incomparable and healing is skipped
    /// entirely. The healed copy carries the full local set with a bumped
    /// `updatedAt` (strictly newer even under second-precision truncation, so
    /// the relay PATCH LWW guard passes) and `updateEntry` enqueues the
    /// update for the next drain. When the update loses its LWW race, there
    /// is nothing to heal. Secret-free logs only.
    ///
    /// The mirror case heals too: on a TIE the server set strictly supersets
    /// the local set. Sub-millisecond wire precision (relay stamps
    /// microseconds, the wire codec keeps milliseconds) makes a server
    /// `.385574` tie with a local `.385` forever, so a join lost by an
    /// older buggy pull would otherwise never reconverge. The server ids
    /// are adopted locally (remap-aware, no outbox row — the relay already
    /// holds this version), mirroring the rival-remap rewrite. A
    /// server-older superset is a legitimate relay prune (delete-wins on
    /// another device) and keeps local.
    private func healCategoryForkIfNeeded(
        server: TimeEntry,
        local: TimeEntry,
        isTie: Bool,
        serverCategories: [String: Category]
    ) async throws {
        let serverSet = Set(server.categoryIDs)
        let localSet = Set(local.categoryIDs)
        if isTie, localSet != serverSet, serverSet.isSuperset(of: localSet) {
            var healed = local
            healed.categoryIDs = try await resolveEntryCategoryIDs(server, serverCategories: serverCategories)
            guard healed.categoryIDs != local.categoryIDs else { return }
            try await store.mergeEntry(healed)
            Self.logger.info("sync pull heals category fork on entry \(local.id, privacy: .public)")
            return
        }
        let extras = localSet.subtracting(serverSet)
        guard !extras.isEmpty, serverSet.isSubset(of: localSet) else { return }
        var cleanExtras = false
        for id in local.categoryIDs where extras.contains(id) {
            guard try await store.category(id: id) != nil else { continue }
            if try await store.isLocallyDeleted(resource: "category", recordID: id) { continue }
            cleanExtras = true
            break
        }
        guard cleanExtras else { return }
        var healed = local
        healed.updatedAt = max(
            Date(),
            max(server.updatedAt.addingTimeInterval(1), local.updatedAt.addingTimeInterval(1))
        )
        guard try await store.updateEntry(healed) else { return }
        Self.logger.info("sync pull heals category fork on entry \(local.id, privacy: .public)")
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

    /// Pushes buffered (undoable) deletions to the relay before the drain
    /// (push-then-commit, propagate-buffered-deletes D1/D2): one `DELETE`
    /// per snapshotted record; a buffer row is dropped only after ALL its
    /// records pushed successfully, so a partial failure keeps the whole row
    /// buffered and undoable for the next cycle — never half-committed. A
    /// 404 is success (already gone); any other error fails the cycle loudly
    /// with the row still buffered. While the loop runs, undo of buffered
    /// rows is refused (D3 guard); the flag is always cleared, even on
    /// error, so undo can never wedge shut.
    private func pushBufferedDeletions() async throws {
        let pending = try await store.bufferedDeletions()
        guard !pending.isEmpty else { return }
        await store.setUndoPushInFlight(true)
        do {
            for bufferID in Set(pending.map(\.bufferID)) {
                for deletion in pending where deletion.bufferID == bufferID {
                    do {
                        switch deletion.resource {
                        case "entry":
                            try await remote.deleteEntry(id: deletion.recordID)
                        case "category":
                            try await remote.deleteCategory(id: deletion.recordID)
                        default:
                            Self.logger.error("sync ignores unknown buffered resource \(deletion.resource, privacy: .public)")
                            throw SyncError.unknownOutboxOp(deletion.resource, "delete")
                        }
                    } catch let error as APIError where error.code == "not_found" {
                        // Already gone on the relay — converged, nothing to do.
                        Self.logger.info("sync buffered delete 404-as-success \(deletion.resource, privacy: .public) \(deletion.recordID, privacy: .public)")
                    }
                }
                try await store.undoBufferRemove(id: bufferID)
            }
            Self.logger.info("sync pushed \(pending.count) buffered deletions")
        } catch {
            await store.setUndoPushInFlight(false)
            throw error
        }
        await store.setUndoPushInFlight(false)
    }

    /// Drains the outbox in dependency order, one HTTP request per row.
    /// `category` rows push before `entry` rows (`POST /entries` rejects
    /// unknown `category_ids` with 422, so referenced categories must exist
    /// on the relay first); `created_at, id` order is preserved within each
    /// resource. POST is idempotent on `id` and PATCH carries `updated_at`
    /// (LWW), so a replay after a crash or relapse produces the same result
    /// as the first attempt.
    private func drainOutbox() async throws {
        let rows = try await store.outboxRows()
        // One relay category snapshot per drain, fetched lazily: only when
        // the drain actually holds an entry create/update row.
        var relayCategoryIDs: Set<String>?
        for queuedRow in Self.orderedForDrain(rows) {
            // Conflict recovery can remove or rewrite a later row while this
            // drain is still iterating the initial snapshot. Always push the
            // current persisted payload rather than a stale in-memory copy.
            guard var row = try await store.outboxRow(id: queuedRow.id) else {
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
            if row.resource == "entry" && (row.op == "create" || row.op == "update") {
                if relayCategoryIDs == nil {
                    let snapshot = try await remote.fetchCategories()
                    relayCategoryIDs = Set(snapshot.map(\.id))
                }
                var knownIDs = relayCategoryIDs ?? []
                row = try await ensureEntryCategories(for: row, knownIDs: &knownIDs)
                relayCategoryIDs = knownIDs
            }
            do {
                try await push(row)
                try await store.removeOutboxRow(id: row.id)
            } catch let error as APIError {
                if try await resolvePushError(row, error: error) {
                    continue
                }
                throw error
            }
        }
    }

    /// Dependency order for the drain snapshot: `category` rows before
    /// `entry` rows, `created_at, id` within each resource.
    private static func orderedForDrain(_ rows: [OutboxRow]) -> [OutboxRow] {
        rows.sorted { lhs, rhs in
            let leftRank = drainRank(lhs.resource)
            let rightRank = drainRank(rhs.resource)
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    /// Resolves one failed push. Returns true when the row is resolved and
    /// the drain may continue; false rethrows the original error loudly.
    private func resolvePushError(_ row: OutboxRow, error: APIError) async throws -> Bool {
        switch error.code {
        case "conflict", "category_exists", "duplicate_import":
            try await resolveConflict(row, code: error.code ?? "", details: error.details)
            return true
        case "not_found":
            // 404 on DELETE → treat as success (already gone). A push
            // for a tombstone-less relay-missing record resurrects
            // from local data and retries once (see
            // resurrectAndRetry) instead of wedging the cycle on a
            // doomed retry; anything else still throws.
            if row.op == "delete" {
                try await store.removeOutboxRow(id: row.id)
                return true
            }
            return try await resurrectAndRetry(row)
        case "validation_error":
            // 422 unknown `category_ids` on entry create/update →
            // prune to the relay-known remainder and retry once (see
            // healUnknownCategoryIDs). Anything else still throws.
            guard error.details["category_ids"] != nil else { return false }
            return try await healUnknownCategoryIDs(row)
        default:
            return false
        }
    }

    /// Drain ordering rank: categories push before entries so `POST /entries`
    /// never references a category the relay has not seen yet. Unknown
    /// resources drain last so the push path still rejects them loudly.
    private static func drainRank(_ resource: String) -> Int {
        switch resource {
        case "category":
            return 0
        case "entry":
            return 1
        default:
            return 2
        }
    }

    /// Ensures every category id referenced by an entry create/update exists
    /// on the relay before the entry push, so the push carries the full set
    /// (no 422, no prune, no local loss). Ids missing from the per-drain
    /// cached relay snapshot but present locally and not pending deletion are
    /// created on the relay first (idempotent; a `category_exists` 409 remaps
    /// local references to the winning id and the entry push re-reads its
    /// payload). Dangling ids (no local row) and delete-wins ids are left
    /// for the last-resort prune-and-retry heal. Any other creation error
    /// throws, aborting the cycle with the row still queued — nothing is ever
    /// silently pruned here. Returns the row to push (possibly re-read after
    /// a remap rewrote its payload).
    private func ensureEntryCategories(for row: OutboxRow, knownIDs: inout Set<String>) async throws -> OutboxRow {
        var currentRow = row
        // At most two passes: the initial scan plus one re-check after a
        // remap (the entry then carries the winner id).
        for _ in 0..<2 {
            let entry = try decodePayload(currentRow, as: TimeEntry.self)
            var didRemap = false
            for id in entry.categoryIDs where !knownIDs.contains(id) {
                guard let local = try await store.category(id: id) else { continue }
                if try await store.isLocallyDeleted(resource: "category", recordID: id) { continue }
                do {
                    try await remote.createCategory(local)
                    knownIDs.insert(id)
                } catch let error as APIError where error.code == "category_exists" {
                    guard let winningID = error.details["id"] else { throw error }
                    try await remapCategoryReferences(from: id, to: winningID)
                    knownIDs.insert(winningID)
                    if let fresh = try await store.outboxRow(id: row.id) {
                        currentRow = fresh
                    }
                    didRemap = true
                    break
                }
            }
            if !didRemap { break }
        }
        return currentRow
    }

    /// Recovers an entry create/update rejected with 422 `category_ids`:
    /// fetches the relay categories, drops unknown ids from the queued
    /// payload keeping the remainder (secret-free log), rewrites the outbox
    /// payload, retries the push exactly once, and clears the row on success.
    /// Returns whether the row was resolved (anything else rethrows loudly).
    /// The following pull converges the local copy via LWW (the pruned server
    /// version is newer), so local joins are left untouched here.
    private func healUnknownCategoryIDs(_ row: OutboxRow) async throws -> Bool {
        guard row.resource == "entry", row.op == "create" || row.op == "update" else {
            return false
        }
        guard let current = try await store.outboxRow(id: row.id) else {
            return true
        }
        let entry: TimeEntry
        do {
            entry = try decodePayload(current, as: TimeEntry.self)
        } catch {
            return false
        }
        guard !entry.categoryIDs.isEmpty else { return false }
        let snapshot = try await remote.fetchCategories()
        let knownIDs = Set(snapshot.map(\.id))
        let prunedIDs = entry.categoryIDs.filter { knownIDs.contains($0) }
        guard prunedIDs.count != entry.categoryIDs.count else {
            return false
        }
        var pruned = entry
        pruned.categoryIDs = prunedIDs
        for id in entry.categoryIDs where !knownIDs.contains(id) {
            Self.logger.info("sync drain prunes unknown category \(id, privacy: .public) from entry \(entry.id, privacy: .public)")
        }
        try await store.rewriteOutboxPayload(resource: row.resource, recordID: row.recordID, payload: pruned)
        if row.op == "create" {
            try await remote.createEntry(pruned)
        } else {
            try await remote.updateEntry(pruned)
        }
        try await store.removeOutboxRow(id: row.id)
        return true
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

    /// Resolves a server entry's category ids before a conflict-adoption
    /// merge, identically to the pull path (see `resolveEntryCategoryIDs`):
    /// relay-known-but-locally-missing ids are adopted or remapped to a
    /// same-name local rival, snapshot-unknown ids are dropped with the
    /// remainder kept (secret-free log), and the merge never fails the cycle.
    private func prunedEntry(_ entry: TimeEntry) async throws -> TimeEntry {
        guard !entry.categoryIDs.isEmpty else { return entry }
        let snapshot = try await remote.fetchCategories()
        let serverCategories = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        var resolved = entry
        resolved.categoryIDs = try await resolveEntryCategoryIDs(entry, serverCategories: serverCategories)
        return resolved
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
