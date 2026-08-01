import Foundation
import Combine
import OSLog

/// Orchestrates `CatalogStore` + `CatalogRepository` + `SyncQueue` +
/// `UndoBuffer` + `Connectivity`. The single entry point for catalog mutations:
/// applies optimistically to the store, enqueues sync, holds deletions in the
/// undo buffer, and replays the queue on reconnect. Mirrors `TimerService`'s
/// store + repository + connectivity composition.
@MainActor
final class CatalogService: ObservableObject {
    let store: CatalogStoring
    let repository: CatalogRepository
    let syncQueue: SyncQueue
    let undoBuffer: UndoBuffer
    let connectivity: Connectivity
    let entryStore: TimerStoring?

    /// Published revision counter bumped on every store mutation so observers
    /// (e.g. TimerViewModel) can react to catalog changes.
    @Published private(set) var storeRevision: UInt64 = 0

    var onSyncCompleted: (() async -> Void)?
    private var conflictedActivityIds: Set<UUID> = []

    private var connectivityCancellable: AnyCancellable?

    init(
        store: CatalogStoring,
        repository: CatalogRepository,
        syncQueue: SyncQueue,
        undoBuffer: UndoBuffer,
        connectivity: Connectivity,
        entryStore: TimerStoring? = nil
    ) {
        self.store = store
        self.repository = repository
        self.syncQueue = syncQueue
        self.undoBuffer = undoBuffer
        self.connectivity = connectivity
        self.entryStore = entryStore

        // After the 30s undo window, commit the deletion locally + enqueue a
        // server DELETE. The buffer is in-memory; this is the only place the
        // held deletion becomes a real (persisted) deletion.
        undoBuffer.onCommit = { [weak self] item in
            await self?.commitDeletion(item)
        }

        // Replay the queue whenever connectivity flips back to online.
        connectivityCancellable = connectivity.$isConnected
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in await self?.syncNow() }
            }
    }

    // MARK: - Activities

    /// Applies an activity optimistically and enqueues a create mutation.
    /// The activity's `id` MUST be a client-generated UUID v7 (F9).
    /// Returns the server's canonical version if the sync completed, or the
    /// optimistic version if still pending.
    @discardableResult
    func createActivity(_ activity: Activity) async throws -> Activity {
        await store.upsertActivity(activity)
        storeRevision &+= 1
        try await syncQueue.enqueue(
            .create(resource: .activity, resourceId: activity.id,
                    payload: encode(activity), updatedAt: activity.updatedAt)
        )
        await syncNow()
        // After sync, the optimistic activity may have been remapped (409
        // activity_exists). If it was removed, return the survivor (found by
        // name) instead of the dead optimistic record.
        if let stored = await store.activity(activity.id) { return stored }
        if let survivor = await store.activity(named: activity.name) { return survivor }
        return activity
    }

    /// Applies an update optimistically (LWW: `updated_at` is carried) and
    /// enqueues a sync mutation.
    /// Returns the server's canonical version if the sync completed, or the
    /// optimistic version if still pending.
    @discardableResult
    func updateActivity(_ activity: Activity) async throws -> Activity {
        await store.upsertActivity(activity)
        storeRevision &+= 1
        try await syncQueue.enqueue(
            .update(resource: .activity, resourceId: activity.id,
                    payload: encode(activity), updatedAt: activity.updatedAt)
        )
        await syncNow()
        return await store.activity(activity.id) ?? activity
    }

    /// Enters a deletion into the undo buffer. The deletion is NOT committed to
    /// the store or enqueued while held (AC #6 / INTERACTIONS.md); the UI hides
    /// the item via `undoBuffer.state`. After the 30s window, `onCommit`
    /// removes it locally and enqueues a `DELETE`.
    func deleteActivity(_ activity: Activity) async throws {
        undoBuffer.record(.activity(activity))
    }

    // MARK: - Categories

    func createCategory(_ category: Category) async throws {
        await store.upsertCategory(category)
        storeRevision &+= 1
        try await syncQueue.enqueue(
            .create(resource: .category, resourceId: category.id,
                    payload: encode(category), updatedAt: category.updatedAt)
        )
        await syncNow()
    }

    func updateCategory(_ category: Category) async throws {
        await store.upsertCategory(category)
        storeRevision &+= 1
        try await syncQueue.enqueue(
            .update(resource: .category, resourceId: category.id,
                    payload: encode(category), updatedAt: category.updatedAt)
        )
        await syncNow()
    }

    func deleteCategory(_ category: Category) async throws {
        undoBuffer.record(.category(category))
    }

    // MARK: - Undo

    /// Reverses the most recent undoable deletion within the 30s window:
    /// re-inserts the item into the store and clears the buffer. On re-insert
    /// failure, re-holds so the user can retry (INTERACTIONS.md "Undo API
    /// failure"). Returns the restored item, or `nil` if nothing is restorable.
    func undo() async -> UndoableItem? {
        guard let item = undoBuffer.undo() else { return nil }
        switch item {
        case .activity(let activity):
            await store.upsertActivity(activity)
        case .category(let category):
            await store.upsertCategory(category)
        case .activityWithEntries(let activity, _):
            await store.upsertActivity(activity)
            // Entry restore is owned by 1-3.
        case .entryOnly:
            // Entry deletion/restoration is owned by the time-entry feature.
            break
        }
        storeRevision &+= 1
        return item
    }

    // MARK: - Reuse (F3/F4)

    /// Case-insensitive, whitespace-trimmed activity lookup so the timer screen
    /// (1-3) can decide reuse vs auto-create. Returns the existing activity.
    /// Skips records currently held in the undo buffer (about to be deleted).
    func caseInsensitiveReuse(named name: String) async -> Activity? {
        guard let activity = await store.activity(named: name) else { return nil }
        if undoBuffer.heldIds.contains(activity.id) { return nil }
        return activity
    }

    // MARK: - Seeding (F6)

    /// Primitive the first-run flow (1-2/1-5) calls to seed localized
    /// categories. Writes via the store + enqueues POSTs. Seeding *logic*
    /// (first-run detection, localized names) is out of scope here.
    /// On failure, logs the error and continues with remaining categories
    /// so a partial seed doesn't block first-run.
    func seedCategories(_ categories: [Category]) async throws {
        var lastError: Error?
        for category in categories {
            do {
                await store.upsertCategory(category)
                try await syncQueue.enqueue(
                    .create(resource: .category, resourceId: category.id,
                            payload: encode(category), updatedAt: category.updatedAt)
                )
            } catch {
                os_log(.error, "seedCategories failed for %{public}@: %{public}@",
                       category.name, error.localizedDescription)
                lastError = error
            }
        }
        await syncNow()
        if let lastError { throw lastError }
    }

    // MARK: - Sync

    /// Drains the queue now (no-op while offline). Called after each optimistic
    /// mutation and on reconnect.
    func syncNow() async {
        let conflicts = await syncQueue.replay(
            using: repository,
            store: store,
            connectivity: connectivity,
            entryStore: entryStore
        )
        conflictedActivityIds.formUnion(conflicts)
        storeRevision &+= 1
        await onSyncCompleted?()
    }

    func consumeActivityConflicts() -> Set<UUID> {
        defer { conflictedActivityIds.removeAll() }
        return conflictedActivityIds
    }

    // MARK: - Commit (undo window elapsed)

    private func commitDeletion(_ item: UndoableItem) async {
        switch item {
        case .activity(let activity):
            await store.removeActivity(activity.id)
            storeRevision &+= 1
            try? await syncQueue.enqueue(
                .delete(resource: .activity, resourceId: activity.id, updatedAt: Date())
            )
        case .category(let category):
            // Capture affected activities BEFORE removal so we can enqueue
            // sync mutations for the cascaded category id removal.
            let affected = await store.loadActivities().filter {
                $0.categoryIds.contains(category.id)
            }
            await store.removeCategory(category.id)
            storeRevision &+= 1
            try? await syncQueue.enqueue(
                .delete(resource: .category, resourceId: category.id, updatedAt: Date())
            )
            // Enqueue update mutations for activities whose categoryIds
            // were cascaded by removeCategory.
            for activity in affected {
                var updated = activity
                updated.categoryIds.removeAll { $0 == category.id }
                try? await syncQueue.enqueue(
                    .update(resource: .activity, resourceId: updated.id,
                            payload: encode(updated), updatedAt: updated.updatedAt)
                )
            }
        case .activityWithEntries(let activity, _):
            // Activity + its entries deleted as a unit (F10); entries owned by 1-3.
            await store.removeActivity(activity.id)
            storeRevision &+= 1
            try? await syncQueue.enqueue(
                .delete(resource: .activity, resourceId: activity.id, updatedAt: Date())
            )
        case .entryOnly:
            // Entry deletion is owned by the time-entry feature.
            break
        }
    }

    // MARK: - Encoding

    /// Encodes a record for the queue. Uses deferred-to-date (matching the
    /// store), so `SyncQueue` decodes with the same strategy. Throws on
    /// encoding failure so the caller can surface the error rather than
    /// silently enqueueing empty data.
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
