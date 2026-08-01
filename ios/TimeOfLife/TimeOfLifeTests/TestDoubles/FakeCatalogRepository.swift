import Foundation
@testable import TimeOfLife

/// Records calls and returns canned results / errors. Drives `CatalogService`
/// and `SyncQueue` tests without a network. Mirrors `FakeAuthRepository`.
///
/// Thread-safe via `NSLock`.
final class FakeCatalogRepository: CatalogRepository, @unchecked Sendable {

    /// Recorded call types for verification.
    enum Call: Equatable {
        case listActivities(query: String?)
        case getActivity(UUID)
        case createActivity(Activity)
        case updateActivity(Activity)
        case deleteActivity(UUID)
        case listCategories
        case getCategory(UUID)
        case createCategory(Category)
        case updateCategory(Category)
        case deleteCategory(UUID)
    }

    // MARK: - State

    private let lock = NSLock()
    private var _calls: [Call] = []

    /// All recorded calls, in order.
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    // MARK: - Canned results

    var activitiesResult: [Activity] = []
    var activityResult: Activity?
    var categoriesResult: [Category] = []
    var categoryResult: Category?

    // MARK: - Per-method errors

    var listActivitiesError: Error?
    var getActivityError: Error?
    var createActivityError: Error?
    var updateActivityError: Error?
    var deleteActivityError: Error?
    var listCategoriesError: Error?
    var getCategoryError: Error?
    var createCategoryError: Error?
    var updateCategoryError: Error?
    var deleteCategoryError: Error?

    // MARK: - Recording

    private func record(_ call: Call) {
        lock.lock(); _calls.append(call); lock.unlock()
    }

    // MARK: - CatalogRepository

    func listActivities(query: String?) async throws -> [Activity] {
        record(.listActivities(query: query))
        if let e = listActivitiesError { throw e }
        return activitiesResult
    }

    func getActivity(_ id: UUID) async throws -> Activity {
        record(.getActivity(id))
        if let e = getActivityError { throw e }
        if let activity = activityResult { return activity }
        // Fall back to a deterministic activity with the requested id.
        return TestCatalogFactory.activity(id: id)
    }

    func createActivity(_ activity: Activity) async throws -> Activity {
        record(.createActivity(activity))
        if let e = createActivityError { throw e }
        return activity
    }

    func updateActivity(_ activity: Activity) async throws -> Activity {
        record(.updateActivity(activity))
        if let e = updateActivityError { throw e }
        return activity
    }

    func deleteActivity(_ id: UUID) async throws {
        record(.deleteActivity(id))
        if let e = deleteActivityError { throw e }
    }

    func listCategories() async throws -> [Category] {
        record(.listCategories)
        if let e = listCategoriesError { throw e }
        return categoriesResult
    }

    func getCategory(_ id: UUID) async throws -> Category {
        record(.getCategory(id))
        if let e = getCategoryError { throw e }
        if let category = categoryResult { return category }
        return TestCatalogFactory.category(id: id)
    }

    func createCategory(_ category: Category) async throws -> Category {
        record(.createCategory(category))
        if let e = createCategoryError { throw e }
        return category
    }

    func updateCategory(_ category: Category) async throws -> Category {
        record(.updateCategory(category))
        if let e = updateCategoryError { throw e }
        return category
    }

    func deleteCategory(_ id: UUID) async throws {
        record(.deleteCategory(id))
        if let e = deleteCategoryError { throw e }
    }
}
