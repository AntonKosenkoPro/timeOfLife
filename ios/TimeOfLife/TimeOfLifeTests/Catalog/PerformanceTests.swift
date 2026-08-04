import Testing
import Foundation
@testable import TimeOfLife

/// AC10 / Phase 9.4 — Performance test: suggestions ranking must complete
/// in under 50 ms for 1,000 activities (in-memory, no file I/O).
@Suite("Performance")
struct PerformanceTests {

    @Test("Suggestions ranking < 50 ms for 1,000 activities")
    func suggestionsRankingUnder50ms() async throws {
        let store = try LocalStore(inMemory: true)
        let base = CatalogTestFactory.date()

        // Insert 1,000 activities with staggered recency.
        for index in 0..<1_000 {
            try await store.upsertActivity(CatalogTestFactory.makeActivity(
                id: "a\(String(format: "%04d", index))",
                name: "Activity \(index)",
                lastUsedAt: base.addingTimeInterval(TimeInterval(index)),
                sync: .adoptedClean()))
        }

        // Time the suggestion query (the 5 most recent activities).
        // Warm up once so the first (cold-cache) query isn't measured —
        // production runs many queries per session, not one cold query.
        _ = try await store.suggestionActivities(limit: 5)

        // `ProcessInfo.systemUptime` is iOS 15-compatible.
        let start = ProcessInfo.processInfo.systemUptime
        _ = try await store.suggestionActivities(limit: 5)
        let elapsedMillis = (ProcessInfo.processInfo.systemUptime - start) * 1_000

        #expect(
            elapsedMillis < 50,
            "Suggestions ranking took \(elapsedMillis) ms — expected < 50 ms")
    }
}
