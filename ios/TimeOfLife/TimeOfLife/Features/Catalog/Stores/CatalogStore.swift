import Foundation
import os

/// Local persistence contract for the catalog. The store is the offline-first
/// source of truth for on-device suggestions (F5) and manage lists; it has no
/// network references — sync is orchestrated by `CatalogService` / `SyncQueue`.
protocol CatalogStoring: Sendable {
    func loadActivities() async -> [Activity]
    func loadCategories() async -> [Category]
    /// Activities ranked by `last_used_at` DESC (recency; D16/D19).
    func activitiesSortedByLastUsedAt() async -> [Activity]
    func activity(_ id: UUID) async -> Activity?
    /// Case-insensitive, whitespace-trimmed name lookup for reuse (F4).
    func activity(named: String) async -> Activity?
    func category(_ id: UUID) async -> Category?

    /// Upserts (create or replace-by-id) an activity optimistically.
    func upsertActivity(_ activity: Activity) async
    func upsertCategory(_ category: Category) async
    /// Removes an activity by id.
    func removeActivity(_ id: UUID) async
    func removeCategory(_ id: UUID) async
    /// Rewrites activities' `categoryIds`, replacing `oldId` with `newId`.
    /// Used when a `category_exists` collision re-maps references (F4).
    func replaceCategoryReferences(from oldId: UUID, to newId: UUID) async
    /// Rewrites references to an activity id (entries are owned by 1-3; in this
    /// story the store has no in-store activity references, so this is a no-op
    /// seam for the entry side). Called on `activity_exists` re-map.
    func replaceActivityReferences(from oldId: UUID, to newId: UUID) async
}

