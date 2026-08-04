import Foundation
@testable import TimeOfLife

/// A fake `RemoteCatalogRepository` for testing the `SyncCoordinator`.
/// Records all calls and returns canned results/errors per endpoint.
/// `@MainActor` for safe synchronous access to recorded state in tests.
@MainActor
final class FakeCatalogRepository: CatalogRemoteSending {

    // Recorded calls
    private(set) var listCategoriesCalls = 0
    private(set) var createCategoryCalls: [CategoryCreateRequest] = []
    private(set) var updateCategoryCalls: [(id: String, request: CategoryUpdateRequest)] = []
    private(set) var deleteCategoryCalls: [String] = []
    private(set) var getCategoryCalls: [String] = []
    private(set) var listActivitiesCalls = 0
    private(set) var createActivityCalls: [ActivityCreateRequest] = []
    private(set) var updateActivityCalls: [(id: String, request: ActivityUpdateRequest)] = []
    private(set) var deleteActivityCalls: [String] = []
    private(set) var getActivityCalls: [String] = []

    // Canned results
    var listCategoriesResult: [CategoryDTO] = []
    var listCategoriesError: Error?

    var createCategoryResult: ((CategoryCreateRequest) -> CategoryDTO?)?
    var createCategoryError: ((CategoryCreateRequest) -> Error?)?

    var updateCategoryResult: ((String, CategoryUpdateRequest) -> CategoryDTO?)?
    var updateCategoryError: ((String, CategoryUpdateRequest) -> Error?)?

    var deleteCategoryError: ((String) -> Error?)?

    var getCategoryResult: ((String) -> CategoryDTO?)?
    var getCategoryError: ((String) -> Error?)?

    var listActivitiesResult: [ActivityDTO] = []
    var listActivitiesError: Error?

    var createActivityResult: ((ActivityCreateRequest) -> ActivityDTO?)?
    var createActivityError: ((ActivityCreateRequest) -> Error?)?

    var updateActivityResult: ((String, ActivityUpdateRequest) -> ActivityDTO?)?
    var updateActivityError: ((String, ActivityUpdateRequest) -> Error?)?

    var deleteActivityError: ((String) -> Error?)?

    var getActivityResult: ((String) -> ActivityDTO?)?
    var getActivityError: ((String) -> Error?)?

    func reset() {
        listCategoriesCalls = 0
        createCategoryCalls = []
        updateCategoryCalls = []
        deleteCategoryCalls = []
        getCategoryCalls = []
        listActivitiesCalls = 0
        createActivityCalls = []
        updateActivityCalls = []
        deleteActivityCalls = []
        getActivityCalls = []
        listCategoriesResult = []
        listCategoriesError = nil
        createCategoryResult = nil
        createCategoryError = nil
        updateCategoryResult = nil
        updateCategoryError = nil
        deleteCategoryError = nil
        getCategoryResult = nil
        getCategoryError = nil
        listActivitiesResult = []
        listActivitiesError = nil
        createActivityResult = nil
        createActivityError = nil
        updateActivityResult = nil
        updateActivityError = nil
        deleteActivityError = nil
        getActivityResult = nil
        getActivityError = nil
    }
}

extension FakeCatalogRepository {
    func listCategories() async throws -> [CategoryDTO] {
        listCategoriesCalls += 1
        if let listCategoriesError { throw listCategoriesError }
        return listCategoriesResult
    }

    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO {
        createCategoryCalls.append(request)
        if let error = createCategoryError?(request) { throw error }
        if let result = createCategoryResult?(request) { return result }
        return CategoryDTO(id: request.id, name: request.name, icon: request.icon,
                           createdAt: Date(), updatedAt: Date())
    }

    func updateCategory(id: String, request: CategoryUpdateRequest) async throws -> CategoryDTO {
        updateCategoryCalls.append((id, request))
        if let error = updateCategoryError?(id, request) { throw error }
        if let result = updateCategoryResult?(id, request) { return result }
        return CategoryDTO(id: id, name: request.name ?? "x", icon: request.icon ?? "circle",
                           createdAt: Date(), updatedAt: request.updatedAt)
    }

    func deleteCategory(id: String) async throws {
        deleteCategoryCalls.append(id)
        if let error = deleteCategoryError?(id) { throw error }
    }

    func getCategory(id: String) async throws -> CategoryDTO {
        getCategoryCalls.append(id)
        if let error = getCategoryError?(id) { throw error }
        if let result = getCategoryResult?(id) { return result }
        return CategoryDTO(id: id, name: "Server", icon: "circle",
                           createdAt: Date(), updatedAt: Date())
    }

    func listActivities() async throws -> [ActivityDTO] {
        listActivitiesCalls += 1
        if let listActivitiesError { throw listActivitiesError }
        return listActivitiesResult
    }

    func createActivity(_ request: ActivityCreateRequest) async throws -> ActivityDTO {
        createActivityCalls.append(request)
        if let error = createActivityError?(request) { throw error }
        if let result = createActivityResult?(request) { return result }
        return ActivityDTO(id: request.id, name: request.name, notes: request.notes,
                           lastUsedAt: nil, createdAt: Date(), updatedAt: Date(),
                           categories: [])
    }

    func updateActivity(id: String, request: ActivityUpdateRequest) async throws -> ActivityDTO {
        updateActivityCalls.append((id, request))
        if let error = updateActivityError?(id, request) { throw error }
        if let result = updateActivityResult?(id, request) { return result }
        return ActivityDTO(id: id, name: request.name ?? "x", notes: request.notes,
                           lastUsedAt: nil, createdAt: Date(), updatedAt: request.updatedAt,
                           categories: [])
    }

    func deleteActivity(id: String) async throws {
        deleteActivityCalls.append(id)
        if let error = deleteActivityError?(id) { throw error }
    }

    func getActivity(id: String) async throws -> ActivityDTO {
        getActivityCalls.append(id)
        if let error = getActivityError?(id) { throw error }
        if let result = getActivityResult?(id) { return result }
        return ActivityDTO(id: id, name: "Server", notes: nil, lastUsedAt: nil,
                           createdAt: Date(), updatedAt: Date(), categories: [])
    }
}
