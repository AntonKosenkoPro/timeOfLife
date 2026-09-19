// swiftlint:disable file_length
import Foundation

/// The backend relay's categories/entries contract (catalog feature + local-
/// first additions, remove-activities-layer: no activity routes). The backend
/// is an optional relay, not the source of truth: the client pushes outbox
/// rows and pulls deltas via `modified_since`.
protocol CatalogSending: Sendable {
    /// `GET /categories` — full pull (the authoritative category snapshot).
    func fetchCategories() async throws -> [Category]
    /// `GET /entries?modified_since=` — full pull when `modifiedSince` is nil.
    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry]
    /// `GET /deletions?deleted_since=` — full list when `since` is nil
    /// (cross-device-delete-propagation; entries and categories only).
    func fetchDeletions(since: Date?) async throws -> [Deletion]
    /// `GET /categories/{id}` — used to adopt the server's version on conflict.
    func fetchCategory(id: String) async throws -> Category
    /// `GET /entries/{id}` — used to adopt the server's version on conflict.
    func fetchEntry(id: String) async throws -> TimeEntry
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

    func fetchCategories() async throws -> [Category] {
        let response = try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/categories", requiresAuth: true),
            as: [CategoryWireDTO].self
        )
        return response.map(Self.localCategory(from:))
    }

    func fetchEntries(modifiedSince: Date?) async throws -> [TimeEntry] {
        let response = try await client.send(
            APIEndpoint.value(method: .get, path: entriesPath(modifiedSince: modifiedSince),
                              requiresAuth: true),
            as: EntryListResponse.self
        )
        return response.items.map(Self.localEntry(from:))
    }

    func fetchDeletions(since: Date?) async throws -> [Deletion] {
        let response = try await client.send(
            APIEndpoint.value(method: .get, path: deletionsPath(since: since), requiresAuth: true),
            as: [DeletionWireDTO].self
        )
        return response.map(Self.localDeletion(from:))
    }

    func fetchCategory(id: String) async throws -> Category {
        let dto = try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/categories/\(id)", requiresAuth: true),
            as: CategoryWireDTO.self
        )
        return Self.localCategory(from: dto)
    }

    func fetchEntry(id: String) async throws -> TimeEntry {
        let dto = try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/entries/\(id)", requiresAuth: true),
            as: EntryWireDTO.self
        )
        return Self.localEntry(from: dto)
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

    /// Maps the wire Category (RFC 3339 timestamps) to the local model.
    private static func localCategory(from dto: CategoryWireDTO) -> Category {
        Category(
            id: dto.id,
            name: dto.name,
            icon: dto.icon,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    /// Maps the wire Entry (RFC 3339 timestamps, ordered `category_ids`)
    /// to the local model.
    private static func localEntry(from dto: EntryWireDTO) -> TimeEntry {
        TimeEntry(
            id: dto.id,
            activityText: dto.activityText,
            startedAt: dto.startedAt,
            endedAt: dto.endedAt,
            durationSeconds: dto.durationSeconds,
            source: dto.source,
            sourceRef: dto.sourceRef,
            categoryIDs: dto.categoryIDs,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    /// Maps the wire Deletion tombstone (RFC 3339 timestamps) to the local model.
    private static func localDeletion(from dto: DeletionWireDTO) -> Deletion {
        Deletion(resource: dto.resource, recordID: dto.id, deletedAt: dto.deletedAt)
    }

    // MARK: - Paths

    private func entriesPath(modifiedSince: Date?) -> String {
        var path = "\(basePath)/entries"
        if let modifiedSince {
            path += "?modified_since=\(Self.rfc3339(modifiedSince))"
        }
        return path
    }

    private func deletionsPath(since: Date?) -> String {
        var path = "\(basePath)/deletions"
        if let since {
            path += "?deleted_since=\(Self.rfc3339(since))"
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
    let items: [EntryWireDTO]
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

    /// Decodes a required RFC 3339 date from a keyed container.
    static func decode<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        guard let parsed = parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid RFC 3339 date: \(raw)"
            )
        }
        return parsed
    }

    /// Decodes an optional RFC 3339 date from a keyed container.
    static func decodeIfPresent<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date? {
        try container.decodeIfPresent(String.self, forKey: key).flatMap(parse)
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

/// The wire shape of a Category as the relay returns it: RFC 3339
/// timestamps, which the local `Category` model does not decode directly
/// (default Codable expects `Double`).
struct CategoryWireDTO: Decodable, Sendable {
    let id: String
    let name: String
    let icon: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        createdAt = try WireDate.decode(container, forKey: .createdAt)
        updatedAt = try WireDate.decode(container, forKey: .updatedAt)
    }
}

/// The wire shape of an Entry as the relay returns it (OpenAPI `Entry`):
/// RFC 3339 timestamps plus the entry-owned `activity_text`, ordered
/// `category_ids`, and `notes` (remove-activities-layer; no `activity_id`).
struct EntryWireDTO: Decodable, Sendable {
    let id: String
    let activityText: String
    let categoryIDs: [String]
    let notes: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let source: String
    let sourceRef: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityText = "activity_text"
        case categoryIDs = "category_ids"
        case notes
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case source
        case sourceRef = "source_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        activityText = try container.decode(String.self, forKey: .activityText)
        categoryIDs = try container.decodeIfPresent([String].self, forKey: .categoryIDs) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        startedAt = try WireDate.decode(container, forKey: .startedAt)
        endedAt = try WireDate.decodeIfPresent(container, forKey: .endedAt)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        // Older relays predate entry provenance and omit `source`; the
        // backend itself defaults those to "manual" (back-compat), so do the
        // same instead of failing the whole pull on keyNotFound.
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        sourceRef = try container.decodeIfPresent(String.self, forKey: .sourceRef)
        createdAt = try WireDate.decode(container, forKey: .createdAt)
        updatedAt = try WireDate.decode(container, forKey: .updatedAt)
    }
}

/// The wire shape of a Deletion tombstone as the relay returns it
/// (OpenAPI `Deletion`, cross-device-delete-propagation): RFC 3339
/// timestamps, which the local `Deletion` model does not decode directly.
struct DeletionWireDTO: Decodable, Sendable {
    let resource: String
    let id: String
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case resource, id
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resource = try container.decode(String.self, forKey: .resource)
        id = try container.decode(String.self, forKey: .id)
        deletedAt = try WireDate.decode(container, forKey: .deletedAt)
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
    let activityText: String
    let categoryIDs: [String]
    let notes: String
    let startedAt: String
    let endedAt: String?
    let source: String
    let sourceRef: String?

    enum CodingKeys: String, CodingKey {
        case id
        case activityText = "activity_text"
        case categoryIDs = "category_ids"
        case notes
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case source
        case sourceRef = "source_ref"
    }

    init(entry: TimeEntry) {
        self.id = entry.id
        self.activityText = entry.activityText
        self.categoryIDs = entry.categoryIDs
        self.notes = entry.notes
        self.startedAt = WireDate.format(entry.startedAt)
        self.endedAt = entry.endedAt.map(WireDate.format)
        self.source = entry.source
        self.sourceRef = entry.sourceRef
    }
}

struct EntryUpdateBody: Encodable, Sendable {
    let activityText: String
    let categoryIDs: [String]
    let notes: String
    let startedAt: String
    let endedAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case activityText = "activity_text"
        case categoryIDs = "category_ids"
        case notes
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
    }

    init(entry: TimeEntry) {
        self.activityText = entry.activityText
        self.categoryIDs = entry.categoryIDs
        self.notes = entry.notes
        self.startedAt = WireDate.format(entry.startedAt)
        self.endedAt = entry.endedAt.map(WireDate.format)
        self.updatedAt = WireDate.format(entry.updatedAt)
    }
}
