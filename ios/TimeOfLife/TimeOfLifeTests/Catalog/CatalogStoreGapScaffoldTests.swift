// RED-PHASE ATDD scaffold — disabled until the behavior is verified/implemented. Activate by removing .disabled() during the green phase.
import Testing
import Foundation
@testable import TimeOfLife

@Suite("CatalogStoreGapScaffold")
struct CatalogStoreGapScaffoldTests {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CatalogStoreGapScaffoldTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Category persistence (1.1-UNIT-002)

    @Test("category CRUD survives store recreation", .disabled())
    func categoryCrudSurvivesRecreation() async throws {
        // RED: the activity CRUD + relaunch paths are covered; category create/update/remove across a recreated store instance is uncovered.
        let dir = tempDir()
        let store = CatalogStore(directory: dir)
        let category = TestCatalogFactory.category(name: "Sport")
        await store.upsertCategory(category)

        let reopened = CatalogStore(directory: dir)
        #expect(await reopened.category(category.id) == category)

        let renamed = TestCatalogFactory.category(id: category.id, name: "Gym")
        await reopened.upsertCategory(renamed)
        #expect(await CatalogStore(directory: dir).category(category.id)?.name == "Gym")

        await reopened.removeCategory(category.id)
        #expect(await reopened.category(category.id) == nil)
        #expect(await reopened.loadCategories().isEmpty)
    }

    // MARK: - Corruption (1.1-UNIT-007)

    @Test("corrupt catalog JSON is quarantined, not silently read as empty", .disabled())
    func corruptActivitiesFileIsQuarantined() async throws {
        // RED: CatalogStore.loadActivities returns [] on decode failure (CatalogStore.swift:52-56). Recovery behavior must be defined (R-009). This scaffold encodes the desired contract — quarantine or explicit corruption signal, NOT silent empty.
        let dir = tempDir()
        let store = CatalogStore(directory: dir)
        await store.upsertActivity(TestCatalogFactory.activity(name: "Gym"))
        let activitiesURL = dir.appendingPathComponent("catalog_activities.json")
        try Data("not-json-garbage".utf8).write(to: activitiesURL)

        let reopened = CatalogStore(directory: dir)
        _ = await reopened.loadActivities()

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("catalog_activities.corrupted.") && $0.hasSuffix(".json") })
        #expect(!FileManager.default.fileExists(atPath: activitiesURL.path))
    }

    // MARK: - Recency ordering (CatalogStore.swift:60-69)

    @Test("recency tie-break: equal lastUsedAt sorts by name", .disabled())
    func recencyTieBreakByName() async throws {
        // RED: for equal non-nil lastUsedAt the comparator returns l > r (false) and relies on unstable sort order; only the nil-vs-nil default branch sorts by name. Contract: deterministic name ordering on both tie branches.
        let store = CatalogStore(directory: tempDir())
        let zed = TestCatalogFactory.activity(name: "Zed", lastUsedAt: Date(timeIntervalSince1970: 100))
        let alpha = TestCatalogFactory.activity(name: "Alpha", lastUsedAt: Date(timeIntervalSince1970: 100))
        let neverZed = TestCatalogFactory.activity(name: "NeverZed", lastUsedAt: nil)
        let neverAlpha = TestCatalogFactory.activity(name: "NeverAlpha", lastUsedAt: nil)
        // Insert in reverse-name order so a sort that merely preserves insertion order cannot satisfy the contract by luck.
        await store.upsertActivity(zed)
        await store.upsertActivity(alpha)
        await store.upsertActivity(neverZed)
        await store.upsertActivity(neverAlpha)

        let ordered = await store.activitiesSortedByLastUsedAt()
        #expect(ordered.map(\.name) == ["Alpha", "Zed", "NeverAlpha", "NeverZed"])
    }
}
