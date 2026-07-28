import Testing
import Foundation
@testable import TimeOfLife

@Suite("RemoteCatalogRepository")
struct RemoteCatalogRepositoryTests {

    private func makeRepo() -> (RemoteCatalogRepository, MockAPIClient) {
        let mock = MockAPIClient()
        let repo = RemoteCatalogRepository(client: mock)
        return (repo, mock)
    }

    private func makeDTO(id: UUID = UUID(), name: String = "Gym") -> ActivityDTO {
        ActivityDTO(id: id, name: name, color: .blue, icon: .figureStrengthtraining,
                    notes: nil, lastUsedAt: nil, createdAt: Date(), updatedAt: Date(),
                    categories: [])
    }

    private func bodyObject(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Activities

    @Test("listActivities calls GET /activities with auth")
    func listActivitiesEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in [self.makeDTO()] }

        let activities = try await repo.listActivities(query: nil)

        #expect(activities.count == 1)
        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/activities")
        #expect(r.requiresAuth == true)
    }

    @Test("listActivities appends the ?q= query")
    func listActivitiesQuery() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in [ActivityDTO]() }

        _ = try await repo.listActivities(query: "Gym")

        let r = try #require(mock.received.first)
        #expect(r.path == "/api/v1/activities?q=Gym")
    }

    @Test("getActivity calls GET /activities/{id}")
    func getActivityEndpoint() async throws {
        let (repo, mock) = makeRepo()
        let id = UUID()
        mock.sendHandler = { _, _ in self.makeDTO(id: id) }

        let activity = try await repo.getActivity(id)

        #expect(activity.id == id)
        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/activities/\(id.uuidString)")
        #expect(r.requiresAuth == true)
    }

    @Test("createActivity calls POST /activities with id/name/color/icon/category_ids")
    func createActivityEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in self.makeDTO() }
        let activity = TestCatalogFactory.activity(categoryIds: [UUID()])

        _ = try await repo.createActivity(activity)

        let r = try #require(mock.received.first)
        #expect(r.method == .post)
        #expect(r.path == "/api/v1/activities")
        #expect(r.requiresAuth == true)
        let body = try #require(bodyObject(r.body))
        #expect(body["id"] != nil)
        #expect(body["name"] as? String == "Gym")
        #expect(body["color"] as? String == "blue")
        #expect(body["icon"] as? String == "figure.strengthtraining")
        #expect(body["category_ids"] != nil)
    }

    @Test("updateActivity calls PATCH /activities/{id} with updated_at")
    func updateActivityEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in self.makeDTO() }
        let activity = TestCatalogFactory.activity()

        _ = try await repo.updateActivity(activity)

        let r = try #require(mock.received.first)
        #expect(r.method == .patch)
        #expect(r.path == "/api/v1/activities/\(activity.id.uuidString)")
        #expect(r.requiresAuth == true)
        let body = try #require(bodyObject(r.body))
        #expect(body["updated_at"] != nil)
        #expect(body["name"] != nil)
    }

    @Test("deleteActivity calls DELETE /activities/{id} and returns on 204")
    func deleteActivityEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let id = UUID()

        try await repo.deleteActivity(id)

        #expect(mock.sendVoidCallCount == 1)
        let r = try #require(mock.received.first)
        #expect(r.method == .delete)
        #expect(r.path == "/api/v1/activities/\(id.uuidString)")
        #expect(r.requiresAuth == true)
    }

    // MARK: - Categories

    @Test("createCategory calls POST /categories with id/name/color")
    func createCategoryEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            CategoryDTO(id: UUID(), name: "Sport", color: .green, createdAt: Date(), updatedAt: Date())
        }
        let category = TestCatalogFactory.category()

        _ = try await repo.createCategory(category)

        let r = try #require(mock.received.first)
        #expect(r.method == .post)
        #expect(r.path == "/api/v1/categories")
        #expect(r.requiresAuth == true)
        let body = try #require(bodyObject(r.body))
        #expect(body["id"] != nil)
        #expect(body["name"] as? String == "Sport")
        #expect(body["color"] as? String == "green")
    }

    @Test("updateCategory calls PATCH /categories/{id} with updated_at")
    func updateCategoryEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            CategoryDTO(id: UUID(), name: "Sport", color: .green, createdAt: Date(), updatedAt: Date())
        }
        let category = TestCatalogFactory.category()

        _ = try await repo.updateCategory(category)

        let r = try #require(mock.received.first)
        #expect(r.method == .patch)
        #expect(r.path == "/api/v1/categories/\(category.id.uuidString)")
        let body = try #require(bodyObject(r.body))
        #expect(body["updated_at"] != nil)
    }

    @Test("deleteCategory calls DELETE /categories/{id}")
    func deleteCategoryEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        let id = UUID()

        try await repo.deleteCategory(id)

        let r = try #require(mock.received.first)
        #expect(r.method == .delete)
        #expect(r.path == "/api/v1/categories/\(id.uuidString)")
    }

    // MARK: - Error mapping

    @Test("409 conflict maps to CatalogError.conflict with server updated_at")
    func conflictMapping() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "conflict", message: "stale",
                                  details: ["updated_at": "2026-07-27T09:00:00Z"])
        }
        do {
            _ = try await repo.updateActivity(TestCatalogFactory.activity())
            Issue.record("Expected conflict")
        } catch let error as CatalogError {
            #expect(error == .conflict(serverUpdatedAt: CatalogDateCoding.decode("2026-07-27T09:00:00Z")))
        }
    }

    @Test("409 activity_exists maps to CatalogError.activityExists with survivor id+name")
    func activityExistsMapping() async throws {
        let (repo, mock) = makeRepo()
        let survivorId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000002")!
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "activity_exists", message: "exists",
                                  details: ["id": survivorId.uuidString, "name": "Gym"])
        }
        do {
            _ = try await repo.createActivity(TestCatalogFactory.activity())
            Issue.record("Expected activity_exists")
        } catch let error as CatalogError {
            #expect(error == .activityExists(existingId: survivorId, existingName: "Gym"))
        }
    }

    @Test("409 category_exists maps to CatalogError.categoryExists")
    func categoryExistsMapping() async throws {
        let (repo, mock) = makeRepo()
        let survivorId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000003")!
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "category_exists", message: "exists",
                                  details: ["id": survivorId.uuidString, "name": "Sport"])
        }
        do {
            _ = try await repo.createCategory(TestCatalogFactory.category())
            Issue.record("Expected category_exists")
        } catch let error as CatalogError {
            #expect(error == .categoryExists(existingId: survivorId, existingName: "Sport"))
        }
    }

    @Test("422 validation_error maps to a field→message map")
    func validationMapping() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "validation_error", message: "bad",
                                  details: ["name": "Name must not be empty"])
        }
        do {
            _ = try await repo.createActivity(TestCatalogFactory.activity())
            Issue.record("Expected validation_error")
        } catch let error as CatalogError {
            #expect(error == .validation(fields: ["name": "Name must not be empty"]))
        }
    }

    @Test("404 not_found maps to CatalogError.notFound")
    func notFoundMapping() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "not_found", message: "missing", details: [:])
        }
        do {
            _ = try await repo.getActivity(UUID())
            Issue.record("Expected not_found")
        } catch let error as CatalogError {
            #expect(error == .notFound)
        }
    }

    @Test("offline maps to CatalogError.offline")
    func offlineMapping() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in throw APIError.offline }
        do {
            _ = try await repo.listActivities(query: nil)
            Issue.record("Expected offline")
        } catch let error as CatalogError {
            #expect(error == .offline)
        }
    }
}
