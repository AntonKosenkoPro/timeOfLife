import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TrackViewModel Refinement")
struct TrackViewModelRefinementTests {

    // MARK: - Presentation

    @Test("presentRefinement resolves the selected Activity and opens the editor")
    func presentRefinementOpensEditor() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym", notes: "Leg day"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))

        vm.presentRefinement()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let presentation = try #require(vm.refinementPresentation)
        #expect(presentation.activity.id == "a1")
        #expect(presentation.activity.name == "Gym")
        #expect(presentation.activity.notes == "Leg day")
    }

    @Test("presentRefinement does nothing from idle")
    func presentRefinementIdle() async {
        let vm = makeViewModel()
        vm.presentRefinement()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.refinementPresentation == nil)
    }

    @Test("presentRefinement with a stale selection clears preparation and shows an error")
    func presentRefinementStale() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))

        try await store.deleteActivity(id: "a1")
        vm.presentRefinement()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.refinementPresentation == nil)
        #expect(vm.state == .idle)
        #expect(vm.errorMessage != nil)
    }

    @Test("dismissRefinement closes the editor without acting")
    func dismissRefinementCancels() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))
        vm.presentRefinement()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.refinementPresentation != nil)

        vm.dismissRefinement()
        #expect(vm.refinementPresentation == nil)
        #expect(vm.state.activity?.id == "a1")
        #expect(vm.state.activity?.name == "Gym")
    }

    // MARK: - Save: state-preserving replacement

    @Test("saveRefinement replaces the Activity in ready state without transitioning")
    func saveRefinementReady() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))

        let updated = Activity(id: "a1", name: "Deep Work", notes: "Focus")
        await vm.saveRefinement(updated: updated)

        guard case let .ready(activity) = vm.state else {
            Issue.record("expected ready state")
            return
        }
        #expect(activity.id == "a1")
        #expect(activity.name == "Deep Work")
        #expect(vm.refinementPresentation == nil)
    }

    @Test("saveRefinement preserves running state startedAt and activity identity")
    func saveRefinementRunning() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Coding"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Coding"))
        vm.start()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let originalStartedAt: Date = {
            if case let .running(_, startedAt) = vm.state { return startedAt }
            fatalError("expected running")
        }()

        let updated = Activity(id: "a1", name: "Deep Work", notes: "Focus")
        await vm.saveRefinement(updated: updated)

        guard case let .running(activity, startedAt) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(activity.id == "a1")
        #expect(activity.name == "Deep Work")
        #expect(startedAt == originalStartedAt)
    }

    @Test("saveRefinement preserves saved state duration")
    func saveRefinementSaved() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Coding"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Coding"))
        vm.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await vm.stop()

        guard case let .saved(_, duration) = vm.state else {
            Issue.record("expected saved state")
            return
        }

        let updated = Activity(id: "a1", name: "Deep Work")
        await vm.saveRefinement(updated: updated)

        guard case let .saved(activity, preservedDuration) = vm.state else {
            Issue.record("expected saved state preserved")
            return
        }
        #expect(activity.id == "a1")
        #expect(activity.name == "Deep Work")
        #expect(preservedDuration == duration)
    }

    @Test("saveRefinement refreshes the catalog")
    func saveRefinementRefreshesCatalog() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))
        #expect(vm.activities.first?.name == "Gym")

        // Persist the refinement so the catalog refresh sees the new name
        _ = try await store.refineActivity(
            id: "a1",
            draft: ActivityDraft(name: "Deep Work"),
            now: Date(timeIntervalSinceReferenceDate: 5_000)
        )
        let updated = try #require(await store.activity(id: "a1"))
        await vm.saveRefinement(updated: updated)

        #expect(vm.activities.first?.name == "Deep Work")
    }

    @Test("saveRefinement preserves the Activity identifier")
    func saveRefinementPreservesIdentity() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Gym"))

        let updated = Activity(id: "a1", name: "Renamed")
        await vm.saveRefinement(updated: updated)

        #expect(vm.state.activity?.id == "a1")
        let count = try await store.activities().count
        #expect(count == 1)
    }

    // MARK: - Helpers

    private func makeViewModel() -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return TrackViewModel(service: service, connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
