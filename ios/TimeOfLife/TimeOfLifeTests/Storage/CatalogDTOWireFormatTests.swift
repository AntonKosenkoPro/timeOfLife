import Testing
import Foundation
@testable import TimeOfLife

/// Network DTO date contract tests (AC2/AC3/AC5).
///
/// The backend emits RFC 3339 timestamps as strings (`RFC3339Nano`, which
/// omits the fractional part when sub-second is zero) and accepts the same
/// on input. These tests pin the client's wire format so a decode/encode
/// regression cannot ship green again (Phase 3 review finding P1/P2).
@Suite("Catalog DTO wire format")
struct CatalogDTOWireFormatTests {

    // MARK: - Decoding (inbound)

    @Test("Decoder accepts RFC 3339 with fractional seconds")
    func decodesFractionalSeconds() throws {
        let json = #"""
        {"id":"c1","name":"Work","icon":"briefcase",
         "created_at":"2026-07-27T09:00:00.123Z","updated_at":"2026-07-27T10:00:00.456Z"}
        """#
        let dto = try JSONDecoder.catalogDecoder.decode(CategoryDTO.self, from: Data(json.utf8))
        #expect(dto.id == "c1")
        let expected = CatalogDateCoding.decode("2026-07-27T09:00:00.123Z")
        #expect(dto.createdAt == expected)
    }

    @Test("Decoder accepts whole-second RFC 3339 (no fraction)")
    func decodesWholeSeconds() throws {
        let json = #"""
        {"id":"c1","name":"Work","icon":"briefcase",
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T10:00:00Z"}
        """#
        let dto = try JSONDecoder.catalogDecoder.decode(CategoryDTO.self, from: Data(json.utf8))
        #expect(dto.id == "c1")
        let expected = CatalogDateCoding.decode("2026-07-27T09:00:00Z")
        #expect(dto.createdAt == expected)
    }

    @Test("Decoder accepts non-Zulu offset (SQLite test backend)")
    func decodesNonZuluOffset() throws {
        let json = #"""
        {"id":"c1","name":"Work","icon":"briefcase",
         "created_at":"2026-07-27T09:00:00+00:00","updated_at":"2026-07-27T10:00:00+00:00"}
        """#
        let dto = try JSONDecoder.catalogDecoder.decode(CategoryDTO.self, from: Data(json.utf8))
        #expect(dto.id == "c1")
        let expected = CatalogDateCoding.decode("2026-07-27T09:00:00Z")
        #expect(dto.createdAt == expected)
    }

    @Test("Entry list response decodes with fractional timestamps and cursor")
    func decodesEntryList() throws {
        let json = #"""
        {"items":[
          {"id":"e1","activity_id":"a1","activity_name":"Reading",
           "started_at":"2026-07-27T09:00:00.500Z","ended_at":"2026-07-27T09:30:00Z",
           "duration_seconds":1800.0,
           "created_at":"2026-07-27T09:00:00.123Z","updated_at":"2026-07-27T09:30:00Z",
           "categories":[]}
        ],"next_cursor":"abc"}
        """#
        let dto = try JSONDecoder.catalogDecoder.decode(
            EntryListResponseDTO.self, from: Data(json.utf8))
        #expect(dto.items.count == 1)
        #expect(dto.nextCursor == "abc")
        #expect(dto.items.first?.endedAt != nil)
    }

    // MARK: - Encoding (outbound)

    @Test("Encoder emits RFC 3339 strings, not JSON numbers")
    func encodesAsRFC3339Strings() throws {
        let date = CatalogDateCoding.decode("2026-07-27T09:00:00.123Z")!
        let request = EntryCreateRequest(
            id: "e1", activityId: "a1", startedAt: date, endedAt: nil)
        let data = try JSONEncoder.catalogEncoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"started_at\":"))
        #expect(!json.contains("\"started_at\":1"))
        // RFC 3339 string with fractional seconds.
        #expect(json.contains("2026-07-27T09:00:00.123Z"))
    }

    @Test("APIEndpoint encodes bodies with the catalog date strategy")
    func endpointUsesCatalogEncoder() throws {
        let date = CatalogDateCoding.decode("2026-07-27T09:00:00.123Z")!
        let request = EntryCreateRequest(
            id: "e1", activityId: "a1", startedAt: date, endedAt: nil)
        let endpoint = APIEndpoint(
            method: .post, path: "/api/v1/entries", body: request, requiresAuth: true)
        let body = try #require(endpoint.body)
        let json = String(data: body, encoding: .utf8) ?? ""
        #expect(json.contains("\"started_at\":\"2026-07-27T09:00:00.123Z\""))
    }

    @Test("Default API client decoder/encoder use the catalog strategies")
    func defaultClientCoding() throws {
        let decoder = APIClient.defaultDecoder()
        let json = #"""
        {"id":"c1","name":"Work","icon":"briefcase",
         "created_at":"2026-07-27T09:00:00Z","updated_at":"2026-07-27T10:00:00Z"}
        """#
        let dto = try decoder.decode(CategoryDTO.self, from: Data(json.utf8))
        #expect(dto.id == "c1")
    }
}
