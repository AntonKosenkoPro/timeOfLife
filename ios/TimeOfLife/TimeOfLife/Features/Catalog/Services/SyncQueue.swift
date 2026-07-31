import Foundation
import os

/// A pending catalog mutation queued for sync. Generic over the resource kind
/// (activity/category, plus an `entry` stub owned by story 1-3). Persisted to
/// disk so the queue survives relaunch and replays on reconnect (F12/R1).
struct SyncMutation: Codable, Sendable, Equatable {
    enum Resource: String, Codable, Sendable {
        case activity
        case category
        case entry // forward-looking stub; owned by 1-3
    }

    enum Method: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    /// Local operation id (for dedup/removal).
    let id: UUID
    /// The id of the affected activity/category/entry.
    let resourceId: UUID
    let resource: Resource
    let method: Method
    /// Encoded `Activity`/`Category` (empty for deletes).
    let payload: Data
    let updatedAt: Date
    var attempts: Int

    init(resourceId: UUID,
         resource: Resource,
         method: Method,
         updatedAt: Date,
         id: UUID = UUID(),
         payload: Data = Data(),
         attempts: Int = 0) {
        self.id = id
        self.resourceId = resourceId
        self.resource = resource
        self.method = method
        self.payload = payload
        self.updatedAt = updatedAt
        self.attempts = attempts
    }
}

extension SyncMutation {
    /// Convenience for a create carrying an encoded record.
    static func create(resource: Resource, resourceId: UUID, payload: Data, updatedAt: Date) -> SyncMutation {
        SyncMutation(resourceId: resourceId, resource: resource, method: .create, updatedAt: updatedAt, payload: payload)
    }

    static func update(resource: Resource, resourceId: UUID, payload: Data, updatedAt: Date) -> SyncMutation {
        SyncMutation(resourceId: resourceId, resource: resource, method: .update, updatedAt: updatedAt, payload: payload)
    }

    static func delete(resource: Resource, resourceId: UUID, updatedAt: Date) -> SyncMutation {
        SyncMutation(resourceId: resourceId, resource: resource, method: .delete, updatedAt: updatedAt)
    }
}

