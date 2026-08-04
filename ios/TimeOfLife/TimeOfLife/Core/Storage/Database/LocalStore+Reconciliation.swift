import GRDB
import Foundation

/// Full-snapshot reconciliation and canonical-response adoption.
extension LocalStore {

    // MARK: - Full-snapshot reconciliation

    /// Merges a complete server snapshot into the local store in one
    /// transaction.
    ///
    /// Rules (per AC5):
    /// - Clean local records adopt server values.
    /// - Dirty or blocked records remain locally authoritative.
    /// - Clean remote-known records absent from a complete response are
    ///   deleted locally.
    /// - Removing a remotely deleted activity also removes its clean local
    ///   entries.
    /// - Pending creates absent from server remain pending.
    /// - Pending deletes absent from server are completed.
    /// - A failed/partial pull never reaches this method (caller stages first).
    func reconcileWithSnapshot(_ snapshot: ServerSnapshot) throws {
        try dbQueue.write { db in
            try reconcileCategories(db, snapshot: snapshot)
            try reconcileActivities(db, snapshot: snapshot)
            try reconcileEntries(db, snapshot: snapshot)
        }
    }

    // MARK: - Revision guard

    /// Adopts a canonical server response for a category only if the local
    /// revision is unchanged since the request was sent.
    func adoptCanonicalCategory(
        id: String,
        dto: CategoryDTO,
        expectedRevision: Int
    ) throws -> AdoptionResult<Category> {
        try dbQueue.write { db in
            guard let local = try CategoryRecord.filter(key: id).fetchOne(db) else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            guard local.localRevision == expectedRevision else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            let model = Category(
                id: dto.id, name: dto.name, icon: dto.icon,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                sync: .adoptedClean()
            )
            var catRec = CategoryRecord.from(model); try catRec.save(db)
            return AdoptionResult(model: model, didOverwrite: true)
        }
    }

    /// Adopts a canonical server response for an activity only if the local
    /// revision is unchanged.
    func adoptCanonicalActivity(
        id: String,
        dto: ActivityDTO,
        expectedRevision: Int
    ) throws -> AdoptionResult<Activity> {
        try dbQueue.write { db in
            guard let local = try ActivityRecord.filter(key: id).fetchOne(db) else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            guard local.localRevision == expectedRevision else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            let categoryIds = dto.categories.map(\.id)
            let model = Activity(
                id: dto.id, name: dto.name, notes: dto.notes,
                lastUsedAt: dto.lastUsedAt,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                categoryIds: categoryIds, sync: .adoptedClean()
            )
            var actRec = ActivityRecord.from(model); try actRec.save(db)
            try replaceActivityCategories(db, activityId: dto.id, categoryIds: categoryIds)
            return AdoptionResult(model: model, didOverwrite: true)
        }
    }

    /// Adopts a canonical server response for an entry only if the local
    /// revision is unchanged.
    func adoptCanonicalEntry(
        id: String,
        dto: EntryDTO,
        expectedRevision: Int
    ) throws -> AdoptionResult<Entry> {
        try dbQueue.write { db in
            guard let local = try EntryRecord.filter(key: id).fetchOne(db) else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            guard local.localRevision == expectedRevision else {
                return AdoptionResult(model: nil, didOverwrite: false)
            }
            let model = Entry(
                id: dto.id, activityId: dto.activityId,
                startedAt: dto.startedAt, endedAt: dto.endedAt,
                durationSeconds: dto.durationSeconds,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                sync: .adoptedClean()
            )
            var entRec = EntryRecord.from(model); try entRec.save(db)
            return AdoptionResult(model: model, didOverwrite: true)
        }
    }

    // MARK: - Reconciliation helpers (private)

