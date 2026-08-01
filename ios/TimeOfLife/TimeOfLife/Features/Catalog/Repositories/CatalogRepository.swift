import Foundation

/// Remote persistence contract for the activity/category catalog.
///
/// Mirrors `AuthRepository` / `RemoteAuthRepository`'s shape over `APISending`.
/// All endpoints require a Bearer token (`Activity_Catalog_API.md`).
protocol CatalogRepository: Sendable {
    func listActivities(query: String?) async throws -> [Activity]
    func getActivity(_ id: UUID) async throws -> Activity
    func createActivity(_ activity: Activity) async throws -> Activity
    func updateActivity(_ activity: Activity) async throws -> Activity
    func deleteActivity(_ id: UUID) async throws
    func listCategories() async throws -> [Category]
    func getCategory(_ id: UUID) async throws -> Category
    func createCategory(_ category: Category) async throws -> Category
    func updateCategory(_ category: Category) async throws -> Category
    func deleteCategory(_ id: UUID) async throws
}

// MARK: - CatalogError

/// Catalog-domain errors the caller can switch on, mapped from `APIError`.
///
/// `details` shapes follow the actual backend (`catalog.go`):
/// - `409 conflict` → `{updated_at}` (RFC 3339); the caller re-fetches the full
///   record and adopts it (keep-latest, R2). The backend does NOT send the
///   full record for conflicts — only `updated_at` (deviation from the story's
///   `serverVersion: Activity?/Category?`, per "inspect what the backend sends").
/// - `409 activity_exists` / `category_exists` → `{id, name}` of the survivor;
///   the caller re-maps local references to the surviving id (F4).
/// - `422 validation_error` → `{field: message}` map.
enum CatalogError: Error, Equatable, Sendable {
    /// 409 `conflict` — LWW stale write; carries the server's `updated_at`.
    case conflict(serverUpdatedAt: Date?)
    /// 409 `activity_exists` — case-insensitive name collision; surviving record.
    case activityExists(existingId: UUID, existingName: String)
    /// 409 `category_exists` — case-insensitive name collision; surviving record.
    case categoryExists(existingId: UUID, existingName: String)
    /// 422 `validation_error` — field → message map.
    case validation(fields: [String: String])
    /// 404 `not_found` (or `activity_not_found`).
    case notFound
    /// No connectivity (from `APIError.offline`).
    case offline
    /// Unmapped `APIError` passthrough.
    case underlying(APIError)
    /// Non-APIError passthrough with original description.
    case unexpected(description: String)

    /// Maps any thrown error (coerced to `APIError`) into a `CatalogError`.
    static func map(_ error: Error) -> CatalogError {
        guard let api = error as? APIError else {
            return .unexpected(description: error.localizedDescription)
        }
        switch api {
        case .offline:
            return .offline
        case let .server(code, _, details):
            return mapServerError(code: code, details: details, api: api)
        default:
            return .underlying(api)
        }
    }

    private static func mapServerError(
        code: String,
        details: [String: String],
        api: APIError
    ) -> CatalogError {
        switch code {
        case "conflict":
            return .conflict(serverUpdatedAt: parseUpdatedAt(details))
        case "activity_exists":
            guard let existingId = parseId(details) else {
                return .unexpected(description: "activity_exists missing id in details")
            }
            return .activityExists(existingId: existingId, existingName: parseName(details) ?? "")
        case "category_exists":
            guard let existingId = parseId(details) else {
                return .unexpected(description: "category_exists missing id in details")
            }
            return .categoryExists(existingId: existingId, existingName: parseName(details) ?? "")
        case "validation_error":
            return .validation(fields: parseFieldMap(details))
        case "not_found", "activity_not_found":
            return .notFound
        default:
            return .underlying(api)
        }
    }

    private static func parseUpdatedAt(_ details: [String: String]) -> Date? {
        guard let raw = details["updated_at"] else { return nil }
        return CatalogDateCoding.decode(raw)
    }

    private static func parseId(_ details: [String: String]) -> UUID? {
        guard let raw = details["id"] else { return nil }
        return UUID(uuidString: raw)
    }

    private static func parseName(_ details: [String: String]) -> String? {
        details["name"]
    }

    private static func parseFieldMap(_ details: [String: String]) -> [String: String] {
        details
    }
}

// MARK: - RemoteCatalogRepository

/// `CatalogRepository` backed by an `APIClient`. Maps domain calls onto the
/// catalog endpoints; does not own local state — that's `CatalogStore` /
/// `CatalogService`. Mirrors `RemoteAuthRepository` over `APISending`.
final class RemoteCatalogRepository: CatalogRepository {
    private let client: APISending
    private let basePath = "/api/v1"

    init(client: APISending) {
        self.client = client
    }

    // MARK: Activities