/// File-based offline sync queue. Replay is safe: idempotent POST, 404 on
/// DELETE, 409 conflict adopts server version, 409 *_exists re-maps refs.
actor SyncQueue {
    private static let maxAttempts = 5

    private let url: URL

    init(url: URL? = nil) {
        let base = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TimeOfLife", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife", isDirectory: true)
        self.url = base.appendingPathComponent("syncQueue.json")
    }

    // MARK: - Queue ops

    func enqueue(_ mutation: SyncMutation) async throws {
        try ensureDirectory()
        var pending = try load()
        pending.append(mutation)
        try save(pending)
    }

    func pending() async -> [SyncMutation] {
        (try? load()) ?? []
    }

    func remove(_ id: UUID) async throws {
        var pending = try load()
        pending.removeAll { $0.id == id }
        try save(pending)
    }

    func clear() async throws {
        try save([])
    }

    // MARK: - Replay

    /// Replays pending mutations in FIFO order. On offline, stops and leaves
    /// the remaining entries (retried on the next connectivity change).
    func replay(
        using repository: CatalogRepository,
        store: CatalogStoring,
        connectivity: Connectivity
    ) async {
        guard await connectivity.isConnected else { return }
        let pending = (try? load()) ?? []
        var remaining: [SyncMutation] = []
        var stopped = false

        for mutation in pending {
            if stopped {
                remaining.append(mutation)
                continue
            }
            // Re-check connectivity before each mutation in case the
            // network dropped mid-replay.
            guard await connectivity.isConnected else {
                remaining.append(mutation)
                stopped = true
                continue
            }
            let outcome = await replayOne(mutation, using: repository, store: store)
            switch outcome {
            case .done:
                continue
            case .retry:
                // Increment attempts and drop if exceeded max retries.
                var m = mutation
                m.attempts += 1
                if m.attempts >= Self.maxAttempts {
                    // Log and drop — the mutation will never succeed.
                    continue
                }
                remaining.append(m)
            case .stop:
                remaining.append(mutation)
                stopped = true
            }
        }

        // Reload from disk to capture any mutations enqueued during replay
        // (e.g. cascaded activity-updates from remapCategory).
        let onDisk = (try? load()) ?? []
        let newMutations = onDisk.filter { m in
            !pending.contains { $0.id == m.id }
        }
        try? save(remaining + newMutations)
    }

    // MARK: - Per-mutation dispatch

    private enum ReplayOutcome { case done, retry, stop }

    private func replayOne(
        _ mutation: SyncMutation,
        using repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        switch (mutation.resource, mutation.method) {
        case (.activity, .create):
            return await replayActivityCreate(mutation, repository: repository, store: store)
        case (.activity, .update):
            return await replayActivityUpdate(mutation, repository: repository, store: store)
        case (.activity, .delete):
            return await replayActivityDelete(mutation, repository: repository)
        case (.category, .create):
            return await replayCategoryCreate(mutation, repository: repository, store: store)
        case (.category, .update):
            return await replayCategoryUpdate(mutation, repository: repository, store: store)
        case (.category, .delete):
            return await replayCategoryDelete(mutation, repository: repository)
        case (.entry, .create), (.entry, .update), (.entry, .delete):
            // Entries are owned by story 1-3; never enqueued here.
            return .done
        }
    }

    // MARK: Activity replay

    private func replayActivityCreate(
        _ mutation: SyncMutation,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        guard let activity = decode(Activity.self, mutation.payload) else { return .done }
        do {
            let canonical = try await repository.createActivity(activity)
            await store.upsertActivity(canonical)
            return .done
        } catch CatalogError.activityExists(let existingId, _) {
            await remapActivity(from: activity.id, to: existingId, repository: repository, store: store)
            return .done
        } catch CatalogError.validation {
            return .done // 422 will never succeed on retry
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayActivityUpdate(
        _ mutation: SyncMutation,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        guard let activity = decode(Activity.self, mutation.payload) else { return .done }
        do {
            let canonical = try await repository.updateActivity(activity)
            await store.upsertActivity(canonical)
            return .done
        } catch CatalogError.conflict {
            // Keep-latest: adopt the server's current version (re-fetch).
            if let server = try? await repository.getActivity(activity.id) {
                await store.upsertActivity(server)
            }
            return .done
        } catch CatalogError.activityExists(let existingId, _) {
            await remapActivity(from: activity.id, to: existingId, repository: repository, store: store)
            return .done
        } catch CatalogError.validation {
            return .done
        } catch CatalogError.notFound {
            return .done // deleted server-side; drop the stale update
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayActivityDelete(_ mutation: SyncMutation, repository: CatalogRepository) async -> ReplayOutcome {
        do {
            try await repository.deleteActivity(mutation.resourceId)
            return .done
        } catch CatalogError.notFound {
            return .done // 404 on DELETE is success
        } catch CatalogError.validation {
            return .done
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func remapActivity(
        from oldId: UUID,
        to newId: UUID,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async {
        if let survivor = try? await repository.getActivity(newId) {
            await store.upsertActivity(survivor)
        }
        await store.removeActivity(oldId)
        await store.replaceActivityReferences(from: oldId, to: newId)
    }

    // MARK: Category replay

    private func replayCategoryCreate(
        _ mutation: SyncMutation,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        guard let category = decode(Category.self, mutation.payload) else { return .done }
        do {
            let canonical = try await repository.createCategory(category)
            await store.upsertCategory(canonical)
            return .done
        } catch CatalogError.categoryExists(let existingId, _) {
            await remapCategory(from: category.id, to: existingId, repository: repository, store: store)
            return .done
        } catch CatalogError.validation {
            return .done
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayCategoryUpdate(
        _ mutation: SyncMutation,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        guard let category = decode(Category.self, mutation.payload) else { return .done }
        do {
            let canonical = try await repository.updateCategory(category)
            await store.upsertCategory(canonical)
            return .done
        } catch CatalogError.conflict {
            if let server = try? await repository.getCategory(category.id) {
                await store.upsertCategory(server)
            }
            return .done
        } catch CatalogError.categoryExists(let existingId, _) {
            await remapCategory(from: category.id, to: existingId, repository: repository, store: store)
            return .done
        } catch CatalogError.validation {
            return .done
        } catch CatalogError.notFound {
            return .done
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayCategoryDelete(_ mutation: SyncMutation, repository: CatalogRepository) async -> ReplayOutcome {
        do {
            try await repository.deleteCategory(mutation.resourceId)
            return .done
        } catch CatalogError.notFound {
            return .done
        } catch CatalogError.validation {
            return .done
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func remapCategory(
        from oldId: UUID,
        to newId: UUID,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async {
        // Capture affected activities BEFORE the re-map so we can enqueue
        // sync mutations for the cascaded category id replacement.
        let affected = await store.loadActivities().filter {
            $0.categoryIds.contains(oldId)
        }
        if let survivor = try? await repository.getCategory(newId) {
            await store.upsertCategory(survivor)
        }
        await store.removeCategory(oldId)
        await store.replaceCategoryReferences(from: oldId, to: newId)
        // Enqueue update mutations for activities whose categoryIds were
        // rewritten by replaceCategoryReferences.
        for activity in affected {
            var updated = activity
            updated.categoryIds.removeAll { $0 == oldId }
            if !updated.categoryIds.contains(newId) {
                updated.categoryIds.append(newId)
            }
            if let data = try? JSONEncoder().encode(updated) {
                try? await enqueue(
                    .update(resource: .activity, resourceId: updated.id,
                            payload: data, updatedAt: updated.updatedAt)
                )
            }
        }
    }

    // MARK: - File helpers

    private func ensureDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: nil
        )
    }

    private func load() throws -> [SyncMutation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([SyncMutation].self, from: data)
        } catch {
            let ts = ISO8601DateFormatter().string(from: Date())
            let dir = url.deletingLastPathComponent()
            let quarantined = dir.appendingPathComponent("syncQueue.corrupted.\(ts).json")
            try? FileManager.default.moveItem(at: url, to: quarantined)
            return []
        }
    }

    private func save(_ mutations: [SyncMutation]) throws {
        let data = try JSONEncoder().encode(mutations)
        try data.write(to: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? { try? JSONDecoder().decode(type, from: data) }
}
