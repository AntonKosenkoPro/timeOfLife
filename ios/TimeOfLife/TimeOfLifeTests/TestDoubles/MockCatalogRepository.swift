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
    private var _fetchedDeletionsSince: [Date?] = []

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    var fetchedModifiedSince: [Date?] {
        lock.lock(); defer { lock.unlock() }
        return _fetchedModifiedSince
    }

    var fetchedDeletionsSince: [Date?] {
        lock.lock(); defer { lock.unlock() }
        return _fetchedDeletionsSince
    }

    func clearLog() {
        lock.lock()
        _calls = []
        _fetchedModifiedSince = []
        _fetchedDeletionsSince = []
        lock.unlock()
    }

    var categoriesResult: [Category] = []
    var entriesResult: [TimeEntry] = []
    var deletionsResult: [Deletion] = []

    // Handlers are async so tests can inject slow or failing relay
    // behavior (e.g. a delayed push that keeps a cycle in flight while a
    // second trigger arrives). Synchronous closures convert implicitly,
    // so existing assignments keep compiling.
    var fetchCategoryHandler: ((String) async throws -> Category)?
    var fetchEntryHandler: ((String) async throws -> TimeEntry)?
    var fetchDeletionsHandler: ((Date?) async throws -> [Deletion])?
    var createCategoryHandler: ((Category) async throws -> Void)?
    var updateCategoryHandler: ((Category) async throws -> Void)?
    var deleteCategoryHandler: ((String) async throws -> Void)?
    var createEntryHandler: ((TimeEntry) async throws -> Void)?
    var updateEntryHandler: ((TimeEntry) async throws -> Void)?
    var deleteEntryHandler: ((String) async throws -> Void)?

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

    private func recordDeletionsPull(_ since: Date?) {
        lock.lock()
        _fetchedDeletionsSince.append(since)
        lock.unlock()
    }

    func fetchCategories() async throws -> [Category] {
        record("fetchCategories", "category")
        return categoriesResult
    }

    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry] {
        record("fetchEntries", "entry")
        recordPull(modifiedSince)
        return entriesResult
    }

    func fetchDeletions(since: Date?) async throws -> [Deletion] {
        record("fetchDeletions", "deletion")
        recordDeletionsPull(since)
        if let fetchDeletionsHandler { return try await fetchDeletionsHandler(since) }
        return deletionsResult
    }

    func fetchCategory(id: String) async throws -> Category {
        record("fetchCategory", "category", id)
        if let fetchCategoryHandler { return try await fetchCategoryHandler(id) }
        if let match = categoriesResult.first(where: { $0.id == id }) { return match }
        throw APIError.unexpected
    }

    func fetchEntry(id: String) async throws -> TimeEntry {
        record("fetchEntry", "entry", id)
        if let fetchEntryHandler { return try await fetchEntryHandler(id) }
        if let match = entriesResult.first(where: { $0.id == id }) { return match }
        throw APIError.unexpected
    }

    func createCategory(_ category: Category) async throws {
        record("createCategory", "category", category.id)
        if let createCategoryHandler { try await createCategoryHandler(category) }
    }

    func updateCategory(_ category: Category) async throws {
        record("updateCategory", "category", category.id)
        if let updateCategoryHandler { try await updateCategoryHandler(category) }
    }

    func deleteCategory(id: String) async throws {
        record("deleteCategory", "category", id)
        if let deleteCategoryHandler { try await deleteCategoryHandler(id) }
    }

    func createEntry(_ entry: TimeEntry) async throws {
        record("createEntry", "entry", entry.id)
        if let createEntryHandler { try await createEntryHandler(entry) }
    }

    func updateEntry(_ entry: TimeEntry) async throws {
        record("updateEntry", "entry", entry.id)
        if let updateEntryHandler { try await updateEntryHandler(entry) }
    }

    func deleteEntry(id: String) async throws {
        record("deleteEntry", "entry", id)
        if let deleteEntryHandler { try await deleteEntryHandler(id) }
    }
}
