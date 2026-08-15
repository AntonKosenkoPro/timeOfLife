// swiftlint:disable file_length
import Foundation

/// The backend relay's catalog/entries contract (catalog feature + local-first
/// additions). The backend is an optional relay, not the source of truth:
/// the client pushes outbox rows and pulls deltas via `modified_since`.
protocol CatalogSending: Sendable {
    /// `GET /activities?modified_since=` — full pull when `modifiedSince` is nil.
    func fetchActivities(modifiedSince: Date?) async throws -> [Activity]
    /// `GET /categories` — full pull (categories have no delta cursor yet).
    func fetchCategories() async throws -> [Category]
    /// `GET /entries?modified_since=` — full pull when `modifiedSince` is nil.
    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry]
    /// `GET /activities/{id}` — used to adopt the server's version on conflict.
    func fetchActivity(id: String) async throws -> Activity
    /// `GET /categories/{id}` — used to adopt the server's version on conflict.
    func fetchCategory(id: String) async throws -> Category
    /// `GET /entries/{id}` — used to adopt the server's version on conflict.
    func fetchEntry(id: String) async throws -> TimeEntry
    /// `POST /activities` — idempotent on `id`.
    func createActivity(_ activity: Activity) async throws
    /// `PATCH /activities/{id}` — LWW on `updated_at`.
    func updateActivity(_ activity: Activity) async throws
    /// `DELETE /activities/{id}`.
    func deleteActivity(id: String) async throws
    /// `POST /categories` — idempotent on `id`.
    func createCategory(_ category: Category) async throws
    /// `PATCH /categories/{id}` — LWW on `updated_at`.
    func updateCategory(_ category: Category) async throws
    /// `DELETE /categories/{id}`.
    func deleteCategory(id: String) async throws
    /// `POST /entries` — idempotent on `id`.
    func createEntry(_ entry: TimeEntry) async throws
    /// `PATCH /entries/{id}` — LWW on `updated_at`.
    func updateEntry(_ entry: TimeEntry) async throws
    /// `DELETE /entries/{id}`.
    func deleteEntry(id: String) async throws
}

/// `CatalogSending` backed by the shared `APIClient` (Bearer auth, refresh,
/// uniform error envelope).
final class RemoteCatalogRepository: CatalogSending {
    private let client: APISending
    private let basePath = "/api/v1"

    init(client: APISending) {
        self.client = client
    }

    func fetchActivities(modifiedSince: Date?) async throws -> [Activity] {
        let response = try await client.send(
            APIEndpoint.value(method: .get, path: activitiesPath(modifiedSince: modifiedSince),
                              requiresAuth: true),
            as: [ActivityWireDTO].self
        )
        return response.map(Self.localActivity(from:))
    }

