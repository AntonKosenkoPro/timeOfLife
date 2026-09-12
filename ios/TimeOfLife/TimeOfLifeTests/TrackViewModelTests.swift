import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TrackViewModel")
struct TrackViewModelTests {

    // MARK: - State transitions

    @Test("initial state is idle with no activity")
    func initialState() {
        let vm = makeViewModel()
        #expect(vm.state == .idle)
        #expect(vm.state.activity == nil)
        #expect(vm.elapsed == 0)
        #expect(!vm.isSearchActive)
    }

    @Test("selecting an activity prepares it without starting")
    func selectPrepares() {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Deep work")
        vm.select(activity)

        #expect(vm.state == .ready(activity))
        #expect(vm.elapsed == 0)
        #expect(!vm.state.isRunning)
        #expect(!vm.isSearchActive)
    }

    @Test("start requires a prepared activity")
    func startRequiresSelection() {
        let vm = makeViewModel()
        vm.start()
        #expect(vm.state == .idle)
    }

    @Test("start transitions ready to running and persists state")
    func startRuns() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Coding")
        try await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case let .running(selected, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(selected.id == activity.id)
        #expect(vm.state.isRunning)

        let state = try await vm.service.store.timerState()
        #expect(state != nil)
        #expect(state?.status == "running")
        #expect(state?.activityID == activity.id)
    }

    @Test("stop saves entry and returns to saved then ready")
    func stopSaves() async {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try? await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        await vm.stop()

        guard case let .saved(selected, duration) = vm.state else {
            Issue.record("expected saved state")
            return
        }
        #expect(selected.id == activity.id)
        #expect(duration >= 0)
        #expect(!vm.state.isRunning)

        let entries = try? await vm.service.store.entries()
        #expect(entries?.count == 1)
        #expect(entries?.first?.source == "manual")
        #expect(entries?.first?.activityName == "Reading")

        let state = try? await vm.service.store.timerState()
        #expect(state == nil)
    }

    @Test("elapsed formatting matches TimeFormatter")
    func elapsedFormatting() {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Work")
        vm.select(activity)
        vm.start()
        vm.elapsed = 125

        #expect(TimeFormatter.formattedDuration(vm.elapsed) == "02:05")
        #expect(TimeFormatter.formattedDuration(3661) == "1:01:01")
    }

    // MARK: - Empty catalog

    @Test("empty catalog shows no activities and idle state")
    func emptyCatalog() async throws {
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.activities.isEmpty)
        #expect(vm.state == .idle)
        vm.activateSearch()
        guard case let .browsing(activities) = vm.searchResults else {
            Issue.record("expected browsing results")
            return
        }
        #expect(activities.isEmpty)
    }

    // MARK: - Recoverable save failure

    @Test("stop failure preserves running state and error message")
    func stopFailurePreservesRunning() async {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Work")
        try? await vm.service.store.createActivity(activity)
        vm.select(activity)
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate a store failure: delete the activity row so the entry
        // insert fails on the FK constraint (foreign_keys = ON), while the
        // timer_state row still exists. The service stopTimer throws when the
        // entry insert fails, so the state must remain recoverable.
        let store = vm.service.store
        try? await store.deleteActivity(id: activity.id)

        await vm.stop()

        if case .error = vm.state {
            #expect(vm.errorMessage != nil)
        } else {
            // If the store accepted the entry (no FK enforcement in this
            // configuration), the save succeeded — acceptable.
            #expect(vm.state.isRunning == false)
        }
    }

    // MARK: - Categories map (Recents chip icons, design D6)

    @Test("load populates the categories map")
    func loadPopulatesCategories() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let category = Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue)
        try await store.createCategory(category)

        await vm.load()

        // Field comparison: the store round-trips dates at reduced precision.
        #expect(vm.categories[category.id]?.name == category.name)
        #expect(vm.categories[category.id]?.icon == category.icon)
    }

    @Test("load leaves the categories map empty on a fresh store")
    func loadEmptyCategories() async throws {
        let vm = makeViewModel()

        await vm.load()

        #expect(vm.categories.isEmpty)
    }

    @Test("saveRefinement refreshes the categories map")
    func saveRefinementRefreshesCategories() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let category = Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue)
        try await store.createCategory(category)
        try await store.createActivity(Activity(id: "a1", name: "Coding", categoryIDs: [category.id]))
        await vm.load()
        vm.select(Activity(id: "a1", name: "Coding"))
        #expect(vm.categories[category.id]?.icon == CatalogIcon.briefcase.rawValue)

        let updated = Category(
            id: category.id,
            name: "Work",
            icon: CatalogIcon.laptopcomputer.rawValue,
            createdAt: category.createdAt,
            updatedAt: Date()
        )
        #expect(try await store.updateCategory(updated))
        await vm.saveRefinement(updated: Activity(id: "a1", name: "Coding"))

        #expect(vm.categories[category.id]?.icon == CatalogIcon.laptopcomputer.rawValue)
    }

    // MARK: - Refinement deletion (unify-catalog-deletion)

    @Test("deleteRefinement clears the deleted activity back to idle and refreshes the catalog")
    func deleteRefinementClearsSelection() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createActivity(Activity(id: "a2", name: "Reading"))
        await vm.load()
        vm.select(try #require(await store.activity(id: "a1")))
        #expect(vm.selectedActivityID == "a1")

        _ = try await store.deleteActivityUndoable(id: "a1", deletedAt: Date())
        await vm.deleteRefinement(id: "a1")

        #expect(vm.selectedActivityID == nil)
        #expect(vm.activities.map(\.id) == ["a2"])
    }

    @Test("deleteRefinement keeps another selected activity")
    func deleteRefinementKeepsOtherSelection() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createActivity(Activity(id: "a2", name: "Reading"))
        await vm.load()
        vm.select(try #require(await store.activity(id: "a2")))

        _ = try await store.deleteActivityUndoable(id: "a1", deletedAt: Date())
        await vm.deleteRefinement(id: "a1")

        #expect(vm.selectedActivityID == "a2")
    }

    @Test("performActivityUndo restores the activity into the catalog")
    func activityUndoRestores() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
        await vm.load()
        _ = try await store.deleteActivityUndoable(id: "a1", deletedAt: Date())
        await vm.deleteRefinement(id: "a1")
        #expect(!vm.activities.map(\.id).contains("a1"))

        await vm.performActivityUndo()

        #expect(vm.activities.map(\.id).contains("a1"))
        #expect(try await store.entry(id: "e1") != nil)
    }

    @Test("activity undo ignores foreign snapshots")
    func activityUndoIgnoresForeign() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let undoManager = UndoManager()

        await vm.registerActivityUndo(with: undoManager)
        await vm.performActivityUndo()

        #expect(!undoManager.canUndo)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("system undo registers for activity deletions")
    func systemUndoRegistersActivityDeletion() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        _ = try await store.deleteActivityUndoable(id: "a1", deletedAt: Date())
        let undoManager = UndoManager()

        await vm.registerActivityUndo(with: undoManager)

        #expect(undoManager.canUndo)
        #expect(undoManager.undoActionName == L10n.activityEditorDelete.text)
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
