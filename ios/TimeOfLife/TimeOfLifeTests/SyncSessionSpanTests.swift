import Foundation
import Testing
@testable import TimeOfLife

@Suite("SyncSessionSpan")
struct SyncSessionSpanTests {
    @Test("builder maps outcome, counts, and depths")
    func builderMapsFields() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1.5)
        let span = SyncSessionSpan.build(
            start: start,
            end: end,
            outcome: .success,
            counts: SyncSessionSpanCounts(pushed: 3, pulled: 12, conflicts: 1, depthBefore: 4, depthAfter: 1)
        )
        #expect(span.name == "sync.session")
        #expect(span.outcome == .success)
        #expect(span.pushedCount == 3)
        #expect(span.pulledCount == 12)
        #expect(span.conflictCount == 1)
        #expect(span.outboxDepthBefore == 4)
        #expect(span.outboxDepthAfter == 1)
        #expect(span.wallDurationMs == 1_500)
        #expect(span.offlineDurationMs == 0)
        #expect(span.endNanos >= span.startNanos)
        let offline = SyncSessionSpan.build(
            start: start, end: end, outcome: .offline,
            counts: SyncSessionSpanCounts(offlineDurationMs: 9_000)
        )
        #expect(offline.offlineDurationMs == 9_000)
    }

    @Test("ids are hex, fixed length, and unique per span")
    func idsAreHexAndUnique() {
        let first = SyncSessionSpan.build(
            start: Date(), end: Date(), outcome: .success,
            counts: SyncSessionSpanCounts()
        )
        let second = SyncSessionSpan.build(
            start: Date(), end: Date(), outcome: .failed,
            counts: SyncSessionSpanCounts()
        )
        #expect(first.traceID.count == 32)
        #expect(first.spanID.count == 16)
        #expect(first.traceID != second.traceID)
        #expect(first.spanID != second.spanID)
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(first.traceID.unicodeScalars.allSatisfy { hex.contains($0) })
        #expect(first.spanID.unicodeScalars.allSatisfy { hex.contains($0) })
    }

    @Test("encoded span carries no identifiers or user content")
    func encodedSpanHasNoPII() throws {
        let span = SyncSessionSpan.build(
            start: Date(), end: Date(), outcome: .offline,
            counts: SyncSessionSpanCounts(offlineDurationMs: 9_000, depthBefore: 2, depthAfter: 2)
        )
        let data = try JSONEncoder().encode(span)
        let json = String(data: data, encoding: .utf8) ?? ""
        for forbidden in ["user_id", "email", "token", "activity_text", "category"] {
            #expect(!json.contains(forbidden))
        }
        // Exact key allowlist: substring checks go blind the moment a new
        // field serializes camelCase (JSONEncoder uses default keys).
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "traceID", "spanID", "name", "startNanos", "endNanos", "outcome",
            "wallDurationMs", "offlineDurationMs", "pushedCount", "pulledCount",
            "conflictCount", "outboxDepthBefore", "outboxDepthAfter",
        ])
    }
}
