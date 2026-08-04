import Foundation

/// Protocol for the remote entries repository, allowing test doubles.
protocol EntriesRemoteSending: Sendable {
    func listEntries(cursor: String?, limit: Int) async throws -> EntryListResponseDTO
    func listAllEntries() async throws -> [EntryDTO]
    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO
    func updateEntry(id: String, request: EntryUpdateRequest) async throws -> EntryDTO
    func deleteEntry(id: String) async throws
    func getEntry(id: String) async throws -> EntryDTO
}

/// Remote entries repository — wraps an `APISending` client for the
/// `/api/v1/entries` endpoints.
///
/// Includes cursor-based pagination via `listEntries` (AC5: full entry pull
/// across all cursor pages, even though the History UI is Epic 2).
final class RemoteEntriesRepository: EntriesRemoteSending {
    private let client: APISending

    init(client: APISending) {
        self.client = client
    }

    // MARK: - Entries

    /// `GET /entries` — one page of entries. Pass `cursor` for pagination.
    func listEntries(cursor: String? = nil, limit: Int = 100) async throws -> EntryListResponseDTO {
        var path = "/api/v1/entries?limit=\(limit)"
        if let cursor {
            let escaped = cursor.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? cursor
            path += "&cursor=\(escaped)"
        }
        let endpoint = APIEndpoint(
            method: .get, path: path, requiresAuth: true)
        return try await client.send(endpoint, as: EntryListResponseDTO.self)
    }

    /// Fetches **all** entry pages by following `next_cursor` until `nil`.
    /// Used by the `SyncCoordinator` during the pull phase (AC5).
    func listAllEntries() async throws -> [EntryDTO] {
        var all: [EntryDTO] = []
        var cursor: String?
        repeat {
            let page = try await listEntries(cursor: cursor, limit: 100)
            all.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return all
    }

    /// `POST /entries` — idempotent on `id`; `activity_id` required.
    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        let endpoint = APIEndpoint(
            method: .post, path: "/api/v1/entries",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: EntryDTO.self)
    }

    /// `PATCH /entries/{id}` — recompute `duration_seconds`.
    func updateEntry(id: String, request: EntryUpdateRequest) async throws -> EntryDTO {
        let endpoint = APIEndpoint(
            method: .patch, path: "/api/v1/entries/\(id)",
            body: request, requiresAuth: true)
        return try await client.send(endpoint, as: EntryDTO.self)
    }

    /// `DELETE /entries/{id}` — 204 or 404 (both success).
    func deleteEntry(id: String) async throws {
        let endpoint = APIEndpoint(
            method: .delete, path: "/api/v1/entries/\(id)", requiresAuth: true)
        try await client.sendVoid(endpoint)
    }

    /// `GET /entries/{id}` — fetch the canonical entry (used after 409 conflict).
    func getEntry(id: String) async throws -> EntryDTO {
        let endpoint = APIEndpoint(
            method: .get, path: "/api/v1/entries/\(id)", requiresAuth: true)
        return try await client.send(endpoint, as: EntryDTO.self)
    }
}