    /// Reconciles categories: adopt server values, remove absent clean
    /// records, complete pending deletes.
    private func reconcileCategories(_ db: Database, snapshot: ServerSnapshot) throws {
        let serverIds = Set(snapshot.categories.map(\.id))

        for dto in snapshot.categories {
            try adoptServerCategory(db, dto: dto)
        }

        // Remove clean local categories absent from server (skip undo-hidden).
        let cleanCats = try CategoryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.clean.rawValue &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for cat in cleanCats where !serverIds.contains(cat.id) {
            _ = try CategoryRecord.filter(key: cat.id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("category_id") == cat.id).deleteAll(db)
        }

        // Complete pending deletes absent from server.
        let pendingDeleteCats = try CategoryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                Column(SyncMetadataColumns.isDeleted) == 1)
            .fetchAll(db)
        for cat in pendingDeleteCats where !serverIds.contains(cat.id) {
            _ = try CategoryRecord.filter(key: cat.id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("category_id") == cat.id).deleteAll(db)
        }

        // Complete blocked remote-known records absent from the snapshot —
        // the server deleted them, so the local copy (stuck visible with a
        // stale error) must go. Blocked records never created on the server
        // (`remote_known == 0`) stay: they are local-only failed creates and
        // can never appear in a snapshot.
        let blockedRemoteCats = try CategoryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue &&
                Column(SyncMetadataColumns.remoteKnown) == 1 &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for cat in blockedRemoteCats where !serverIds.contains(cat.id) {
            _ = try CategoryRecord.filter(key: cat.id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("category_id") == cat.id).deleteAll(db)
        }
    }

    /// Reconciles activities: adopt server values, remove absent clean
    /// records (cascading clean entries), complete pending deletes.
    private func reconcileActivities(_ db: Database, snapshot: ServerSnapshot) throws {
        let serverIds = Set(snapshot.activities.map(\.id))

        for dto in snapshot.activities {
            try adoptServerActivity(db, dto: dto)
        }

        // Remove clean local activities absent from server, cascading clean
        // entries (skip undo-hidden).
        let cleanActs = try ActivityRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.clean.rawValue &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for act in cleanActs where !serverIds.contains(act.id) {
            try deleteCleanEntriesForActivity(db, activityId: act.id)
            _ = try ActivityCategoryRecord
                .filter(Column("activity_id") == act.id).deleteAll(db)
            _ = try ActivityRecord.filter(key: act.id).deleteAll(db)
        }

        // Complete pending deletes absent from server.
        let pendingDeleteActs = try ActivityRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                Column(SyncMetadataColumns.isDeleted) == 1)
            .fetchAll(db)
        for act in pendingDeleteActs where !serverIds.contains(act.id) {
            _ = try EntryRecord
                .filter(Column("activity_id") == act.id).deleteAll(db)
            _ = try ActivityCategoryRecord
                .filter(Column("activity_id") == act.id).deleteAll(db)
            _ = try ActivityRecord.filter(key: act.id).deleteAll(db)
        }

        // Complete blocked remote-known activities absent from the snapshot
        // (server deleted them). Local-only failed creates stay.
        let blockedRemoteActs = try ActivityRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue &&
                Column(SyncMetadataColumns.remoteKnown) == 1 &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for act in blockedRemoteActs where !serverIds.contains(act.id) {
            try deleteCleanEntriesForActivity(db, activityId: act.id)
            _ = try ActivityCategoryRecord
                .filter(Column("activity_id") == act.id).deleteAll(db)
            _ = try ActivityRecord.filter(key: act.id).deleteAll(db)
        }
    }

    /// Reconciles entries: adopt server values, remove absent clean records,
    /// complete pending deletes.
    private func reconcileEntries(_ db: Database, snapshot: ServerSnapshot) throws {
        let serverIds = Set(snapshot.entries.map(\.id))

        for dto in snapshot.entries {
            try adoptServerEntry(db, dto: dto)
        }

        // Remove clean local entries absent from server (skip undo-hidden).
        let cleanEntries = try EntryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.clean.rawValue &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for ent in cleanEntries where !serverIds.contains(ent.id) {
            _ = try EntryRecord.filter(key: ent.id).deleteAll(db)
        }

        // Complete pending deletes absent from server.
        let pendingDeleteEntries = try EntryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.pending.rawValue &&
                Column(SyncMetadataColumns.isDeleted) == 1)
            .fetchAll(db)
        for ent in pendingDeleteEntries where !serverIds.contains(ent.id) {
            _ = try EntryRecord.filter(key: ent.id).deleteAll(db)
        }

        // Complete blocked remote-known entries absent from the snapshot
        // (server deleted them). Local-only failed creates stay.
        let blockedRemoteEntries = try EntryRecord
            .filter(
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.blocked.rawValue &&
                Column(SyncMetadataColumns.remoteKnown) == 1 &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for ent in blockedRemoteEntries where !serverIds.contains(ent.id) {
            _ = try EntryRecord.filter(key: ent.id).deleteAll(db)
        }
    }

    /// Removes all clean entries for the given activity (used during
    /// activity cascade deletion in reconciliation). Skips undo-hidden.
    private func deleteCleanEntriesForActivity(_ db: Database, activityId: String) throws {
        let cleanEntries = try EntryRecord
            .filter(
                Column("activity_id") == activityId &&
                Column(SyncMetadataColumns.syncStatus) == SyncStatus.clean.rawValue &&
                Column(SyncMetadataColumns.isUndoHidden) == 0)
            .fetchAll(db)
        for ent in cleanEntries {
            _ = try EntryRecord.filter(key: ent.id).deleteAll(db)
        }
    }

    // MARK: - Adoption helpers (private)

    /// Adopts a server category: if local is clean (or absent), overwrite with
    /// server values and mark clean. If dirty/blocked/undo-hidden, preserve.
    private func adoptServerCategory(_ db: Database, dto: CategoryDTO) throws {
        if let local = try CategoryRecord.filter(key: dto.id).fetchOne(db) {
            guard local.syncStatus == SyncStatus.clean.rawValue,
                  local.isUndoHidden == 0 else { return }
        }
        let model = Category(
            id: dto.id, name: dto.name, icon: dto.icon,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            sync: .adoptedClean()
        )
        var catRec = CategoryRecord.from(model); try catRec.save(db)
    }

    /// Adopts a server activity: if local is clean (or absent), overwrite with
    /// server values + category tags and mark clean. If dirty/blocked/undo-hidden, preserve.
    private func adoptServerActivity(_ db: Database, dto: ActivityDTO) throws {
        if let local = try ActivityRecord.filter(key: dto.id).fetchOne(db) {
            guard local.syncStatus == SyncStatus.clean.rawValue,
                  local.isUndoHidden == 0 else { return }
        }
        let categoryIds = dto.categories.map(\.id)
        let model = Activity(
            id: dto.id, name: dto.name, notes: dto.notes,
            lastUsedAt: dto.lastUsedAt,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            categoryIds: categoryIds, sync: .adoptedClean()
        )
        var actRec = ActivityRecord.from(model); try actRec.save(db)
        try replaceActivityCategories(db, activityId: dto.id, categoryIds: categoryIds)
    }

    /// Adopts a server entry: if local is clean (or absent), overwrite with
    /// server values and mark clean. If dirty/blocked/undo-hidden, preserve.
    private func adoptServerEntry(_ db: Database, dto: EntryDTO) throws {
        if let local = try EntryRecord.filter(key: dto.id).fetchOne(db) {
            guard local.syncStatus == SyncStatus.clean.rawValue,
                  local.isUndoHidden == 0 else { return }
        }
        let model = Entry(
            id: dto.id, activityId: dto.activityId,
            startedAt: dto.startedAt, endedAt: dto.endedAt,
            durationSeconds: dto.durationSeconds,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            sync: .adoptedClean()
        )
        var entRec = EntryRecord.from(model); try entRec.save(db)
    }
}