    func fetchCategories() async throws -> [Category] {
        try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/categories", requiresAuth: true),
            as: [Category].self
        )
    }

    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry] {
        let response = try await client.send(
            APIEndpoint.value(method: .get, path: entriesPath(modifiedSince: modifiedSince),
                              requiresAuth: true),
            as: EntryListResponse.self
        )
        return response.items
    }

    func fetchActivity(id: String) async throws -> Activity {
        let dto = try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/activities/\(id)", requiresAuth: true),
            as: ActivityWireDTO.self
        )
        return Self.localActivity(from: dto)
    }

    func fetchCategory(id: String) async throws -> Category {
        try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/categories/\(id)", requiresAuth: true),
            as: Category.self
        )
    }

    func fetchEntry(id: String) async throws -> TimeEntry {
        try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/entries/\(id)", requiresAuth: true),
            as: TimeEntry.self
        )
    }

    func createActivity(_ activity: Activity) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/activities",
                        body: ActivityCreateBody(activity: activity), requiresAuth: true)
        )
    }

    func updateActivity(_ activity: Activity) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .patch, path: "\(basePath)/activities/\(activity.id)",
                        body: ActivityUpdateBody(activity: activity), requiresAuth: true)
        )
    }

    func deleteActivity(id: String) async throws {
        try await client.sendVoid(
            APIEndpoint.value(method: .delete, path: "\(basePath)/activities/\(id)", requiresAuth: true)
        )
    }

    func createCategory(_ category: Category) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/categories",
                        body: CategoryCreateBody(category: category), requiresAuth: true)
        )
    }

    func updateCategory(_ category: Category) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .patch, path: "\(basePath)/categories/\(category.id)",
                        body: CategoryUpdateBody(category: category), requiresAuth: true)
        )
    }

    func deleteCategory(id: String) async throws {
        try await client.sendVoid(
            APIEndpoint.value(method: .delete, path: "\(basePath)/categories/\(id)", requiresAuth: true)
        )
    }

    func createEntry(_ entry: TimeEntry) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/entries",
                        body: EntryCreateBody(entry: entry), requiresAuth: true)
        )
    }

    func updateEntry(_ entry: TimeEntry) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .patch, path: "\(basePath)/entries/\(entry.id)",
                        body: EntryUpdateBody(entry: entry), requiresAuth: true)
        )
    }

    func deleteEntry(id: String) async throws {
        try await client.sendVoid(
            APIEndpoint.value(method: .delete, path: "\(basePath)/entries/\(id)", requiresAuth: true)
        )
    }

    /// Maps the wire Activity (embedded `categories`) to the local model
    /// (ordered `categoryIDs`) (category-management D5).
    private static func localActivity(from dto: ActivityWireDTO) -> Activity {
        Activity(
            id: dto.id,
            name: dto.name,
            notes: dto.notes,
            lastUsedAt: dto.lastUsedAt,
            categoryIDs: dto.categories.map(\.id),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    // MARK: - Paths

    private func activitiesPath(modifiedSince: Date?) -> String {
        var path = "\(basePath)/activities"
        if let modifiedSince {
            path += "?modified_since=\(Self.rfc3339(modifiedSince))"
        }
        return path
    }

    private func entriesPath(modifiedSince: Date?) -> String {
        var path = "\(basePath)/entries"
        if let modifiedSince {
            path += "?modified_since=\(Self.rfc3339(modifiedSince))"
        }
        return path
    }

    private static func rfc3339(_ date: Date) -> String {
        // A fresh formatter per call: ISO8601DateFormatter is not Sendable and
        // the catalog client may be called from any actor.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// `GET /entries` response envelope.
struct EntryListResponse: Decodable, Sendable {
    let items: [TimeEntry]
}

/// RFC 3339 date codec for the relay wire format (OpenAPI `format: date-time`).
/// The default JSONDecoder/JSONEncoder use `Double` timestamps, which neither
/// the OpenAPI contract nor the backend accepts — every wire DTO decodes
/// dates through this type and every request body encodes them through it.
enum WireDate {
    /// Parses an RFC 3339 timestamp (with or without fractional seconds).
    static func parse(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter.withFractional.date(from: string) {
            return date
        }
        return ISO8601DateFormatter.plain.date(from: string)
    }

    /// Formats a Date as RFC 3339 with fractional seconds.
    static func format(_ date: Date) -> String {
        ISO8601DateFormatter.withFractional.string(from: date)
    }
}

fileprivate extension ISO8601DateFormatter {
    /// A fresh formatter per use — ISO8601DateFormatter is not Sendable and
    /// the catalog client may be called from any actor.
    static var withFractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static var plain: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

/// The wire shape of an Activity as the relay returns it
/// (category-management D5): the response embeds `categories` as CategoryTag
/// objects and RFC 3339 timestamps, which the local `Activity` model does not
/// decode directly. The repository maps this DTO to the local ordered
/// `categoryIDs`.
struct ActivityWireDTO: Decodable, Sendable {
    let id: String
    let name: String
    let notes: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let categories: [CategoryTagDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        categories = try container.decode([CategoryTagDTO].self, forKey: .categories)
        func date(_ key: CodingKeys) throws -> Date {
            let raw = try container.decode(String.self, forKey: key)
            guard let parsed = WireDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Invalid RFC 3339 date: \(raw)"
                )
            }
            return parsed
        }
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt).flatMap(WireDate.parse)
        createdAt = try date(.createdAt)
        updatedAt = try date(.updatedAt)
    }
}

/// An embedded category tag in an Activity/Entry response
/// (OpenAPI `CategoryTag`).
struct CategoryTagDTO: Decodable, Sendable {
    let id: String
    let name: String
    let icon: String
}

// MARK: - Request bodies (mirror the OpenAPI contract)

struct ActivityCreateBody: Encodable, Sendable {
    let id: String
    let name: String
    let notes: String?
    let categoryIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case categoryIDs = "category_ids"
    }

    init(activity: Activity) {
        self.id = activity.id
        self.name = activity.name
        self.notes = activity.notes
        self.categoryIDs = activity.categoryIDs
    }
}

struct ActivityUpdateBody: Encodable, Sendable {
    let name: String
    let notes: String?
    let categoryIDs: [String]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, notes
        case categoryIDs = "category_ids"
        case updatedAt = "updated_at"
    }

    init(activity: Activity) {
        self.name = activity.name
        self.notes = activity.notes
        self.categoryIDs = activity.categoryIDs
        self.updatedAt = WireDate.format(activity.updatedAt)
    }
}

struct CategoryCreateBody: Encodable, Sendable {
    let id: String
    let name: String
    let icon: String

    init(category: Category) {
        self.id = category.id
        self.name = category.name
        self.icon = category.icon
    }
}

struct CategoryUpdateBody: Encodable, Sendable {
    let name: String
    let icon: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, icon
        case updatedAt = "updated_at"
    }

    init(category: Category) {
        self.name = category.name
        self.icon = category.icon
        self.updatedAt = WireDate.format(category.updatedAt)
    }
}

struct EntryCreateBody: Encodable, Sendable {
    let id: String
    let activityID: String
    let startedAt: String
    let endedAt: String?
    let source: String
    let sourceRef: String?

    enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case source
        case sourceRef = "source_ref"
    }

    init(entry: TimeEntry) {
        self.id = entry.id
        self.activityID = entry.activityID
        self.startedAt = WireDate.format(entry.startedAt)
        self.endedAt = entry.endedAt.map(WireDate.format)
        self.source = entry.source
        self.sourceRef = entry.sourceRef
    }
}

struct EntryUpdateBody: Encodable, Sendable {
    let startedAt: String
    let endedAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
    }

    init(entry: TimeEntry) {
        self.startedAt = WireDate.format(entry.startedAt)
        self.endedAt = entry.endedAt.map(WireDate.format)
        self.updatedAt = WireDate.format(entry.updatedAt)
    }
}
