// Provider endpoint: backend/api/openapi.yaml (v1.1.0) — verify seven scrutiny
// points (shape, status codes, field names, enums, required fields, data types,
// nested structures) against the OpenAPI spec before activation.
//
// RED-phase scaffold (1.1-API-001): serialization-contract gaps not covered by
// RemoteCatalogRepositoryTests. Every test is .disabled() so the suite stays
// green — activate them one by one after verifying against the OpenAPI spec.
import Testing
import Foundation
@testable import TimeOfLife

@Suite("RemoteCatalogRepositoryContract")
struct RemoteCatalogRepositoryContractScaffoldTests {

    private func makeRepo() -> (RemoteCatalogRepository, MockAPIClient) {
        let mock = MockAPIClient()
        let repo = RemoteCatalogRepository(client: mock)
        return (repo, mock)
    }

    private func makeDTO(
        id: UUID = UUID(),
        name: String = "Gym",
        notes: String? = nil,
        lastUsedAt: Date? = nil,
        categories: [CategoryDTO] = []
    ) -> ActivityDTO {
        ActivityDTO(id: id, name: name, notes: notes, lastUsedAt: lastUsedAt, createdAt: Date(),
                    updatedAt: Date(), categories: categories)
    }

    private func makeCategoryDTO(id: UUID, name: String = "Fitness") -> CategoryDTO {
        CategoryDTO(id: id, name: name, icon: .tag, createdAt: Date(), updatedAt: Date())
    }

    private func bodyObject(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func decodeActivityJSON(_ json: String) throws -> ActivityDTO {
        try JSONDecoder().decode(ActivityDTO.self, from: Data(json.utf8))
    }

    private func decodeActivitiesJSON(_ json: String) throws -> [ActivityDTO] {
        try JSONDecoder().decode([ActivityDTO].self, from: Data(json.utf8))
    }

    // MARK: - P1: nested categories[] resolution (GET)

    // RED: activate when this contract gap is verified
    @Test("GET /activities decodes resolved categories[] into categoryIds", .disabled())
    func listActivitiesResolvesCategories() async throws {
        let (repo, mock) = makeRepo()
        let catId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000001")!
        let raw = """
        [{"id":"019639f1-7a3b-7abc-9def-100000000002","name":"Gym",
          "created_at":"2026-07-27T09:00:00Z",
          "updated_at":"2026-07-27T09:00:00Z",
          "categories":[{"id":"\(catId.uuidString)","name":"Fitness","icon":"tag",
                         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}]}]
        """
        let dtos = try decodeActivitiesJSON(raw)
        #expect(dtos.first?.categories.count == 1)

        mock.sendHandler = { _, _ in dtos }
        let activities = try await repo.listActivities(query: nil)
        let activity = try #require(activities.first)
        #expect(activity.categoryIds == [catId])
        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/activities")
        #expect(r.requiresAuth == true)
    }

    // RED: activate when this contract gap is verified
    @Test("GET /activities/{id} decodes resolved categories[] into categoryIds", .disabled())
    func getActivityResolvesCategories() async throws {
        let (repo, mock) = makeRepo()
        let activityId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000002")!
        let catId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000001")!
        let raw = """
        {"id":"\(activityId.uuidString)","name":"Gym","created_at":"2026-07-27T09:00:00Z",
         "updated_at":"2026-07-27T09:00:00Z",
         "categories":[{"id":"\(catId.uuidString)","name":"Fitness","icon":"tag",
                        "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}]}
        """
        let dto = try decodeActivityJSON(raw)
        mock.sendHandler = { _, _ in dto }

        let activity = try await repo.getActivity(activityId)

        #expect(activity.categoryIds == [catId])
        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/activities/\(activityId.uuidString)")
    }

    // MARK: - P1: PATCH body serialization

    // RED: activate when this contract gap is verified
    @Test("PATCH body omits nil notes and empty category_ids keys", .disabled())
    func patchOmitsNilOptionals() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in self.makeDTO() }
        let activity = TestCatalogFactory.activity(notes: nil, categoryIds: [])

        _ = try await repo.updateActivity(activity)

