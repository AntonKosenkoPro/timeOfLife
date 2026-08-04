import Foundation

/// Errors produced by the `SyncCoordinator` while resolving a single record.

/// Errors produced by the `SyncCoordinator` while resolving a single record.
/// These are stored as `sync_error_code`/`sync_error_message` on the record
/// when it is marked `blocked`.
enum SyncResolution {
    /// A name collision — the losing record's references should be remapped to
    /// the winner returned by the server.
    struct Collision: Sendable {
        let winnerId: String
    }

    /// A last-write-wins conflict — the server version should be fetched and
    /// adopted.
    struct Conflict: Sendable {
        let serverUpdatedAt: Date
    }
}

/// The single synchronization coordinator.
///
/// One `SyncCoordinator` handles every sync trigger: account activation,
/// sign-in, cold restore, local mutation, connectivity restoration, undo
/// expiry, and the retry timer. Concurrent triggers join one in-flight sync
/// task (single-flight). `SyncQueue`, timer-specific retry loops, and
/// view-model networking are all removed — everything goes through here.
actor SyncCoordinator {

    private let localStore: LocalStore
    private let catalogRepo: CatalogRemoteSending
    private let entriesRepo: EntriesRemoteSending
    private let connectivity: Connectivity

    /// The currently in-flight sync task, if any. Concurrent callers await it
    /// instead of starting a second sync (single-flight).
    private var inFlightTask: Task<Void, Never>?

    init(
        localStore: LocalStore,
        catalogRepo: CatalogRemoteSending,
        entriesRepo: EntriesRemoteSending,
        connectivity: Connectivity
    ) {
        self.localStore = localStore
        self.catalogRepo = catalogRepo
        self.entriesRepo = entriesRepo
        self.connectivity = connectivity
    }

    // MARK: - Public

    /// Triggers a full sync cycle (outbound + pull). If a sync is already in
    /// flight, the caller joins it (single-flight).
    func sync() async {
        if let existing = inFlightTask {
            await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runSyncCycle()
        }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    /// Cancels any in-flight sync. Called during logout/account switch
    /// before closing the database.
    func cancelSync() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }

    // MARK: - Sync cycle

    /// Runs one full sync cycle: outbound push, then pull reconciliation.
    private func runSyncCycle() async {
        // 1. Outbound: push pending mutations in dependency order.
        await pushOutbound()

        // 2. Pull: fetch all server data and reconcile.
        if await connectivity.isConnected {
            await pullAndReconcile()
        }
    }

    // MARK: - Outbound

    /// Pushes pending mutations to the server in dependency order:
    /// categories → activities → entries → entry deletes → category deletes → activity deletes.
    private func pushOutbound() async {
        await pushPendingCategories()
        await pushPendingActivities()
        await pushPendingEntries()
        await pushPendingEntryDeletes()
        await pushPendingCategoryDeletes()
        await pushPendingActivityDeletes()
    }

    // MARK: - Outbound: categories

    private func pushPendingCategories() async {
        let pending: (createsUpdates: [Category], deletes: [Category])
        do {
            pending = try await localStore.pendingCategories()
        } catch {
            return
        }

        for category in pending.createsUpdates {
            await pushCategoryMutation(category)
        }
    }

    private func pushPendingCategoryDeletes() async {
        let pending: (createsUpdates: [Category], deletes: [Category])
        do {
            pending = try await localStore.pendingCategories()
        } catch {
            return
        }

        for category in pending.deletes {
            await pushCategoryDeletion(category)
        }
    }

    private func pushCategoryMutation(_ category: Category) async {
        if category.sync.remoteKnown {
            // PATCH (update)
            let request = CategoryUpdateRequest(
                updatedAt: category.updatedAt,
                name: category.name,
                icon: category.icon)
            do {
                let dto = try await catalogRepo.updateCategory(id: category.id, request: request)
                _ = try await localStore.adoptCanonicalCategory(
                    id: category.id, dto: dto, expectedRevision: category.sync.localRevision)
            } catch {
                await handleCategoryError(category, error)
            }
        } else {
            // POST (create)
            let request = CategoryCreateRequest(
                id: category.id, name: category.name, icon: category.icon)
            do {
                let dto = try await catalogRepo.createCategory(request)
                _ = try await localStore.adoptCanonicalCategory(
                    id: category.id, dto: dto, expectedRevision: category.sync.localRevision)
            } catch {
                await handleCategoryError(category, error)
            }
        }
    }

    private func pushCategoryDeletion(_ category: Category) async {
        do {
            try await catalogRepo.deleteCategory(id: category.id)
            try await localStore.completeCategoryDeletion(id: category.id)
        } catch APIError.server(let code, _, _) where code == "not_found" {
            // 404 = already deleted on server. Complete.
            try? await localStore.completeCategoryDeletion(id: category.id)
        } catch APIError.offline, APIError.transport {
            // Retain pending; will retry on next cycle.
        } catch {
            // Other errors: retain pending.
        }
    }

    private func handleCategoryError(_ category: Category, _ error: Error) async {
        switch error {
        case APIError.server(let code, let message, let details):
            switch code {
            case "category_exists":
                // Name collision — remap to the winner.
                if let winnerId = details["id"] {
                    await handleCategoryCollision(loserId: category.id, winnerId: winnerId)
                }
            case "conflict":
                // LWW conflict — fetch canonical and adopt.
                await handleCategoryConflict(id: category.id)
            case "validation_error":
                // Retain as blocked.
                try? await localStore.markCategoryBlocked(
                    id: category.id, code: code, message: message)
            case "not_found":
                // Activity was deleted remotely while we had a pending update.
                // Treat as remote hard delete.
                try? await localStore.hardDeleteCategory(id: category.id)
            default:
                // Other server errors: retain pending for retry.
                break
            }
        case APIError.offline, APIError.transport:
            // Retain pending; will retry on next cycle.
            break
        default:
            break
        }
    }

    private func handleCategoryCollision(loserId: String, winnerId: String) async {
        // Fetch the winner to ensure it exists locally, then remap.
        do {
            let winner = try await catalogRepo.getCategory(id: winnerId)
            let model = Category(
                id: winner.id, name: winner.name, icon: winner.icon,
                createdAt: winner.createdAt, updatedAt: winner.updatedAt,
                sync: .adoptedClean())
            // Upsert only if absent locally — a local record with pending
            // edits must keep its pending state (it is the winner's own
            // unsent mutation and will be pushed by the next cycle).
            try await localStore.adoptCanonicalCategoryIfAbsent(model)
            try await localStore.remapCategoryId(loserId: loserId, winnerId: winnerId)
        } catch {
            // Could not fetch winner — retain pending for retry.
        }
    }

    private func handleCategoryConflict(id: String) async {
        do {
            let dto = try await catalogRepo.getCategory(id: id)
            let model = Category(
                id: dto.id, name: dto.name, icon: dto.icon,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                sync: .adoptedClean())
            try await localStore.upsertCategory(model)
            try await localStore.markCategoryClean(id: id)
        } catch {
            // Could not fetch canonical — retain pending for retry.
        }
    }

    // MARK: - Outbound: activities

    private func pushPendingActivities() async {
        let pending: (createsUpdates: [Activity], deletes: [Activity])
        do {
            pending = try await localStore.pendingActivities()
        } catch {
            return
        }

        for activity in pending.createsUpdates {
            // Skip activities pending deletion (server DELETE cascades), and
            // defer activities whose category create is still pending — the
            // server would reject the tag with 422 validation_error.
            guard !activity.sync.isDeleted else { continue }
            let hasPendingCategory = (try? await localStore.hasPendingCategoryCreate(
                for: activity.categoryIds)) ?? false
            if hasPendingCategory {
                continue
            }
            await pushActivityMutation(activity)
        }
    }

    private func pushPendingActivityDeletes() async {
        let pending: (createsUpdates: [Activity], deletes: [Activity])
        do {
            pending = try await localStore.pendingActivities()
        } catch {
            return
        }

        for activity in pending.deletes {
            // Skip activities created and deleted before their first successful POST.
            if !activity.sync.remoteKnown {
                try? await localStore.hardDeleteActivity(id: activity.id)
                continue
            }
            await pushActivityDeletion(activity)
        }
    }

    private func pushActivityMutation(_ activity: Activity) async {
        if activity.sync.remoteKnown {
            // PATCH (update)
            let request = ActivityUpdateRequest(
                updatedAt: activity.updatedAt,
                name: activity.name,
                notes: activity.notes,
                categoryIds: activity.categoryIds)
            do {
                let dto = try await catalogRepo.updateActivity(id: activity.id, request: request)
                _ = try await localStore.adoptCanonicalActivity(
                    id: activity.id, dto: dto, expectedRevision: activity.sync.localRevision)
            } catch {
                await handleActivityError(activity, error)
            }
        } else {
            // POST (create)
            let request = ActivityCreateRequest(
                id: activity.id, name: activity.name,
                notes: activity.notes, categoryIds: activity.categoryIds)
            do {
                let dto = try await catalogRepo.createActivity(request)
                _ = try await localStore.adoptCanonicalActivity(
                    id: activity.id, dto: dto, expectedRevision: activity.sync.localRevision)
            } catch {
                await handleActivityError(activity, error)
            }
        }
    }

    private func pushActivityDeletion(_ activity: Activity) async {
        do {
            try await catalogRepo.deleteActivity(id: activity.id)
            try await localStore.completeActivityDeletion(id: activity.id)
        } catch APIError.server(let code, _, _) where code == "not_found" {
            try? await localStore.completeActivityDeletion(id: activity.id)
        } catch APIError.offline, APIError.transport {
            // Retain pending; will retry on next cycle.
        } catch {
            // Other errors: retain pending.
        }
    }

    private func handleActivityError(_ activity: Activity, _ error: Error) async {
        switch error {
        case APIError.server(let code, let message, let details):
            switch code {
            case "activity_exists":
                if let winnerId = details["id"] {
                    await handleActivityCollision(loserId: activity.id, winnerId: winnerId)
                }
            case "conflict":
                await handleActivityConflict(id: activity.id)
            case "validation_error":
                try? await localStore.markActivityBlocked(
                    id: activity.id, code: code, message: message)
            case "not_found":
                // Remote hard delete.
                try? await localStore.hardDeleteActivity(id: activity.id)
            default:
                break
            }
        case APIError.offline, APIError.transport:
            break
        default:
            break
        }
    }

    private func handleActivityCollision(loserId: String, winnerId: String) async {
        do {
            let winner = try await catalogRepo.getActivity(id: winnerId)
            let categoryIds = winner.categories.map(\.id)
            let model = Activity(
                id: winner.id, name: winner.name, notes: winner.notes,
                lastUsedAt: winner.lastUsedAt,
                createdAt: winner.createdAt, updatedAt: winner.updatedAt,
                categoryIds: categoryIds, sync: .adoptedClean())
            // Upsert only if absent locally — a local record with pending
            // edits must keep its pending state (it is the winner's own
            // unsent mutation and will be pushed by the next cycle).
            try await localStore.adoptCanonicalActivityIfAbsent(model)
            try await localStore.remapActivityId(loserId: loserId, winnerId: winnerId)
        } catch {
            // Could not fetch winner — retain pending for retry.
        }
    }

    private func handleActivityConflict(id: String) async {
        do {
            let dto = try await catalogRepo.getActivity(id: id)
            let categoryIds = dto.categories.map(\.id)
            let model = Activity(
                id: dto.id, name: dto.name, notes: dto.notes,
                lastUsedAt: dto.lastUsedAt,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                categoryIds: categoryIds, sync: .adoptedClean())
            try await localStore.upsertActivity(model)
            try await localStore.markActivityClean(id: id)
        } catch {
            // Could not fetch canonical — retain pending for retry.
        }
    }

    // MARK: - Outbound: entries

    private func pushPendingEntries() async {
        let pending: (createsUpdates: [Entry], deletes: [Entry])
        do {
            pending = try await localStore.pendingEntries()
        } catch {
            return
        }

        for entry in pending.createsUpdates {
            // Cancel pending entry creates/updates for activities pending deletion.
            if let activity = try? await localStore.activity(id: entry.activityId),
               activity.sync.isDeleted {
                // Activity is pending delete — skip this entry (server cascade will handle it).
                continue
            }
            // Defer entries whose activity create is still pending — the server
            // would reject them with 422 activity_not_found, which is terminal
            // (blocked). They sync once the activity create succeeds.
            if let activity = try? await localStore.activity(id: entry.activityId),
               !activity.sync.remoteKnown {
                continue
            }
            await pushEntryMutation(entry)
        }
    }

    private func pushPendingEntryDeletes() async {
        let pending: (createsUpdates: [Entry], deletes: [Entry])
        do {
            pending = try await localStore.pendingEntries()
        } catch {
            return
        }

        for entry in pending.deletes {
            await pushEntryDeletion(entry)
        }
    }

    private func pushEntryMutation(_ entry: Entry) async {
        if entry.sync.remoteKnown {
            // PATCH (update)
            let request = EntryUpdateRequest(
                updatedAt: entry.updatedAt,
                startedAt: entry.startedAt,
                endedAt: entry.endedAt)
            do {
                let dto = try await entriesRepo.updateEntry(id: entry.id, request: request)
                _ = try await localStore.adoptCanonicalEntry(
                    id: entry.id, dto: dto, expectedRevision: entry.sync.localRevision)
            } catch {
                await handleEntryError(entry, error)
            }
        } else {
            // POST (create)
            let request = EntryCreateRequest(
                id: entry.id, activityId: entry.activityId,
                startedAt: entry.startedAt, endedAt: entry.endedAt)
            do {
                let dto = try await entriesRepo.createEntry(request)
                _ = try await localStore.adoptCanonicalEntry(
                    id: entry.id, dto: dto, expectedRevision: entry.sync.localRevision)
            } catch {
                await handleEntryError(entry, error)
            }
        }
    }

    private func pushEntryDeletion(_ entry: Entry) async {
        do {
            try await entriesRepo.deleteEntry(id: entry.id)
            try await localStore.completeEntryDeletion(id: entry.id)
        } catch APIError.server(let code, _, _) where code == "not_found" {
            try? await localStore.completeEntryDeletion(id: entry.id)
        } catch APIError.offline, APIError.transport {
            // Retain pending; will retry on next cycle.
        } catch {
            // Other errors: retain pending.
        }
    }

    private func handleEntryError(_ entry: Entry, _ error: Error) async {
        switch error {
        case APIError.server(let code, let message, _):
            switch code {
            case "conflict":
                await handleEntryConflict(id: entry.id)
            case "validation_error", "activity_not_found":
                try? await localStore.markEntryBlocked(
                    id: entry.id, code: code, message: message)
            case "not_found":
                // Remote hard delete.
                try? await localStore.hardDeleteEntry(id: entry.id)
            default:
                break
            }
        case APIError.offline, APIError.transport:
            break
        default:
            break
        }
    }

    private func handleEntryConflict(id: String) async {
        do {
            let dto = try await entriesRepo.getEntry(id: id)
            let model = Entry(
                id: dto.id, activityId: dto.activityId,
                startedAt: dto.startedAt, endedAt: dto.endedAt,
                durationSeconds: dto.durationSeconds,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                sync: .adoptedClean())
            try await localStore.upsertEntry(model)
            try await localStore.markEntryClean(id: id)
        } catch {
            // Could not fetch canonical — retain pending for retry.
        }
    }

    // MARK: - Pull reconciliation

    /// Fetches all server data (categories, activities, all entry pages) and
    /// merges in one transaction via `LocalStore.reconcileWithSnapshot`.
    /// A failed or partial pull never modifies local state.
    private func pullAndReconcile() async {
        // Stage all responses before modifying local state.
        let categories: [CategoryDTO]
        let activities: [ActivityDTO]
        let entries: [EntryDTO]

        do {
            categories = try await catalogRepo.listCategories()
        } catch {
            return // Pull fails entirely — don't touch local state.
        }
        do {
            activities = try await catalogRepo.listActivities()
        } catch {
            return
        }
        do {
            entries = try await entriesRepo.listAllEntries()
        } catch {
            return // Partial entry pagination does not trigger deletion reconciliation.
        }

        // All three fetches succeeded — merge in one transaction.
        let snapshot = ServerSnapshot(
            categories: categories,
            activities: activities,
            entries: entries)
        try? await localStore.reconcileWithSnapshot(snapshot)
    }
}
