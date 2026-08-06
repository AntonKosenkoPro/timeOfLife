import Foundation
@testable import TimeOfLife

final class MockCatalogRepository: CatalogSending, @unchecked Sendable {

    struct Call: Equatable {
        let method: String
        let resource: String
        let id: String?

        init(_ method: String, _ resource: String, _ id: String? = nil) {
            self.method = method
            self.resource = resource
            self.id = id
        }
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _fetchedModifiedSince: [Date?] = []

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    var fetchedModifiedSince: [Date?] {
        lock.lock(); defer { lock.unlock() }
        return _fetchedModifiedSince
    }

    func clearLog() {
        lock.lock()
        _calls = []
        _fetchedModifiedSince = []
        lock.unlock()
    }

    var activitiesResult: [Activity] = []
    var categoriesResult: [TimeOfLife.Category] = []
    var entriesResult: [TimeEntry] = []

    var fetchActivityHandler: ((String) throws -> Activity)?
    var fetchCategoryHandler: ((String) throws -> TimeOfLife.Category)?
    var fetchEntryHandler: ((String) throws -> TimeEntry)?
    var createActivityHandler: ((Activity) throws -> Void)?
    var updateActivityHandler: ((Activity) throws -> Void)?
    var deleteActivityHandler: ((String) throws -> Void)?
    var createCategoryHandler: ((TimeOfLife.Category) throws -> Void)?
    var updateCategoryHandler: ((TimeOfLife.Category) throws -> Void)?
    var deleteCategoryHandler: ((String) throws -> Void)?
    var createEntryHandler: ((TimeEntry) throws -> Void)?
    var updateEntryHandler: ((TimeEntry) throws -> Void)?
    var deleteEntryHandler: ((String) throws -> Void)?

    private func record(_ method: String, _ resource: String, _ id: String? = nil) {
        lock.lock()
        _calls.append(Call(method, resource, id))
        lock.unlock()
    }

    private func recordPull(_ modifiedSince: Date?) {
        lock.lock()
        _fetchedModifiedSince.append(modifiedSince)
        lock.unlock()
    }

    func fetchActivities(modifiedSince: Date?) async throws -> [Activity] {
        record("fetchActivities", "activity")
        recordPull(modifiedSince)
        return activitiesResult
    }

    func fetchCategories() async throws -> [TimeOfLife.Category] {
        record("fetchCategories", "category")
        return categoriesResult
    }

    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry] {
        record("fetchEntries", "entry")
        recordPull(modifiedSince)
        return entriesResult
    }

    func fetchActivity(id: String) async throws -> Activity {
        record("fetchActivity", "activity", id)
        if let fetchActivityHandler { return try fetchActivityHandler(id) }
        if let match = activitiesResult.first(where: { $0.id == id }) { return match }
        throw APIError.unexpected
    }

    func fetchCategory(id: String) async throws -> TimeOfLife.Category {
        record("fetchCategory", "category", id)
        if let fetchCategoryHandler { return try fetchCategoryHandler(id) }
        if let match = categoriesResult.first(where: { $0.id == id }) { return match }
        throw APIError.unexpected
    }

    func fetchEntry(id: String) async throws -> TimeEntry {
        record("fetchEntry", "entry", id)
        if let fetchEntryHandler { return try fetchEntryHandler(id) }
        if let match = entriesResult.first(where: { $0.id == id }) { return match }
        throw APIError.unexpected
    }

    func createActivity(_ activity: Activity) async throws {
        record("createActivity", "activity", activity.id)
        if let createActivityHandler { try createActivityHandler(activity) }
    }

    func updateActivity(_ activity: Activity) async throws {
        record("updateActivity", "activity", activity.id)
        if let updateActivityHandler { try updateActivityHandler(activity) }
    }

    func deleteActivity(id: String) async throws {
        record("deleteActivity", "activity", id)
        if let deleteActivityHandler { try deleteActivityHandler(id) }
    }

    func createCategory(_ category: TimeOfLife.Category) async throws {
        record("createCategory", "category", category.id)
        if let createCategoryHandler { try createCategoryHandler(category) }
    }

    func updateCategory(_ category: TimeOfLife.Category) async throws {
        record("updateCategory", "category", category.id)
        if let updateCategoryHandler { try updateCategoryHandler(category) }
    }

    func deleteCategory(id: String) async throws {
        record("deleteCategory", "category", id)
        if let deleteCategoryHandler { try deleteCategoryHandler(id) }
    }

    func createEntry(_ entry: TimeEntry) async throws {
        record("createEntry", "entry", entry.id)
        if let createEntryHandler { try createEntryHandler(entry) }
    }

    func updateEntry(_ entry: TimeEntry) async throws {
        record("updateEntry", "entry", entry.id)
        if let updateEntryHandler { try updateEntryHandler(entry) }
    }

    func deleteEntry(id: String) async throws {
        record("deleteEntry", "entry", id)
        if let deleteEntryHandler { try deleteEntryHandler(id) }
    }
}
