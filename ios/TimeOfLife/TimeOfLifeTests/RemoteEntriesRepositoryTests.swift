import Testing
import Foundation
@testable import TimeOfLife

@Suite("RemoteEntriesRepository")
struct RemoteEntriesRepositoryTests {

    private func makeRepo() -> (RemoteEntriesRepository, MockAPIClient) {
        let mock = MockAPIClient()
        let repo = RemoteEntriesRepository(client: mock)
        return (repo, mock)
    }

    private func makeEntry() -> TimeEntry {
        TimeEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            activityId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            endedAt: Date(timeIntervalSinceReferenceDate: 3600),
            synced: false
        )
    }

    // MARK: - Create

    @Test("create calls POST /api/v1/entries with correct body")
    func createEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let entry = makeEntry()

        try await repo.create(entry)

        let r = try #require(mock.received.first)
        #expect(r.method == .post)
        #expect(r.path == "/api/v1/entries")
        #expect(r.requiresAuth == true)

        let body = try #require(r.body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EntryCreateRequest.self, from: body)
        #expect(decoded.id == entry.id)
        #expect(decoded.activityId == entry.activityId)
    }

    @Test("create handles success without throwing")
    func createSuccess() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }

        try await repo.create(makeEntry())
        #expect(mock.sendVoidCallCount == 1)
    }

    @Test("create propagates 404 activity_not_found")
    func createActivityNotFound() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in
            throw APIError.server(code: "activity_not_found", message: "Activity not found")
        }

        do {
            try await repo.create(makeEntry())
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "activity_not_found")
        }
    }

    // MARK: - Stop

    @Test("stop calls PATCH /api/v1/entries/{id}")
    func stopEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let id = UUID()
        let now = Date()

        try await repo.stop(id: id, endedAt: now, updatedAt: now)

        let r = try #require(mock.received.first)
        #expect(r.method == .patch)
        #expect(r.path == "/api/v1/entries/\(id.uuidString)")
        #expect(r.requiresAuth == true)
    }

    @Test("stop propagates 409 conflict")
    func stopConflict() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in
            throw APIError.server(code: "conflict", message: "Conflict",
                                  details: ["updated_at": "2024-01-15T10:00:00Z"])
        }

        do {
            try await repo.stop(id: UUID(), endedAt: Date(), updatedAt: Date())
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "conflict")
        }
    }

    // MARK: - Delete

    @Test("delete calls DELETE /api/v1/entries/{id}")
    func deleteEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let id = UUID()

        try await repo.delete(id: id)

        let r = try #require(mock.received.first)
        #expect(r.method == .delete)
        #expect(r.path == "/api/v1/entries/\(id.uuidString)")
        #expect(r.requiresAuth == true)
    }

    @Test("delete treats 404 as success")
    func deleteNotFoundIsSuccess() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in
            throw APIError.server(code: "not_found", message: "Not found")
        }

        // Should not throw.
        try await repo.delete(id: UUID())
    }

    // MARK: - Get

    @Test("get calls GET /api/v1/entries/{id}")
    func getEndpoint() async throws {
        let (repo, mock) = makeRepo()
        let id = UUID()
        let dto = EntryDTO(
            id: id,
            activityId: UUID(),
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        mock.sendHandler = { _, _ in dto }

        _ = try await repo.get(id: id)

        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/entries/\(id.uuidString)")
        #expect(r.requiresAuth == true)
    }

    @Test("get returns decoded EntryDTO")
    func getReturnsDTO() async throws {
        let (repo, mock) = makeRepo()
        let id = UUID()
        let dto = EntryDTO(
            id: id,
            activityId: UUID(),
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            endedAt: Date(timeIntervalSinceReferenceDate: 3600),
            activityName: "Reading"
        )
        mock.sendHandler = { _, _ in dto }

        let result = try await repo.get(id: id)

        #expect(result.id == dto.id)
        #expect(result.activityId == dto.activityId)
        #expect(result.activityName == "Reading")
    }

    // MARK: - JSON round-trip

    @Test("EntryDTO decodes backend snake_case payload with RFC 3339 dates")
    func entryDTODecodesBackendPayload() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let activityId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let categoryId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "activity_id": activityId.uuidString.lowercased(),
            "started_at": "2024-01-15T10:00:00Z",
            "ended_at": "2024-01-15T11:00:00Z",
            "duration_seconds": 3600.0,
            "created_at": "2024-01-15T10:00:00Z",
            "updated_at": "2024-01-15T11:00:00Z",
            "activity_name": "Reading",
            "categories": [
                [
                    "id": categoryId.uuidString.lowercased(),
                    "name": "Mind",
                    "icon": "tag",
                    "created_at": "2024-01-15T10:00:00Z",
                    "updated_at": "2024-01-15T10:00:00Z"
                ] as [String: Any]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(EntryDTO.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.activityId == activityId)
        #expect(decoded.durationSeconds == 3600.0)
        #expect(decoded.activityName == "Reading")
        #expect(decoded.endedAt != nil)
        let categories = try #require(decoded.categories)
        #expect(categories.count == 1)
        #expect(categories.first?.id == categoryId)
        #expect(categories.first?.icon == .tag)
    }

    // MARK: - Idempotent POST

    @Test("create replay with same id sends both requests")
    func createIdempotentReplay() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let entry = makeEntry()

        try await repo.create(entry)
        try await repo.create(entry)

        #expect(mock.sendVoidCallCount == 2)
    }

    // MARK: - Get error

    @Test("get propagates not_found")
    func getNotFound() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "not_found", message: "Not found")
        }

        do {
            _ = try await repo.get(id: UUID())
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "not_found")
        }
    }

    // MARK: - Stop 404

    @Test("stop treats 404 not_found as success")
    func stopNotFoundIsSuccess() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in
            throw APIError.server(code: "not_found", message: "Not found")
        }

        try await repo.stop(id: UUID(), endedAt: Date(), updatedAt: Date())
    }
}