    func listActivities(query: String?) async throws -> [Activity] {
        var path = "\(basePath)/activities"
        if let query, !query.isEmpty {
            var components = URLComponents(string: path)
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            path = components?.url?.absoluteString ?? path
        }
        do {
            let dtos = try await client.send(
                APIEndpoint.value(method: .get, path: path, requiresAuth: true),
                as: [ActivityDTO].self
            )
            return dtos.map { $0.toActivity() }
        } catch {
            throw CatalogError.map(error)
        }
    }

    func getActivity(_ id: UUID) async throws -> Activity {
        do {
            let dto = try await client.send(
                APIEndpoint.value(method: .get, path: "\(basePath)/activities/\(id.uuidString)", requiresAuth: true),
                as: ActivityDTO.self
            )
            return dto.toActivity()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func createActivity(_ activity: Activity) async throws -> Activity {
        let body = ActivityCreateRequest(
            id: activity.id,
            name: activity.name,
            color: activity.color,
            icon: activity.icon,
            notes: activity.notes,
            categoryIds: activity.categoryIds
        )
        do {
            let dto = try await client.send(
                APIEndpoint(method: .post, path: "\(basePath)/activities", body: body, requiresAuth: true),
                as: ActivityDTO.self
            )
            return dto.toActivity()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func updateActivity(_ activity: Activity) async throws -> Activity {
        let body = ActivityPatchRequest(
            name: activity.name,
            color: activity.color,
            icon: activity.icon,
            // PATCH needs an explicit empty string to clear an existing note.
            notes: activity.notes ?? "",
            categoryIds: activity.categoryIds,
            updatedAt: activity.updatedAt
        )
        do {
            let dto = try await client.send(
                APIEndpoint(method: .patch, path: "\(basePath)/activities/\(activity.id.uuidString)",
                            body: body, requiresAuth: true),
                as: ActivityDTO.self
            )
            return dto.toActivity()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func deleteActivity(_ id: UUID) async throws {
        do {
            try await client.sendVoid(
                APIEndpoint.value(method: .delete, path: "\(basePath)/activities/\(id.uuidString)", requiresAuth: true)
            )
        } catch {
            throw CatalogError.map(error)
        }
    }

    // MARK: Categories

    func listCategories() async throws -> [Category] {
        do {
            let dtos = try await client.send(
                APIEndpoint.value(method: .get, path: "\(basePath)/categories", requiresAuth: true),
                as: [CategoryDTO].self
            )
            return dtos.map { $0.toCategory() }
        } catch {
            throw CatalogError.map(error)
        }
    }

    func getCategory(_ id: UUID) async throws -> Category {
        do {
            let dto = try await client.send(
                APIEndpoint.value(method: .get, path: "\(basePath)/categories/\(id.uuidString)", requiresAuth: true),
                as: CategoryDTO.self
            )
            return dto.toCategory()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func createCategory(_ category: Category) async throws -> Category {
        let body = CategoryCreateRequest(id: category.id, name: category.name, color: category.color)
        do {
            let dto = try await client.send(
                APIEndpoint(method: .post, path: "\(basePath)/categories", body: body, requiresAuth: true),
                as: CategoryDTO.self
            )
            return dto.toCategory()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func updateCategory(_ category: Category) async throws -> Category {
        let body = CategoryPatchRequest(name: category.name, color: category.color, updatedAt: category.updatedAt)
        do {
            let dto = try await client.send(
                APIEndpoint(method: .patch, path: "\(basePath)/categories/\(category.id.uuidString)",
                            body: body, requiresAuth: true),
                as: CategoryDTO.self
            )
            return dto.toCategory()
        } catch {
            throw CatalogError.map(error)
        }
    }

    func deleteCategory(_ id: UUID) async throws {
        do {
            try await client.sendVoid(
                APIEndpoint.value(method: .delete, path: "\(basePath)/categories/\(id.uuidString)", requiresAuth: true)
            )
        } catch {
            throw CatalogError.map(error)
        }
    }
}

// MARK: - User-facing messages

extension ErrorLocalization {
    /// Maps a `CatalogError` to a localized user-facing string via the
    /// `error.<code>` keys shared with server codes (`L10n.text(in:code:)`).
    static func message(for error: CatalogError) -> String {
        switch error {
        case .conflict:
            return L10n.text(in: .default, code: "conflict")
        case .activityExists:
            return L10n.text(in: .default, code: "activity_exists")
        case .categoryExists:
            return L10n.text(in: .default, code: "category_exists")
        case .validation:
            return L10n.text(in: .default, code: "validation_error")
        case .notFound:
            return L10n.text(in: .default, code: "not_found")
        case .offline:
            return L10n.text(in: .default, code: "offline")
        case let .underlying(api):
            return message(for: api)
        case let .unexpected(description):
            return description
        }
    }
}
