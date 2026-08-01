import Foundation

// MARK: - EntryDTO

/// Entry resource shape matching the backend `GET /entries` / `POST /entries`.
///
/// Snake_case CodingKeys match the JSON contract (`Activity_Catalog_API.md`).
/// Dates are RFC 3339 strings on the wire, decoded via `CatalogDateCoding`.
struct EntryDTO: Codable, Sendable, Equatable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double?
    let createdAt: Date
    let updatedAt: Date
    let activityName: String?
    let categories: [CategoryDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case activityName = "activity_name"
        case categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.activityId = try c.decode(UUID.self, forKey: .activityId)
        self.startedAt = try CatalogDateCoding.decodeDate(c, forKey: .startedAt)
        self.endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
            .flatMap { CatalogDateCoding.decode($0) }
        self.durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        self.createdAt = try CatalogDateCoding.decodeDate(c, forKey: .createdAt)
        self.updatedAt = try CatalogDateCoding.decodeDate(c, forKey: .updatedAt)
        self.activityName = try c.decodeIfPresent(String.self, forKey: .activityName)
        self.categories = try c.decodeIfPresent([CategoryDTO].self, forKey: .categories)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(CatalogDateCoding.encode(startedAt), forKey: .startedAt)
        try c.encodeIfPresent(endedAt.map(CatalogDateCoding.encode), forKey: .endedAt)
        try c.encode(CatalogDateCoding.encode(createdAt), forKey: .createdAt)
        try c.encode(CatalogDateCoding.encode(updatedAt), forKey: .updatedAt)
        // durationSeconds, activityName, categories are server-resolved; not sent.
    }

    init(
        id: UUID,
        activityId: UUID,
        startedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Double? = nil,
        activityName: String? = nil,
        categories: [CategoryDTO]? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activityName = activityName
        self.categories = categories
    }
}

// MARK: - Request bodies

/// `POST /entries` body: `{id, activity_id, started_at, ended_at?}`.
struct EntryCreateRequest: Codable, Sendable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(CatalogDateCoding.encode(startedAt), forKey: .startedAt)
        try c.encodeIfPresent(endedAt.map(CatalogDateCoding.encode), forKey: .endedAt)
    }
}

/// `PATCH /entries/{id}` body: `{ended_at, updated_at}`.
struct EntryStopRequest: Encodable, Sendable {
    let endedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(CatalogDateCoding.encode(endedAt), forKey: .endedAt)
        try c.encode(CatalogDateCoding.encode(updatedAt), forKey: .updatedAt)
    }
}

// MARK: - EntriesRepository protocol

/// Remote persistence contract for time entries.
///
/// Replaces `TimerRepository`. All endpoints require auth.
/// POST is idempotent on the client-generated UUID v7 `id`.
protocol EntriesRepository: Sendable {
    /// Creates a new time entry. Idempotent on `id` (replay returns existing).
    func create(_ entry: TimeEntry) async throws
    /// Stops a running entry by setting `endedAt`. Carries `updatedAt` for LWW.
    func stop(id: UUID, endedAt: Date, updatedAt: Date) async throws
    /// Deletes an entry. 404 is treated as success (already removed).
    func delete(id: UUID) async throws
    /// Fetches a single entry by id.
    func get(id: UUID) async throws -> EntryDTO
}

// MARK: - RemoteEntriesRepository

/// `EntriesRepository` backed by an `APIClient`. Mirrors `RemoteAuthRepository`
/// over `APISending` with basePath `/api/v1/entries`.
final class RemoteEntriesRepository: EntriesRepository {
    private let client: APISending
    private let basePath = "/api/v1/entries"

    init(client: APISending) {
        self.client = client
    }

    func create(_ entry: TimeEntry) async throws {
        let body = EntryCreateRequest(
            id: entry.id,
            activityId: entry.activityId,
            startedAt: entry.startedAt,
            endedAt: entry.endedAt
        )
        try await client.sendVoid(
            APIEndpoint(method: .post, path: basePath, body: body, requiresAuth: true)
        )
    }

    func stop(id: UUID, endedAt: Date, updatedAt: Date) async throws {
        let body = EntryStopRequest(endedAt: endedAt, updatedAt: updatedAt)
        do {
            try await client.sendVoid(
                APIEndpoint(
                    method: .patch,
                    path: "\(basePath)/\(id.uuidString)",
                    body: body,
                    requiresAuth: true
                )
            )
        } catch let error as APIError {
            if case let .server(code, _, _) = error, code == "not_found" { return }
            throw error
        }
    }

    func delete(id: UUID) async throws {
        do {
            try await client.sendVoid(
                APIEndpoint.value(
                    method: .delete,
                    path: "\(basePath)/\(id.uuidString)",
                    requiresAuth: true
                )
            )
        } catch let error as APIError {
            if case let .server(code, _, _) = error, code == "not_found" {
                return
            }
            throw error
        }
    }

    func get(id: UUID) async throws -> EntryDTO {
        try await client.send(
            APIEndpoint.value(
                method: .get,
                path: "\(basePath)/\(id.uuidString)",
                requiresAuth: true
            ),
            as: EntryDTO.self
        )
    }
}
