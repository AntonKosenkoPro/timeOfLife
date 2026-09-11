import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ActivityEditorViewModel Delete (unify-catalog-deletion)")
struct ActivityEditorDeleteTests {

    @Test("deleteConfirmed removes the activity with its entries and returns true")
    func deleteRemovesActivityAndEntries() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )

        let shouldDismiss = await vm.deleteConfirmed()

        #expect(shouldDismiss)
        #expect(try await store.activity(id: "a1") == nil)
        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
    }

    @Test("deleteConfirmed for an already-gone activity returns true")
    func deleteMissingDismisses() async throws {
        let store = try makeStore()
        let vm = ActivityEditorViewModel(
            store: store,
            activity: Activity(id: "ghost", name: "Ghost"),
            onSaved: { _ in },
            onCollision: { _ in }
        )

        #expect(await vm.deleteConfirmed())
    }

    @Test("deleteConfirmed while the timer runs keeps the draft with a message")
    func deleteBlockedWhileRunning() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.startTimer(activityID: "a1", activityName: "Gym", startedAt: Date())
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.name = "Gym Renamed"

        let shouldDismiss = await vm.deleteConfirmed()

        #expect(!shouldDismiss)
        #expect(vm.errorMessage == L10n.activityDeleteRunning.text)
        // Draft intact, nothing removed, nothing buffered.
        #expect(vm.name == "Gym Renamed")
        #expect(try await store.activity(id: "a1") != nil)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    @Test("the delete scope loads the committed entry count and total")
    func deleteScopeLoads() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.originalName == "Gym")
        #expect(vm.committedEntryCount == 1)
        #expect(vm.committedTotalText == HistoryViewModel.detailedDuration(600))
    }

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }
}
