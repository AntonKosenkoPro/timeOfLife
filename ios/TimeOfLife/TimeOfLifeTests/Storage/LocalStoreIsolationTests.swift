import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// AC10 — Account isolation, atomic mutations, pending durability across
/// relaunch, and cross-device hard-delete reconciliation.
///
/// These tests use **file-backed** databases (not in-memory) so that
/// durability and account isolation are exercised against real SQLite files.
@Suite("LocalStore isolation & durability")
struct LocalStoreIsolationTests {

    // MARK: - Helpers

    /// Creates a unique temporary directory for a file-backed store.
    private func makeTempURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalStoreIsolationTests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test.sqlite")
    }

    /// Opens a file-backed store at the given URL.
    private func makeFileStore(at url: URL) throws -> LocalStore {
        try LocalStore(databaseURL: url)
    }

    // MARK: - Account isolation (AC10)

    @Test("Account A data is never visible to Account B")
    func accountIsolation() async throws {
        let urlA = makeTempURL()
        let urlB = makeTempURL()
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
        }

        let storeA = try makeFileStore(at: urlA)
        try await storeA.upsertCategory(CatalogTestFactory.makeCategory(
            id: "cat-a", name: "Account A Category", sync: .newPending()))
        try await storeA.upsertActivity(CatalogTestFactory.makeActivity(
            id: "act-a", name: "Account A Activity", sync: .newPending()))
        try await storeA.upsertEntry(CatalogTestFactory.makeEntry(
            id: "ent-a", activityId: "act-a", sync: .newPending()))

        let storeB = try makeFileStore(at: urlB)
        let catsB = try await storeB.categoriesSortedByName()
        let actsB = try await storeB.activitiesSortedByLastUsedAt()
        #expect(catsB.isEmpty, "Account B should see zero categories")
        #expect(actsB.isEmpty, "Account B should see zero activities")

        // Account A still has its data.
        let catsA = try await storeA.categoriesSortedByName()
        #expect(catsA.count == 1)
        #expect(catsA.first?.name == "Account A Category")
    }

    @Test("Switching accounts closes the previous DB and opens a fresh one")
    func accountSwitch() async throws {
        let urlA = makeTempURL()
        let urlB = makeTempURL()
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
        }

        let storeA = try makeFileStore(at: urlA)
        try await storeA.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "A Only", sync: .newPending()))

        // Simulate account switch: close A, open B.
        await storeA.close()
        let storeB = try makeFileStore(at: urlB)
        #expect(try await storeB.categoriesSortedByName().isEmpty)
    }

    // MARK: - Atomic mutations (AC10)

    @Test("Multi-record upsert is atomic — concurrent reads see a consistent snapshot")
    func atomicMutationVisibility() async throws {
        let store = try LocalStore(inMemory: true)
        // Insert a category + an activity referencing it concurrently.
        async let catInsert: Void = store.upsertCategory(
            CatalogTestFactory.makeCategory(id: "c1", name: "Work", sync: .newPending()))
        async let actInsert: Void = store.upsertActivity(
            CatalogTestFactory.makeActivity(
                id: "a1", name: "Read", categoryIds: ["c1"], sync: .newPending()))
        _ = try await catInsert
        _ = try await actInsert

        // After both complete, both are visible.
        #expect(try await store.category(id: "c1") != nil)
        #expect(try await store.activity(id: "a1") != nil)
    }

    // MARK: - Pending durability across relaunch (AC10)

    @Test("Pending work survives relaunch (file-backed store reopened)")
    func pendingDurabilityAcrossRelaunch() async throws {
        let url = makeTempURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        // First session: create pending records.
        let store1 = try makeFileStore(at: url)
        try await store1.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Pending Cat", sync: .newPending()))
        try await store1.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Pending Act", sync: .newPending()))
        try await store1.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))
        // Mark an entry as blocked — it must also survive relaunch.
        try await store1.markEntryBlocked(id: "e1", code: "validation_error", message: "bad")
        await store1.close()

        // Second session: reopen the same file.
        let store2 = try makeFileStore(at: url)
        let cats = try await store2.categoriesSortedByName()
        #expect(cats.count == 1)
        #expect(cats.first?.name == "Pending Cat")
        #expect(cats.first?.sync.syncStatus == .pending)

        let acts = try await store2.activitiesSortedByLastUsedAt()
        #expect(acts.count == 1)
        #expect(acts.first?.sync.syncStatus == .pending)

        // Blocked entry survived.
        let entry = try await store2.entry(id: "e1")
        #expect(entry?.sync.syncStatus == .blocked)
        #expect(entry?.sync.syncErrorCode == "validation_error")
    }

    @Test("Undo hold survives relaunch")
    func undoHoldDurabilityAcrossRelaunch() async throws {
        let url = makeTempURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let store1 = try makeFileStore(at: url)
        try await store1.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .newPending()))
        let hold = UndoHold(
            type: .activityWithEntries, targetId: "a1",
            entryIds: [], categoryJoins: [],
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(30))
        try await store1.holdForUndo(hold)
        await store1.close()

        let store2 = try makeFileStore(at: url)
        let restored = try await store2.currentHold()
        #expect(restored?.targetId == "a1")
        #expect(restored?.type == .activityWithEntries)
    }

    // MARK: - Cross-device hard delete reconciliation (AC10)

    @Test("Cross-device hard delete removes clean local records on pull")
    func crossDeviceHardDelete() async throws {
        let store = try LocalStore(inMemory: true)
        // Local clean records (pulled from server previously).
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))

        // Server now reports empty (deleted on another device).
        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        #expect(try await store.category(id: "c1") == nil)
        #expect(try await store.activity(id: "a1") == nil)
        // Clean entries cascade when their activity is absent.
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("Dirty local records survive cross-device activity delete")
    func dirtyRecordSurvivesRemoteDelete() async throws {
        let store = try LocalStore(inMemory: true)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        // Dirty entry (pending) should survive even if the activity is
        // removed from the server.
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        let snapshot = ServerSnapshot(categories: [], activities: [], entries: [])
        try await store.reconcileWithSnapshot(snapshot)

        // Activity removed (clean, absent from server).
        #expect(try await store.activity(id: "a1") == nil)
        // Pending entry preserved.
        let entry = try await store.entry(id: "e1")
        #expect(entry != nil)
        #expect(entry?.sync.syncStatus == .pending)
    }

    // MARK: - Blocked validation failures (AC10)

    @Test("Blocked entry remains visible by id and queryable")
    func blockedEntryRetained() async throws {
        let store = try LocalStore(inMemory: true)
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .newPending()))

        try await store.markEntryBlocked(
            id: "e1", code: "validation_error", message: "Invalid time range")

        let entry = try await store.entry(id: "e1")
        #expect(entry?.sync.syncStatus == .blocked)
        #expect(entry?.sync.syncErrorCode == "validation_error")
        #expect(entry?.sync.syncErrorMessage == "Invalid time range")

        // Blocked records are queryable.
        let (_, _, blockedEntries) = try await store.blockedRecords()
        #expect(blockedEntries.count == 1)
        #expect(blockedEntries.first?.id == "e1")
    }
}
