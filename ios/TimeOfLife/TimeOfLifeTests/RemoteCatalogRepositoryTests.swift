import Testing
import Foundation
@testable import TimeOfLife

/// RemoteCatalogRepository mapping tests (remove-activities-layer 5.1): the
/// relay's entries carry `activity_text`, ordered `category_ids`, and
/// `notes`; the repository must map them to the local model and encode them
/// on writes. Uses `URLProtocolStub` to serve representative OpenAPI
/// responses.
@Suite("RemoteCatalogRepository DTO mapping")
struct RemoteCatalogRepositoryTests {

    private func makeClient() -> APIClient {
        APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: URLProtocolStub.makeSession(),
            accessTokenProvider: { "token" },
            refreshHandler: { "token" }
        )
    }

    private func stubJSON(_ body: String, status: Int = 200) {
        URLProtocolStub.responseHandler = { request in
            let data = body.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }

    @Test("fetchCategories decodes RFC 3339 timestamps from the relay")
    func fetchCategoriesDecodesWireDates() async throws {
        stubJSON("""
        [
          {
            "id": "cat-1",
            "name": "Sport",
            "icon": "figure.run",
            "created_at": "2026-07-20T08:00:00Z",
            "updated_at": "2026-07-27T09:00:00.123Z"
          }
        ]
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let categories = try await repository.fetchCategories()

        let category = try #require(categories.first)
        #expect(category.id == "cat-1")
        #expect(category.name == "Sport")
        #expect(category.icon == "figure.run")
        // The local model decodes Double timestamps by default; the relay
        // sends RFC 3339 strings — this failed with typeMismatch before the
        // wire DTO split and broke every non-empty category pull.
        #expect(category.createdAt.timeIntervalSince1970 > 0)
        #expect(category.updatedAt > category.createdAt)
    }

    @Test("fetchCategory decodes a single wire category")
    func fetchCategoryDecodesWireCategory() async throws {
        stubJSON("""
        {
          "id": "cat-9",
          "name": "Education",
          "icon": "book",
          "created_at": "2026-07-20T08:00:00Z",
          "updated_at": "2026-07-21T08:00:00Z"
        }
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let category = try await repository.fetchCategory(id: "cat-9")

        #expect(category.id == "cat-9")
        #expect(category.name == "Education")
    }

    @Test("fetchEntries decodes the envelope with entry-owned text, tags, and notes")
    func fetchEntriesDecodesWireDates() async throws {
        stubJSON("""
        {
          "items": [
            {
              "id": "e1",
              "activity_text": "Gym",
              "category_ids": ["cat-2", "cat-1"],
              "notes": "Leg day",
              "started_at": "2026-07-27T09:00:00Z",
              "ended_at": "2026-07-27T10:00:00Z",
              "duration_seconds": 3600,
              "source": "manual",
              "source_ref": null,
              "created_at": "2026-07-27T10:00:00Z",
              "updated_at": "2026-07-27T10:00:00Z"
            },
            {
              "id": "e2",
              "activity_text": "Reading",
              "category_ids": [],
              "notes": "",
              "started_at": "2026-07-28T09:00:00.500Z",
              "ended_at": null,
              "duration_seconds": null,
              "source": "manual",
              "source_ref": null,
              "created_at": "2026-07-28T09:00:00.500Z",
              "updated_at": "2026-07-28T09:00:00.500Z"
            }
          ]
        }
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let entries = try await repository.fetchEntries(modifiedSince: nil)

        #expect(entries.count == 2)
        let finished = try #require(entries.first)
        #expect(finished.activityText == "Gym")
        // Embedded order is preserved as the ordered local categoryIDs.
        #expect(finished.categoryIDs == ["cat-2", "cat-1"])
        #expect(finished.notes == "Leg day")
        #expect(finished.durationSeconds == 3600)
        #expect(finished.endedAt != nil)
        let running = try #require(entries.last)
        #expect(running.endedAt == nil)
        #expect(running.durationSeconds == nil)
        #expect(running.startedAt > finished.startedAt)
    }

    @Test("fetchEntry decodes a single wire entry")
    func fetchEntryDecodesWireEntry() async throws {
        stubJSON("""
        {
          "id": "e1",
          "activity_text": "Gym",
          "category_ids": ["cat-1"],
          "notes": "",
          "started_at": "2026-07-27T09:00:00Z",
          "ended_at": "2026-07-27T10:00:00Z",
          "duration_seconds": 3600,
          "source": "manual",
          "source_ref": null,
          "created_at": "2026-07-27T10:00:00Z",
          "updated_at": "2026-07-27T10:00:00Z"
        }
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let entry = try await repository.fetchEntry(id: "e1")

        #expect(entry.id == "e1")
        #expect(entry.activityText == "Gym")
        #expect(entry.categoryIDs == ["cat-1"])
        #expect(entry.durationSeconds == 3600)
    }

    /// Captures the request body, reading from the stream when URLSession
    /// moves `httpBody` there (custom URLProtocol behavior).
    private func captureBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test("createEntry encodes the entries-only payload")
    func createEntryEncodesEntriesOnlyPayload() async throws {
        var capturedBody: Data?
        URLProtocolStub.responseHandler = { request in
            capturedBody = self.captureBody(from: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(), response)
        }
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let entry = TimeEntry(
            id: "e1", activityText: "Gym",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            durationSeconds: 600,
            categoryIDs: ["cat-1", "cat-2"],
            notes: "Focused"
        )

        try await repository.createEntry(entry)

        let body = try #require(capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["activity_text"] as? String == "Gym")
        #expect(json["category_ids"] as? [String] == ["cat-1", "cat-2"])
        #expect(json["notes"] as? String == "Focused")
        #expect(json["activity_id"] == nil)
    }

    @Test("updateEntry encodes the full ordered category set and text")
    func updateEntryEncodesFullCategorySet() async throws {
        var capturedBody: Data?
        URLProtocolStub.responseHandler = { request in
            capturedBody = self.captureBody(from: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(), response)
        }
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let entry = TimeEntry(
            id: "e1", activityText: "Reading",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationSeconds: 60,
            categoryIDs: ["cat-2", "cat-1"],
            notes: "",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        try await repository.updateEntry(entry)

        let body = try #require(capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["category_ids"] as? [String] == ["cat-2", "cat-1"])
        #expect(json["activity_text"] as? String == "Reading")
    }

    @Test("fetchEntries defaults a missing source to manual (pre-provenance relays)")
    func fetchEntriesDefaultsMissingSource() async throws {
        stubJSON("""
        {
          "items": [
            {
              "id": "e1",
              "activity_text": "Gym",
              "started_at": "2026-07-27T09:00:00Z",
              "ended_at": "2026-07-27T10:00:00Z",
              "duration_seconds": 3600,
              "created_at": "2026-07-27T10:00:00Z",
              "updated_at": "2026-07-27T10:00:00Z"
            }
          ]
        }
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let entries = try await repository.fetchEntries(modifiedSince: nil)

        #expect(entries.count == 1)
        #expect(entries.first?.source == "manual")
        #expect(entries.first?.sourceRef == nil)
        // Missing optional entry-owned fields default instead of failing.
        #expect(entries.first?.categoryIDs.isEmpty == true)
        #expect(entries.first?.notes.isEmpty == true)
    }
}