        let r = try #require(mock.received.first)
        #expect(r.method == .patch)
        let body = try #require(bodyObject(r.body))
        #expect(body["notes"] == nil)
        #expect(body["category_ids"] == nil)
        #expect(body["updated_at"] != nil)
    }

    // RED: activate when this contract gap is verified
    @Test("PATCH body includes category_ids only when non-empty", .disabled())
    func patchIncludesCategoryIdsWhenNonEmpty() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in self.makeDTO() }
        let catId = UUID(uuidString: "019639f1-7a3b-7abc-9def-100000000001")!
        let activity = TestCatalogFactory.activity(categoryIds: [catId])

        _ = try await repo.updateActivity(activity)

        let r = try #require(mock.received.first)
        #expect(r.method == .patch)
        let body = try #require(bodyObject(r.body))
        #expect(body["category_ids"] != nil)
        #expect(body["category_ids"] as? [String] == [catId.uuidString])
    }

    // MARK: - P1: notes empty-string vs nil round-trip

    // RED: activate when this contract gap is verified
    @Test("notes empty string vs omitted decodes distinctly", .disabled())
    func notesEmptyVsNilRoundTrip() throws {
        let withEmpty = try decodeActivityJSON("""
        {"id":"019639f1-7a3b-7abc-9def-100000000002","name":"Gym","notes":"",
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}
        """)
        #expect(withEmpty.notes?.isEmpty == true)
        #expect(withEmpty.toActivity().notes?.isEmpty == true)

        let omitted = try decodeActivityJSON("""
        {"id":"019639f1-7a3b-7abc-9def-100000000002","name":"Gym",
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}
        """)
        #expect(omitted.notes == nil)
        #expect(omitted.toActivity().notes == nil)
    }

    // MARK: - P2: date coding

    // RED: activate when this contract gap is verified
    @Test("RFC 3339 dates parse via CatalogDateCoding; nil last_used_at stays nil", .disabled())
    func dateRoundTrip() throws {
        let parsed = try #require(CatalogDateCoding.decode("2026-07-27T09:00:00Z"))
        #expect(CatalogDateCoding.encode(parsed).hasPrefix("2026-07-27T09:00:00"))

        let nilLastUsed = try decodeActivityJSON("""
        {"id":"019639f1-7a3b-7abc-9def-100000000002","name":"Gym","last_used_at":null,
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}
        """)
        #expect(nilLastUsed.lastUsedAt == nil)
        #expect(nilLastUsed.toActivity().lastUsedAt == nil)

        let withLastUsed = try decodeActivityJSON("""
        {"id":"019639f1-7a3b-7abc-9def-100000000002","name":"Gym","last_used_at":"2026-07-27T09:00:00Z",
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T09:00:00Z"}
        """)
        #expect(withLastUsed.lastUsedAt != nil)
        #expect(withLastUsed.toActivity().lastUsedAt == withLastUsed.lastUsedAt)
    }

    // MARK: - P2: no query-param drift on categories

    // RED: activate when this contract gap is verified
    @Test("GET /categories path has no query parameter drift", .disabled())
    func listCategoriesHasNoQuerySupport() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in [CategoryDTO]() }

        let categories = try await repo.listCategories()

        #expect(categories.isEmpty)
        let r = try #require(mock.received.first)
        #expect(r.method == .get)
        #expect(r.path == "/api/v1/categories")
        #expect(!r.path.contains("?"))
    }

    // MARK: - P2: create body serialization

    // RED: activate when this contract gap is verified
    @Test("createActivity sends notes key only when non-nil", .disabled())
    func createIncludesNotesOnlyWhenNonNil() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in self.makeDTO() }

        _ = try await repo.createActivity(TestCatalogFactory.activity(notes: "Morning routine"))
        _ = try await repo.createActivity(TestCatalogFactory.activity(notes: nil))

        let withNotes = try #require(bodyObject(mock.received[0].body))
        #expect(withNotes["notes"] as? String == "Morning routine")
        let withoutNotes = try #require(bodyObject(mock.received[1].body))
        #expect(withoutNotes["notes"] == nil)
    }
}