/// File-based local catalog store. Mirrors `LocalTimerStore`: JSON in
/// Application Support/TimeOfLife/, separate files per resource, actor-isolated.
/// Survives relaunch. Dates use deferred-to-date `Double` (local concern only).
actor CatalogStore: CatalogStoring {
    private let activitiesURL: URL
    private let categoriesURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TimeOfLife", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife", isDirectory: true)
        self.activitiesURL = base.appendingPathComponent("catalog_activities.json")
        self.categoriesURL = base.appendingPathComponent("catalog_categories.json")
    }

    // MARK: - Reads

    func loadActivities() async -> [Activity] {
        (try? loadActivitiesLocked()) ?? []
    }

    func loadCategories() async -> [Category] {
        (try? loadCategoriesLocked()) ?? []
    }

    func activitiesSortedByLastUsedAt() async -> [Activity] {
        let activities = (try? loadActivitiesLocked()) ?? []
        return activities.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.name < rhs.name
            }
        }
    }

    func activity(_ id: UUID) async -> Activity? {
        ((try? loadActivitiesLocked()) ?? []).first { $0.id == id }
    }

    func activity(named name: String) async -> Activity? {
        let key = CatalogValidator.normalizeName(name)
        guard !key.isEmpty else { return nil }
        return ((try? loadActivitiesLocked()) ?? []).first {
            CatalogValidator.normalizeName($0.name) == key
        }
    }

    func category(_ id: UUID) async -> Category? {
        ((try? loadCategoriesLocked()) ?? []).first { $0.id == id }
    }

    // MARK: - Writes

    func upsertActivity(_ activity: Activity) async {
        guard (try? ensureDirectory(at: activitiesURL)) != nil else { return }
        guard var activities = try? loadActivitiesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("upsertActivity: failed to load activities")
            return
        }
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        if (try? saveActivitiesLocked(activities)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("upsertActivity: failed to save activities")
        }
    }

    func upsertCategory(_ category: Category) async {
        guard (try? ensureDirectory(at: categoriesURL)) != nil else { return }
        guard var categories = try? loadCategoriesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("upsertCategory: failed to load categories")
            return
        }
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        if (try? saveCategoriesLocked(categories)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("upsertCategory: failed to save categories")
        }
    }

    func removeActivity(_ id: UUID) async {
        guard var activities = try? loadActivitiesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeActivity: failed to load activities")
            return
        }
        activities.removeAll { $0.id == id }
        if (try? saveActivitiesLocked(activities)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeActivity: failed to save activities")
        }
    }

    func removeCategory(_ id: UUID) async {
        // Cascade the tag removal on activities FIRST so that if the activities
        // save fails, the categories file is untouched (rollback-safe ordering).
        guard var activities = try? loadActivitiesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeCategory: failed to load activities")
            return
        }
        var changed = false
        for index in activities.indices where activities[index].categoryIds.contains(id) {
            activities[index].categoryIds.removeAll { $0 == id }
            changed = true
        }
        if changed, (try? saveActivitiesLocked(activities)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeCategory: failed to save activities")
        }

        guard var categories = try? loadCategoriesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeCategory: failed to load categories")
            return
        }
        categories.removeAll { $0.id == id }
        if (try? saveCategoriesLocked(categories)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("removeCategory: failed to save categories")
        }
    }

    func replaceCategoryReferences(from oldId: UUID, to newId: UUID) async {
        guard oldId != newId else { return }
        guard var activities = try? loadActivitiesLocked() else {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("replaceCategoryReferences: failed to load activities")
            return
        }
        var changed = false
        for index in activities.indices where activities[index].categoryIds.contains(oldId) {
            activities[index].categoryIds.removeAll { $0 == oldId }
            if !activities[index].categoryIds.contains(newId) {
                activities[index].categoryIds.append(newId)
            }
            changed = true
        }
        if changed, (try? saveActivitiesLocked(activities)) == nil {
            Logger(subsystem: "com.timeoflife", category: "catalog").error("replaceCategoryReferences: failed to save activities")
        }
    }

    func replaceActivityReferences(from oldId: UUID, to newId: UUID) async {
        // No in-store references to an activity id (entries are owned by 1-3).
        // Provided as the re-map seam for the `activity_exists` path.
        _ = oldId; _ = newId
    }

    // MARK: - File helpers

    private func ensureDirectory(at url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: nil
        )
        return directory
    }

    private func loadActivitiesLocked() throws -> [Activity] {
        guard FileManager.default.fileExists(atPath: activitiesURL.path) else { return [] }
        let data = try Data(contentsOf: activitiesURL)
        do {
            return try JSONDecoder().decode([Activity].self, from: data)
        } catch {
            let logger = Logger(subsystem: "com.timeoflife", category: "catalog")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let filename = "\(activitiesURL.deletingPathExtension().lastPathComponent).corrupted.\(timestamp).json"
            let quarantinedURL = activitiesURL.deletingLastPathComponent()
                .appendingPathComponent(filename)
            logger.error("loadActivitiesLocked: corrupt catalog file detected: \(error.localizedDescription, privacy: .public)")
            try FileManager.default.moveItem(at: activitiesURL, to: quarantinedURL)
            logger.error("loadActivitiesLocked: quarantined corrupt catalog file at \(quarantinedURL.path, privacy: .public)")
            return []
        }
    }

    private func loadCategoriesLocked() throws -> [Category] {
        guard FileManager.default.fileExists(atPath: categoriesURL.path) else { return [] }
        let data = try Data(contentsOf: categoriesURL)
        do {
            return try JSONDecoder().decode([Category].self, from: data)
        } catch {
            let logger = Logger(subsystem: "com.timeoflife", category: "catalog")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let filename = "\(categoriesURL.deletingPathExtension().lastPathComponent).corrupted.\(timestamp).json"
            let quarantinedURL = categoriesURL.deletingLastPathComponent()
                .appendingPathComponent(filename)
            logger.error("loadCategoriesLocked: corrupt catalog file detected: \(error.localizedDescription, privacy: .public)")
            try FileManager.default.moveItem(at: categoriesURL, to: quarantinedURL)
            logger.error("loadCategoriesLocked: quarantined corrupt catalog file at \(quarantinedURL.path, privacy: .public)")
            return []
        }
    }

    private func saveActivitiesLocked(_ activities: [Activity]) throws {
        let data = try JSONEncoder().encode(activities)
        try data.write(to: activitiesURL, options: .atomic)
    }

    private func saveCategoriesLocked(_ categories: [Category]) throws {
        let data = try JSONEncoder().encode(categories)
        try data.write(to: categoriesURL, options: .atomic)
    }
}
