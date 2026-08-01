import Testing
import Foundation
@testable import TimeOfLife

@Suite("CatalogModels")
struct CatalogModelsTests {

    // MARK: - Palette + icons

    @Test("ActivityColor has the 12 palette keys")
    func paletteCount() {
        #expect(ActivityColor.allCases.count == 12)
        let keys = Set(ActivityColor.allCases.map(\.rawValue))
        let expected = [
            "gray", "red", "orange", "yellow", "green", "teal", "blue",
            "indigo", "purple", "pink", "brown", "mint"
        ]
        for key in expected {
            #expect(keys.contains(key), "Missing color key \(key)")
        }
    }

    @Test("ActivityIcon is the union of backend + TOKENS; default is clock")
    func iconSet() {
        // Union = 13 shared + 15 TOKENS-only + 18 backend-only = 46.
        #expect(ActivityIcon.allCases.count == 46)
        #expect(ActivityIcon.default == .clock)
        let keys = ActivityIcon.validKeys
        // TOKENS-only
        #expect(keys.contains("clock"))
        #expect(keys.contains("brain.head.profile"))
        #expect(keys.contains("moon.stars"))
        // Backend-only
        #expect(keys.contains("figure.walk"))
        #expect(keys.contains("musicalnotes"))
        #expect(keys.contains("moon.zzz"))
        // Shared
        #expect(keys.contains("figure.run"))
        #expect(keys.contains("fork.knife"))
    }

    @Test("Activity color/icon enums decode from raw strings")
    func rawDecoding() throws {
        let color = try JSONDecoder().decode(ActivityColor.self, from: Data("\"blue\"".utf8))
        #expect(color == .blue)
        let icon = try JSONDecoder().decode(ActivityIcon.self, from: Data("\"figure.run\"".utf8))
        #expect(icon == .figureRun)
    }

    // MARK: - Activity Codable (snake_case)

