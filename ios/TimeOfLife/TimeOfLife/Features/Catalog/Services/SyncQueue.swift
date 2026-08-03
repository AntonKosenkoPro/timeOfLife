import Foundation
import os

struct SyncMutation: Codable, Sendable, Equatable {
    enum Resource: String, Codable, Sendable {
        case activity
        case category
        case entry
    }

    enum Method: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    let id: UUID
    let resourceId: UUID
    let resource: Resource
    let method: Method
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

actor SyncQueue {
    private static let maxAttempts = 5
    private static let log = Logger(subsystem: "com.timeoflife", category: "sync")

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
    @discardableResult
    func replay(using repository: CatalogRepository,
                store: CatalogStoring,
                connectivity: Connectivity,
                entryStore: TimerStoring? = nil,
                entriesRepository: EntriesRepository? = nil) async -> Set<UUID> {
        guard await connectivity.isConnected else { return [] }
        let context = ReplayContext(repository: repository, store: store, entryStore: entryStore, entriesRepository: entriesRepository)
        let pending = (try? load()) ?? []
        var remaining: [SyncMutation] = []
        var stopped = false
        var conflictedActivityIds: Set<UUID> = []

        for mutation in pending {
            if stopped {
                remaining.append(mutation)
                continue
            }
            guard await connectivity.isConnected else {
                remaining.append(mutation)
                stopped = true
                continue
            }
            let outcome = await replayOne(mutation, context: context)
            switch outcome {
            case .done:
                continue
            case let .conflict(activityId):
                conflictedActivityIds.insert(activityId)
                continue
            case .retry:
                var m = mutation
                m.attempts += 1
                if m.attempts >= Self.maxAttempts {
                    Self.log.warning("dropping mutation after \(Self.maxAttempts) attempts: \(m.resource.rawValue) \(m.method.rawValue) id=\(m.resourceId.uuidString)")
                    continue
                }
                remaining.append(m)
            case .stop:
                remaining.append(mutation)
                stopped = true
            }
        }

        let onDisk = (try? load()) ?? []
        let newMutations = onDisk.filter { m in
            !pending.contains { $0.id == m.id }
        }
        try? save(remaining + newMutations)
        return conflictedActivityIds
    }

    private enum ReplayOutcome { case done, conflict(UUID), retry, stop }

    private struct ReplayContext {
        let repository: CatalogRepository
        let store: CatalogStoring
        let entryStore: TimerStoring?
        let entriesRepository: EntriesRepository?
    }

    private func replayOne(_ mutation: SyncMutation, context: ReplayContext) async -> ReplayOutcome {
        switch (mutation.resource, mutation.method) {
        case (.activity, .create): return await replayActivityCreate(mutation, context: context)
        case (.activity, .update): return await replayActivityUpdate(mutation, context: context)
        case (.activity, .delete): return await replayActivityDelete(mutation, repository: context.repository)
        case (.category, .create): return await replayCategoryCreate(mutation, repository: context.repository, store: context.store)
        case (.category, .update): return await replayCategoryUpdate(mutation, repository: context.repository, store: context.store)
        case (.category, .delete): return await replayCategoryDelete(mutation, repository: context.repository)
        case (.entry, .delete): return await replayEntryDelete(mutation, context: context)
        case (.entry, .create), (.entry, .update): return .done
        }
    }

    // MARK: Activity replay

    private func replayActivityCreate(_ mutation: SyncMutation, context: ReplayContext) async -> ReplayOutcome {
        guard let activity = decode(Activity.self, mutation.payload) else {
            Self.log.warning("drop activity create: payload decode failure id=\(mutation.resourceId.uuidString)")
            return .done
        }
        do {
            let canonical = try await context.repository.createActivity(activity)
            await context.store.upsertActivity(canonical)
            return .done
        } catch CatalogError.activityExists(let existingId, _) {
            return await remapActivity(from: activity.id, to: existingId, context: context) ? .done : .retry
        } catch CatalogError.validation {
            Self.log.warning("drop activity create: 422 validation id=\(mutation.resourceId.uuidString)")
            return .done // 422 will never succeed on retry
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayActivityUpdate(_ mutation: SyncMutation, context: ReplayContext) async -> ReplayOutcome {
        guard let activity = decode(Activity.self, mutation.payload) else {
            Self.log.warning("drop activity update: payload decode failure id=\(mutation.resourceId.uuidString)")
            return .done
        }
        do {
            let canonical = try await context.repository.updateActivity(activity)
            await context.store.upsertActivity(canonical)
            return .done
        } catch CatalogError.conflict {
            if let server = try? await context.repository.getActivity(activity.id) {
                await context.store.upsertActivity(server)
            }
            return .conflict(activity.id)
        } catch CatalogError.activityExists(let existingId, _) {
            return await remapActivity(from: activity.id, to: existingId, context: context) ? .done : .retry
        } catch CatalogError.validation {
            Self.log.warning("drop activity update: 422 validation id=\(mutation.resourceId.uuidString)")
            return .done
        } catch CatalogError.notFound {
            Self.log.warning("drop activity update: 404 not found id=\(mutation.resourceId.uuidString)")
            return .done
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
            Self.log.warning("drop activity delete: 404 not found id=\(mutation.resourceId.uuidString)")
            return .done
        } catch CatalogError.validation {
            Self.log.warning("drop activity delete: 422 validation id=\(mutation.resourceId.uuidString)")
            return .done
        } catch CatalogError.offline {
            return .stop
        } catch {
            return .retry
        }
    }

    private func replayEntryDelete(_ mutation: SyncMutation, context: ReplayContext) async -> ReplayOutcome {
        guard let entriesRepository = context.entriesRepository else { return .done }
        do { try await entriesRepository.delete(id: mutation.resourceId); return .done } catch let error as APIError {
            if case let .server(code, _, _) = error, code == "not_found" { return .done }
            if case .offline = error { return .stop }
            return .retry
        } catch { return .retry }
    }

    private func remapActivity(from oldId: UUID, to newId: UUID, context: ReplayContext) async -> Bool {
        if let survivor = try? await context.repository.getActivity(newId) {
            await context.store.upsertActivity(survivor)
        }
        do {
            try await context.entryStore?.replaceActivityId(from: oldId, to: newId)
        } catch {
            return false
        }
        await context.store.removeActivity(oldId)
        await context.store.replaceActivityReferences(from: oldId, to: newId)
        return true
    }

    // MARK: Category replay

    private func replayCategoryCreate(
        _ mutation: SyncMutation,
        repository: CatalogRepository,
        store: CatalogStoring
    ) async -> ReplayOutcome {
        guard let category = decode(Category.self, mutation.payload) else {
            Self.log.warning("drop category create: payload decode failure id=\(mutation.resourceId.uuidString)")
            return .done
        }
        do {
            let canonical = try await repository.createCategory(category)
            await store.upsertCategory(canonical)
            return .done
        } catch CatalogError.categoryExists(let existingId, _) {
            await remapCategory(from: category.id, to: existingId, repository: repository, store: store)
            return .done
        } catch CatalogError.validation {
            Self.log.warning("drop category create: 422 validation id=\(mutation.resourceId.uuidString)")
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
        guard let category = decode(Category.self, mutation.payload) else {
            Self.log.warning("drop category update: payload decode failure id=\(mutation.resourceId.uuidString)")
            return .done
        }
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
            Self.log.warning("drop category update: 422 validation id=\(mutation.resourceId.uuidString)")
            return .done
        } catch CatalogError.notFound {
            Self.log.warning("drop category update: 404 not found id=\(mutation.resourceId.uuidString)")
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
        await store.replaceCategoryReferences(from: oldId, to: newId)
        await store.removeCategory(oldId)
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

    private func ensureDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
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

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
