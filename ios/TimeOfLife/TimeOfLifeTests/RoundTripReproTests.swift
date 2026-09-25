import Testing
import Foundation
@testable import TimeOfLife

/// Prevention regression test for the SiWA round-trip triplication
/// (fix-round-trip-duplication): A→B→A→B with drains must not multiply
/// entries locally or leave duplicate generations on either relay.
@MainActor
@Suite("Round-trip duplication")
struct RoundTripReproTests {

    @Test("account round trips do not duplicate entries")
    func roundTripsDoNotDuplicateEntries() async throws {
        let store = try LocalStore(url: scratchStoreURL())
        let mock = MockCatalogRepository()
        let controller = SyncController(
            store: store, remote: mock,
            connectivity: MockConnectivity(connected: true)
        )
        // Account A relay holds one previously-synced entry + category.
        let catA = Category(id: "cat-A", name: "Sport", icon: "tag")
        let entryA = TimeEntry(
            id: "e-A", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600),
            durationSeconds: 600, source: "manual",
            categoryIDs: ["cat-A"], notes: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        try await store.mergeCategory(catA)
        try await store.mergeEntry(entryA)
        try await store.setSyncAccountId("user-A")
        let relay = RoundTripRelay(mock: mock, seedCat: catA, seedEntry: entryA)

        for (account, userID) in [("A", "user-A"), ("B", "user-B"), ("A", "user-A"), ("B", "user-B")] {
            relay.pointMock(at: account)
            controller.activate(accountId: userID)
            await waitForQuiescence(controller, store: store, account: userID)
        }

        // Still exactly one local row per logical entry, and each relay
        // holds no duplicate generations either.
        #expect(try await store.entries().count == 1)
        #expect(relay.entriesA.count == 1)
        #expect(relay.entriesB.count == 1)
    }

    /// Fake per-account relay state (accept everything, like fresh UUIDs;
    /// hard-deletes stand in for tombstones on the real relay).
    private final class RoundTripRelay {
        var catsA: [Category]
        var entriesA: [TimeEntry]
        var catsB: [Category] = []
        var entriesB: [TimeEntry] = []
        var current = "A"

        init(mock: MockCatalogRepository, seedCat: Category, seedEntry: TimeEntry) {
            self.catsA = [seedCat]
            self.entriesA = [seedEntry]
            self.mock = mock
            mock.createCategoryHandler = { [weak self] cat in self?.createCategory(cat) }
            mock.createEntryHandler = { [weak self] entry in self?.createEntry(entry) }
            mock.deleteEntryHandler = { [weak self] id in self?.deleteEntry(id) }
            mock.deleteCategoryHandler = { [weak self] id in self?.deleteCategory(id) }
        }

        func pointMock(at account: String) {
            current = account
            mock.deletionsResult = []
            if account == "A" {
                mock.categoriesResult = catsA
                mock.entriesResult = entriesA
            } else {
                mock.categoriesResult = catsB
                mock.entriesResult = entriesB
            }
        }

        private let mock: MockCatalogRepository

        private func createCategory(_ cat: Category) {
            if current == "A", !catsA.contains(where: { $0.id == cat.id }) { catsA.append(cat) }
            if current == "B", !catsB.contains(where: { $0.id == cat.id }) { catsB.append(cat) }
        }

        private func createEntry(_ entry: TimeEntry) {
            if current == "A", !entriesA.contains(where: { $0.id == entry.id }) { entriesA.append(entry) }
            if current == "B", !entriesB.contains(where: { $0.id == entry.id }) { entriesB.append(entry) }
        }

        private func deleteEntry(_ id: String) {
            entriesA.removeAll { $0.id == id }
            entriesB.removeAll { $0.id == id }
        }

        private func deleteCategory(_ id: String) {
            catsA.removeAll { $0.id == id }
            catsB.removeAll { $0.id == id }
        }
    }

    /// Quiescence that also covers the detached account-switch path in
    /// `activate(accountId:)` (it flips to `.syncing` asynchronously, so a
    /// plain status check can observe idle before the switch even starts).
    private func waitForQuiescence(
        _ controller: SyncController,
        store: LocalStore,
        account: String
    ) async {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if case .syncing = controller.status {
                // Switch cycle still running (or not yet started).
            } else if (try? await store.syncAccountId()) == account,
                (try? await store.outboxRows().isEmpty) == true {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForCycle(_ controller: SyncController) async {
        await waitUntil {
            if case .syncing = controller.status { return false }
            return true
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func scratchStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
    }
}
