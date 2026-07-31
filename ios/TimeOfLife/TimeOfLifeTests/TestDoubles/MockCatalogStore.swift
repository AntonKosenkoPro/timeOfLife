import Foundation
@testable import TimeOfLife

/// In-memory `CatalogStoring` double for `CatalogService` / `SyncQueue` tests.
/// Records mutation calls and mirrors the real store's semantics (case
/// -insensitive name lookup, recency sort, category-tag cascade) so tests can
/// assert against in-memory state without file I/O.
actor MockCatalogStore: CatalogStoring {
    enum Call: Equatable {
        case upsertActivity(Activity)
        case upsertCategory(Category)
        case removeActivity(UUID)
        case removeCategory(UUID)
        case replaceCategoryReferences(from: UUID, to: UUID)
        case replaceActivityReferences(from: UUID, to: UUID)
    }

    private var activities: [Activity] = []
    private var categories: [Category] = []
    private(set) var calls: [Call] = []

    // MARK: - Reads

    func loadActivities() async -> [Activity] { activities }
    func loadCategories() async -> [Category] { categories }

    func activitiesSortedByLastUsedAt() async -> [Activity] {
        activities.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.name < rhs.name
            }
        }
    }

    func activity(_ id: UUID) async -> Activity? {
        activities.first { $0.id == id }
    }

    func activity(named name: String) async -> Activity? {
        let key = CatalogValidator.normalizeName(name)
        guard !key.isEmpty else { return nil }
        return activities.first { CatalogValidator.normalizeName($0.name) == key }
    }

    func category(_ id: UUID) async -> Category? {
        categories.first { $0.id == id }
    }

    func category(named name: String) async -> Category? {
        let key = CatalogValidator.normalizeName(name)
        guard !key.isEmpty else { return nil }
        return categories.first { CatalogValidator.normalizeName($0.name) == key }
    }

    // MARK: - Writes

    func upsertActivity(_ activity: Activity) async {
        calls.append(.upsertActivity(activity))
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
    }

    func upsertCategory(_ category: Category) async {
        calls.append(.upsertCategory(category))
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
    }

    func removeActivity(_ id: UUID) async {
        calls.append(.removeActivity(id))
        activities.removeAll { $0.id == id }
    }

    func removeCategory(_ id: UUID) async {
        calls.append(.removeCategory(id))
        categories.removeAll { $0.id == id }
        for index in activities.indices where activities[index].categoryIds.contains(id) {
            activities[index].categoryIds.removeAll { $0 == id }
        }
    }

    func replaceCategoryReferences(from oldId: UUID, to newId: UUID) async {
        calls.append(.replaceCategoryReferences(from: oldId, to: newId))
        guard oldId != newId else { return }
        for index in activities.indices where activities[index].categoryIds.contains(oldId) {
            activities[index].categoryIds.removeAll { $0 == oldId }
            if !activities[index].categoryIds.contains(newId) {
                activities[index].categoryIds.append(newId)
            }
        }
    }

    func replaceActivityReferences(from oldId: UUID, to newId: UUID) async {
        calls.append(.replaceActivityReferences(from: oldId, to: newId))
    }
}
