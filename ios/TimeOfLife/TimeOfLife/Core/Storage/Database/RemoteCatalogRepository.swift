import Foundation

/// Protocol for the remote catalog repository, allowing test doubles.
protocol CatalogRemoteSending: Sendable {
    func listCategories() async throws -> [CategoryDTO]
    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO
    func updateCategory(id: String, request: CategoryUpdateRequest) async throws -> CategoryDTO
    func deleteCategory(id: String) async throws
    func getCategory(id: String) async throws -> CategoryDTO
    func listActivities() async throws -> [ActivityDTO]
    func createActivity(_ request: ActivityCreateRequest) async throws -> ActivityDTO
    func updateActivity(id: String, request: ActivityUpdateRequest) async throws -> ActivityDTO
    func deleteActivity(id: String) async throws
    func getActivity(id: String) async throws -> ActivityDTO
}

/// Remote catalog repository — wraps an `APISending` client for the
/// `/api/v1/categories` and `/api/v1/activities` endpoints.
///
/// All methods are `Sendable` (no isolated state); the caller (typically
/// `SyncCoordinator`) serializes calls as needed.
final class RemoteCatalogRepository: CatalogRemoteSending {
    private let client: APISending

    init(client: APISending) {
        self.client = client
    }

    // MARK: - Categories

    /// `GET /categories` — returns all categories (name order).
    func listCategories() async throws -> [CategoryDTO] {
        let endpoint = APIEndpoint(
            method: .get, path: "/api/v1/categories", requiresAuth: true)
        return try await client.send(endpoint, as: [CategoryDTO].self)
    }

    /// `POST /categories` — idempotent on `id`.
    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO {
        let endpoint = APIEndpoint(
            method: .post, path: "/api/v1/categories",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: CategoryDTO.self)
    }

    /// `PATCH /categories/{id}` — last-write-wins on `updated_at`.
    func updateCategory(id: String, request: CategoryUpdateRequest) async throws -> CategoryDTO {
        let endpoint = APIEndpoint(
            method: .patch, path: "/api/v1/categories/\(id)",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: CategoryDTO.self)
    }

    /// `DELETE /categories/{id}` — 204 or 404 (both success).
    func deleteCategory(id: String) async throws {
        let endpoint = APIEndpoint(
            method: .delete, path: "/api/v1/categories/\(id)", requiresAuth: true)
        try await client.sendVoid(endpoint)
    }

    /// `GET /categories/{id}` — fetch the canonical category (used after 409 conflict).
    func getCategory(id: String) async throws -> CategoryDTO {
        let endpoint = APIEndpoint(
            method: .get, path: "/api/v1/categories/\(id)", requiresAuth: true)
        return try await client.send(endpoint, as: CategoryDTO.self)
    }

    // MARK: - Activities

    /// `GET /activities` — returns all activities (recency order; `?q=` typeahead).
    func listActivities() async throws -> [ActivityDTO] {
        let endpoint = APIEndpoint(
            method: .get, path: "/api/v1/activities", requiresAuth: true)
        return try await client.send(endpoint, as: [ActivityDTO].self)
    }

    /// `POST /activities` — idempotent on `id`.
    func createActivity(_ request: ActivityCreateRequest) async throws -> ActivityDTO {
        let endpoint = APIEndpoint(
            method: .post, path: "/api/v1/activities",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: ActivityDTO.self)
    }

    /// `PATCH /activities/{id}` — last-write-wins on `updated_at`.
    func updateActivity(id: String, request: ActivityUpdateRequest) async throws -> ActivityDTO {
        let endpoint = APIEndpoint(
            method: .patch, path: "/api/v1/activities/\(id)",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: ActivityDTO.self)
    }

    /// `DELETE /activities/{id}` — 204 or 404 (both success). Cascades to entries + tags.
    func deleteActivity(id: String) async throws {
        let endpoint = APIEndpoint(
            method: .delete, path: "/api/v1/activities/\(id)", requiresAuth: true)
        try await client.sendVoid(endpoint)
    }

    /// `GET /activities/{id}` — fetch the canonical activity (used after 409 conflict).
    func getActivity(id: String) async throws -> ActivityDTO {
        let endpoint = APIEndpoint(
            method: .get, path: "/api/v1/activities/\(id)", requiresAuth: true)
        return try await client.send(endpoint, as: ActivityDTO.self)
    }
}
