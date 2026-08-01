import Testing
import Foundation
@testable import TimeOfLife

@Suite("CatalogStore")
struct CatalogStoreTests {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CatalogStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("create persists and reads back")
    func createPersists() async throws {
        let store = CatalogStore(directory: tempDir())
        let activity = TestCatalogFactory.activity(name: "Gym")

        await store.upsertActivity(activity)
        let loaded = await store.loadActivities()

        #expect(loaded.count == 1)
        #expect(loaded.first == activity)
    }

    @Test("update replaces by id")
    func updateReplacesById() async throws {
        let store = CatalogStore(directory: tempDir())
        let id = UUID.v7()
        let original = TestCatalogFactory.activity(id: id, name: "Gym")
        await store.upsertActivity(original)

        let renamed = TestCatalogFactory.activity(id: id, name: "Lifting")
        await store.upsertActivity(renamed)

        let loaded = await store.loadActivities()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Lifting")
    }

    @Test("delete removes by id")
    func deleteRemoves() async throws {
        let store = CatalogStore(directory: tempDir())
        let activity = TestCatalogFactory.activity()
        await store.upsertActivity(activity)

        await store.removeActivity(activity.id)
        let loaded = await store.loadActivities()
        #expect(loaded.isEmpty)
        #expect(await store.activity(activity.id) == nil)
    }

    @Test("recency ordering returns most-recent first; nil last")
    func recencyOrdering() async throws {
        let store = CatalogStore(directory: tempDir())
        let older = TestCatalogFactory.activity(name: "Old", lastUsedAt: Date(timeIntervalSince1970: 100))
        let newer = TestCatalogFactory.activity(name: "New", lastUsedAt: Date(timeIntervalSince1970: 500))
        let never = TestCatalogFactory.activity(name: "Never", lastUsedAt: nil)
        await store.upsertActivity(older)
        await store.upsertActivity(newer)
        await store.upsertActivity(never)

        let ordered = await store.activitiesSortedByLastUsedAt()
        #expect(ordered.map(\.name) == ["New", "Old", "Never"])
    }

    @Test("file survives a new instance pointed at the same directory")
    func survivesRelaunch() async throws {
        let dir = tempDir()
        let store = CatalogStore(directory: dir)
        let activity = TestCatalogFactory.activity(name: "Persistent")
        await store.upsertActivity(activity)

        let reopened = CatalogStore(directory: dir)
        let loaded = await reopened.loadActivities()
        #expect(loaded.first == activity)
    }

    @Test("concurrent actor access is safe")
    func concurrentAccess() async throws {
        let store = CatalogStore(directory: tempDir())
        let ids = (0..<50).map { _ in UUID.v7() }

        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    await store.upsertActivity(TestCatalogFactory.activity(id: id))
                }
            }
        }

        let loaded = await store.loadActivities()
        #expect(loaded.count == 50)
    }

    @Test("case-insensitive, trimmed name lookup")
    func nameLookup() async throws {
        let store = CatalogStore(directory: tempDir())
        await store.upsertActivity(TestCatalogFactory.activity(name: "Gym"))

        #expect(await store.activity(named: "  gym ") != nil)
        #expect(await store.activity(named: "GYM") != nil)
        #expect(await store.activity(named: "Read") == nil)
    }

    @Test("removing a category drops the tag from all activities")
    func categoryCascade() async throws {
        let store = CatalogStore(directory: tempDir())
        let catId = UUID.v7()
        await store.upsertCategory(TestCatalogFactory.category(id: catId))
        await store.upsertActivity(TestCatalogFactory.activity(name: "A", categoryIds: [catId]))
        await store.upsertActivity(TestCatalogFactory.activity(name: "B", categoryIds: [catId]))

        await store.removeCategory(catId)
        let activities = await store.loadActivities()
        #expect(activities.allSatisfy { $0.categoryIds.isEmpty })
        #expect(await store.category(catId) == nil)
    }

    @Test("replaceCategoryReferences rewrites activity tags to the surviving id")
    func replaceCategoryReferences() async throws {
        let store = CatalogStore(directory: tempDir())
        let oldId = UUID.v7()
        let newId = UUID.v7()
        await store.upsertActivity(TestCatalogFactory.activity(name: "A", categoryIds: [oldId]))

        await store.replaceCategoryReferences(from: oldId, to: newId)
        let activity = await store.activity(named: "a")
        #expect(activity?.categoryIds == [newId])
    }
}