    @Test("Activity encodes with snake_case keys")
    func activityEncodesSnakeCase() throws {
        let activity = TestCatalogFactory.activity(
            lastUsedAt: Date(timeIntervalSince1970: 1_000),
            categoryIds: [UUID()]
        )
        let data = try JSONEncoder().encode(activity)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["last_used_at"] != nil)
        #expect(object["category_ids"] != nil)
        #expect(object["created_at"] != nil)
        #expect(object["updated_at"] != nil)
        #expect(object["lastUsedAt"] == nil)
        #expect(object["categoryIds"] == nil)
    }

    @Test("Activity round-trips Codable")
    func activityRoundTrip() throws {
        let activity = TestCatalogFactory.activity(notes: "x", categoryIds: [UUID(), UUID()])
        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(Activity.self, from: data)
        #expect(decoded == activity)
    }

    @Test("Category round-trips Codable")
    func categoryRoundTrip() throws {
        let category = TestCatalogFactory.category(name: "Work", color: .orange)
        let data = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(Category.self, from: data)
        #expect(decoded == category)
    }

    // MARK: - DTO decoding (network shapes)

    @Test("ActivityDTO decodes from backend resource shape and maps toActivity")
    func activityDTODecodes() throws {
        let categoryId = "019639f1-7a3b-7abc-9def-100000000002"
        let json = """
        {
          "id": "019639f1-7a3b-7abc-9def-100000000001",
          "name": "Gym",
          "color": "blue",
          "icon": "figure.strengthtraining",
          "notes": "",
          "last_used_at": "2026-07-27T09:00:00Z",
          "created_at": "2026-07-27T08:00:00Z",
          "updated_at": "2026-07-27T09:00:00Z",
          "categories": [
            { "id": "\(categoryId)", "name": "Sport", "color": "green",
              "created_at": "2026-07-27T08:00:00Z", "updated_at": "2026-07-27T08:00:00Z" }
          ]
        }
        """
        let dto = try JSONDecoder().decode(ActivityDTO.self, from: Data(json.utf8))
        let activity = dto.toActivity()
        #expect(activity.id.uuidString.lowercased() == "019639f1-7a3b-7abc-9def-100000000001")
        #expect(activity.color == .blue)
        #expect(activity.icon == .figureStrengthtraining)
        #expect(activity.categoryIds.map { $0.uuidString.lowercased() } == [categoryId])
        #expect(activity.lastUsedAt == CatalogDateCoding.decode("2026-07-27T09:00:00Z"))
    }

    @Test("ActivityDTO tolerates fractional-second timestamps and missing categories")
    func activityDTOFractionalAndMissingCategories() throws {
        let json = """
        {
          "id": "019639f1-7a3b-7abc-9def-100000000010",
          "name": "Read", "color": "indigo", "icon": "book",
          "notes": null, "last_used_at": "2026-07-27T09:00:00.123Z",
          "created_at": "2026-07-27T08:00:00Z", "updated_at": "2026-07-27T08:00:00Z"
        }
        """
        let dto = try JSONDecoder().decode(ActivityDTO.self, from: Data(json.utf8))
        #expect(dto.lastUsedAt != nil)
        #expect(dto.categories.isEmpty)
        #expect(dto.toActivity().notes == nil)
    }

    @Test("CategoryDTO decodes and maps toCategory")
    func categoryDTODecodes() throws {
        let json = """
        { "id": "019639f1-7a3b-7abc-9def-100000000020", "name": "Sport", "color": "green",
          "created_at": "2026-07-27T08:00:00Z", "updated_at": "2026-07-27T08:00:00Z" }
        """
        let dto = try JSONDecoder().decode(CategoryDTO.self, from: Data(json.utf8))
        let category = dto.toCategory()
        #expect(category.color == .green)
        #expect(category.name == "Sport")
    }

    @Test("ActivityPatchRequest encodes updated_at as an ISO string")
    func patchEncodesUpdatedAt() throws {
        let date = Date(timeIntervalSince1970: 1_785_626_400)
        let body = ActivityPatchRequest(name: "Gym", color: nil, icon: nil, notes: nil, categoryIds: nil, updatedAt: date)
        let data = try JSONEncoder().encode(body)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updated = try #require(object["updated_at"] as? String)
        #expect(CatalogDateCoding.decode(updated) != nil)
        // Omitted optionals must not be present.
        #expect(object["name"] != nil)
        #expect(object["color"] == nil)
        #expect(object["icon"] == nil)
        #expect(object["notes"] == nil)
        #expect(object["category_ids"] == nil)
    }

    @Test("ActivityCreateRequest encodes category_ids")
    func createEncodesCategoryIds() throws {
        let id = UUID()
        let body = ActivityCreateRequest(id: UUID(), name: "Gym", color: .blue, icon: .figureStrengthtraining, notes: nil, categoryIds: [id])
        let data = try JSONEncoder().encode(body)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["category_ids"] != nil)
        #expect(object["id"] != nil)
    }

    // MARK: - Validator

    @Test("name validation: empty and too-long")
    func nameValidation() {
        #expect(CatalogValidator.validateName("") == [.nameEmpty])
        #expect(CatalogValidator.validateName("   ") == [.nameEmpty])
        #expect(CatalogValidator.validateName("Gym").isEmpty)
        #expect(CatalogValidator.validateName(String(repeating: "a", count: 61)).contains(.nameTooLong))
        #expect(CatalogValidator.validateName(String(repeating: "a", count: 60)).isEmpty)
    }

    @Test("notes validation: ≤280 only (empty allowed)")
    func notesValidation() {
        #expect(CatalogValidator.validateNotes("").isEmpty)
        #expect(CatalogValidator.validateNotes(String(repeating: "a", count: 280)).isEmpty)
        #expect(CatalogValidator.validateNotes(String(repeating: "a", count: 281)) == [.notesTooLong])
    }

    @Test("color + icon validation against the allowed sets")
    func colorIconValidation() {
        #expect(CatalogValidator.validateColor("blue").isEmpty)
        #expect(CatalogValidator.validateColor("notacolor") == [.colorInvalid])
        #expect(CatalogValidator.validateIcon("clock").isEmpty)
        #expect(CatalogValidator.validateIcon("figure.run").isEmpty)
        #expect(CatalogValidator.validateIcon("notasymbol") == [.iconInvalid])
    }

    @Test("normalizeName trims and lowercases for reuse (F4)")
    func normalizeName() {
        #expect(CatalogValidator.normalizeName("  Gym ") == "gym")
        #expect(CatalogValidator.normalizeName("GYM") == "gym")
        #expect(CatalogValidator.normalizeName("\tRead\n") == "read")
    }

    @Test("unified messages return a single message per field or nil")
    func unifiedMessages() {
        #expect(CatalogValidator.unifiedNameMessage([]) == nil)
        #expect(CatalogValidator.unifiedNameMessage([.nameEmpty]) != nil)
        #expect(CatalogValidator.unifiedNameMessage([.nameTooLong]) != nil)
        #expect(CatalogValidator.unifiedNotesMessage([.notesTooLong]) != nil)
        #expect(CatalogValidator.unifiedColorMessage([.colorInvalid]) != nil)
        #expect(CatalogValidator.unifiedIconMessage([.iconInvalid]) != nil)
    }
}
