import Testing
import Foundation
@testable import TimeOfLife

/// RemoteCatalogRepository mapping tests (category-management D5): the relay
/// embeds `categories` (CategoryTag objects) in Activity responses; the
/// repository must map them to the local ordered `categoryIDs` and encode
/// `category_ids` on writes. Uses `URLProtocolStub` to serve representative
/// OpenAPI responses.
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

    @Test("fetchActivities maps embedded categories to ordered categoryIDs")
    func fetchActivitiesMapsEmbeddedCategories() async throws {
        stubJSON("""
        [
          {
            "id": "019639f1-7a3b-7abc-9def-100000000001",
            "name": "Gym",
            "notes": "",
            "last_used_at": "2026-07-27T09:00:00Z",
            "created_at": "2026-07-20T08:00:00Z",
            "updated_at": "2026-07-27T09:00:00Z",
            "categories": [
              { "id": "cat-2", "name": "Health", "icon": "heart" },
              { "id": "cat-1", "name": "Sport", "icon": "figure.run" }
            ]
          }
        ]
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let activities = try await repository.fetchActivities(modifiedSince: nil)

        #expect(activities.count == 1)
        let activity = try #require(activities.first)
        #expect(activity.name == "Gym")
        // Embedded order is preserved as the ordered local categoryIDs.
        #expect(activity.categoryIDs == ["cat-2", "cat-1"])
        #expect(activity.notes?.isEmpty == true)
    }

    @Test("fetchActivity maps a single activity with embedded categories")
    func fetchActivityMapsEmbeddedCategories() async throws {
        stubJSON("""
        {
          "id": "a1",
          "name": "Reading",
          "notes": null,
          "last_used_at": null,
          "created_at": "2026-07-20T08:00:00Z",
          "updated_at": "2026-07-21T08:00:00Z",
          "categories": [
            { "id": "cat-9", "name": "Education", "icon": "book" }
          ]
        }
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let activity = try await repository.fetchActivity(id: "a1")

        #expect(activity.id == "a1")
        #expect(activity.categoryIDs == ["cat-9"])
        #expect(activity.notes == nil)
        #expect(activity.lastUsedAt == nil)
    }

    @Test("fetchActivities handles an empty categories array")
    func fetchActivitiesEmptyCategories() async throws {
        stubJSON("""
        [
          {
            "id": "a1",
            "name": "No tags",
            "notes": null,
            "last_used_at": null,
            "created_at": "2026-07-20T08:00:00Z",
            "updated_at": "2026-07-21T08:00:00Z",
            "categories": []
          }
        ]
        """)
        defer { URLProtocolStub.clear() }
        let repository = RemoteCatalogRepository(client: makeClient())

        let activities = try await repository.fetchActivities(modifiedSince: nil)

        #expect(activities.first?.categoryIDs.isEmpty == true)
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

    @Test("createActivity encodes category_ids in the request body")
    func createActivityEncodesCategoryIDs() async throws {
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
        let activity = Activity(
            id: "a1", name: "Gym", notes: nil,
            categoryIDs: ["cat-1", "cat-2"],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        try await repository.createActivity(activity)

        let body = try #require(capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let categoryIDs = try #require(json["category_ids"] as? [String])
        #expect(categoryIDs == ["cat-1", "cat-2"])
    }

    @Test("updateActivity encodes the full ordered category set")
    func updateActivityEncodesFullCategorySet() async throws {
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
        let activity = Activity(
            id: "a1", name: "Gym", categoryIDs: ["cat-2", "cat-1"],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        try await repository.updateActivity(activity)

        let body = try #require(capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["category_ids"] as? [String] == ["cat-2", "cat-1"])
        #expect(json["name"] as? String == "Gym")
    }
}
