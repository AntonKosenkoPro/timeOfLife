import Testing
import Foundation
@testable import TimeOfLife

/// Track sync-exit reload (fix-track-empty-after-reinstall 3.2): Track must
/// converge on relay-pulled data without a tab switch, mirroring the
/// History/Insights `sync.status` observers. `loadIfNeeded`/`invalidate`
/// serialize concurrent reloads (tab-return vs sync-exit racing); `load()`
/// stays the unguarded worker.
@MainActor
@Suite("TrackSyncReload")
struct TrackSyncReloadTests {

    @Test("load after a seeded pull fills recents, names, and categories")
    func loadAfterSeededPullFillsTrack() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        _ = try await store.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
        let seeded = try await store.categories()
        #expect(seeded.count == 7)
        try await store.createEntry(makeEntry(
            id: "e1", text: "Gym", categoryIDs: [seeded[0].id]
        ))
        let vm = TrackViewModel(service: TimerService(store: store), connectivity: MockConnectivity(connected: true))

        await vm.loadIfNeeded()

        #expect(vm.recents.map(\.text) == ["Gym"])
        #expect(vm.allNames.map(\.text) == ["Gym"])
        #expect(vm.categories.count == 7)
        #expect(vm.errorMessage == nil)
    }

    @Test("concurrent loadIfNeeded calls serialize")
    func concurrentLoadIfNeededSerializes() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        _ = try await store.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
        let vm = TrackViewModel(service: TimerService(store: store), connectivity: MockConnectivity(connected: true))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await vm.loadIfNeeded() }
            }
            await group.waitForAll()
        }

        #expect(vm.categories.count == 7)
    }

    @Test("invalidate forces the next loadIfNeeded to reload")
    func invalidateForcesReload() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        _ = try await store.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
        let vm = TrackViewModel(service: TimerService(store: store), connectivity: MockConnectivity(connected: true))
        await vm.loadIfNeeded()
        #expect(vm.categories.count == 7)

        vm.invalidate()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        await vm.loadIfNeeded()

        #expect(vm.recents.map(\.text) == ["Gym"])
    }

    @Test("a sync-exit reload preserves the typing draft")
    func reloadPreservesTypingDraft() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        _ = try await store.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
        let vm = TrackViewModel(service: TimerService(store: store), connectivity: MockConnectivity(connected: true))
        vm.nameDraft = "Gym"

        await vm.loadIfNeeded()

        #expect(vm.nameDraft == "Gym", "reload must not clobber typing")
        #expect(vm.state == .idle)
    }

    @Test("a failed reload never blanks the last good snapshot")
    func reloadKeepsSnapshotOnFailure() async {
        // Unbound store: every read throws `notBound`.
        let vm = TrackViewModel(
            service: TimerService(store: LocalStore()),
            connectivity: MockConnectivity(connected: true)
        )
        vm.recents = [ExactName(text: "Gym", categoryIDs: [], firstCategoryID: nil)]

        await vm.load()

        #expect(vm.recents.map(\.text) == ["Gym"], "failed reload keeps the last good snapshot")
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Helpers

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func makeEntry(
        id: String,
        text: String,
        categoryIDs: [String] = []
    ) -> TimeEntry {
        let now = Date()
        return TimeEntry(
            id: id,
            activityText: text,
            startedAt: now,
            endedAt: now.addingTimeInterval(60),
            durationSeconds: 60,
            source: "manual",
            categoryIDs: categoryIDs
        )
    }

    // MARK: - Helpers
}
