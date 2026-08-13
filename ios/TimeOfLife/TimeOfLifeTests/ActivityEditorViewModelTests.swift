import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ActivityEditorViewModel")
struct ActivityEditorViewModelTests {

    // MARK: - Prefilling

    @Test("the draft is prefilled with the persisted Activity values")
    func prefillsFromActivity() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym", notes: "Leg day"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.name == "Gym")
        #expect(vm.notes == "Leg day")
        #expect(vm.selectedCategoryIDs.isEmpty)
        #expect(vm.canSave)
        #expect(vm.activityID == "a1")
    }

    @Test("the draft prefills Category identifiers from the persisted Activity")
    func prefillsCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createActivity(Activity(id: "a1", name: "Gym", categoryIDs: ["cat-1"]))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.selectedCategoryIDs == ["cat-1"])
    }

    @Test("an Activity with nil notes prefills empty notes")
    func prefillsNilNotesAsEmpty() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        #expect(vm.notes.isEmpty)
    }

    // MARK: - Validation

    @Test("an empty name disables save and validates")
    func emptyNameValidation() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.name = ""
        #expect(!vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.name != nil)
    }

    @Test("an overlong name validates")
    func tooLongNameValidation() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.name = String(repeating: "a", count: 61)
        #expect(!vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.name != nil)
    }

    @Test("overlong notes validate")
    func tooLongNotesValidation() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.notes = String(repeating: "n", count: 281)
        #expect(vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.notes != nil)
    }

    @Test("editing a field clears its error")
    func editingClearsFieldError() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.name = ""
        vm.save()
        #expect(vm.fieldErrors.name != nil)
        vm.name = "Gym"
        vm.nameDidChange()
        #expect(vm.fieldErrors.name == nil)
    }

    // MARK: - Save

    @Test("save updates the Activity locally and reports it")
    func saveUpdates() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.notes = "Leg day"
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.name == "Gym")
        #expect(savedActivity?.notes == "Leg day")
        #expect(savedActivity?.id == "a1")
        let stored = try await store.activity(id: "a1")
        #expect(stored?.notes == "Leg day")
        let rows = try await store.outboxRows()
        let updateRow = try #require(rows.last)
        #expect(updateRow.op == "update")
    }

    @Test("save with empty notes stores nil")
    func saveEmptyNotes() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym", notes: "Old notes"))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.notes = ""
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.notes == nil)
        let stored = try await store.activity(id: "a1")
        #expect(stored?.notes == nil)
    }

    @Test("save with no changes is a valid same-identity save")
    func saveNoChanges() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.id == "a1")
        #expect(savedActivity?.name == "Gym")
        let count = try await store.activities().count
        #expect(count == 1)
    }

    @Test("save with optional categories assigns them")
    func saveWithCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.selectedCategoryIDs = ["cat-1"]
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.categoryIDs == ["cat-1"])
        let stored = try await store.activity(id: "a1")
        #expect(stored?.categoryIDs == ["cat-1"])
    }

    @Test("save renaming to an existing normalized name reports a collision")
    func saveCollisionReports() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.createActivity(Activity(id: "a2", name: "Reading"))
        let activity = try #require(await store.activity(id: "a1"))
        var collision: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in Issue.record("unexpected save") },
            onCollision: { collision = $0 }
        )
        vm.name = "Reading"
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(collision?.id == "a2")
        let stored = try await store.activity(id: "a1")
        #expect(stored?.name == "Gym")
    }

    @Test("save for a missing Activity shows an error")
    func saveMissingShowsError() async throws {
        let store = try makeStore()
        let activity = Activity(id: "nonexistent", name: "Ghost")
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test("availableCategories loads the name-ordered catalog")
    func availableCategoriesLoads() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-2", name: "Life", icon: "heart"))
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))

        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.availableCategories.map(\.name) == ["Life", "Work"])
    }

    @Test("refreshing categories keeps the draft and sees newly created categories")
    func refreshesAvailableCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.toggleCategory("cat-1")
        try? await Task.sleep(nanoseconds: 100_000_000)

        try await store.createCategory(TimeOfLife.Category(id: "cat-2", name: "Health", icon: "heart"))
        await vm.reloadCategories()
        vm.selectCategory("cat-2")

        #expect(vm.availableCategories.map(\.name) == ["Health", "Work"])
        #expect(vm.selectedCategoryIDs == ["cat-1", "cat-2"])
    }

    // MARK: - Ordered multi-selection (category-management D5/D6)

    @Test("toggling categories keeps the selection ordered")
    func orderedSelectionPreserved() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { _ in },
            onCollision: { _ in }
        )
        vm.toggleCategory("cat-1")
        vm.toggleCategory("cat-2")
        vm.toggleCategory("cat-3")
        #expect(vm.selectedCategoryIDs == ["cat-1", "cat-2", "cat-3"])

        // Removing one keeps the remaining order.
        vm.toggleCategory("cat-1")
        #expect(vm.selectedCategoryIDs == ["cat-2", "cat-3"])
        // Clearing all leaves an empty selection.
        vm.toggleCategory("cat-2")
        vm.toggleCategory("cat-3")
        #expect(vm.selectedCategoryIDs.isEmpty)
    }

    @Test("saving preserves the selection order in the persisted Activity")
    func savePreservesSelectionOrder() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createCategory(TimeOfLife.Category(id: "cat-2", name: "Health", icon: "heart"))
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.toggleCategory("cat-2")
        vm.toggleCategory("cat-1")
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.categoryIDs == ["cat-2", "cat-1"])
        let stored = try await store.activity(id: "a1")
        #expect(stored?.categoryIDs == ["cat-2", "cat-1"])
    }

    @Test("an invalid association reports an error and preserves the draft")
    func invalidAssociationPreservesDraft() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        try await store.createActivity(Activity(id: "a1", name: "Gym", categoryIDs: ["cat-1"]))
        let activity = try #require(await store.activity(id: "a1"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: { savedActivity = $0 },
            onCollision: { _ in Issue.record("unexpected collision") }
        )
        vm.toggleCategory("stale-category") // references a category that does not exist
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity == nil)
        #expect(vm.errorMessage != nil)
        // The draft is preserved for retry.
        #expect(vm.name == "Gym")
        #expect(vm.selectedCategoryIDs.contains("stale-category"))
        // Nothing was persisted.
        let stored = try await store.activity(id: "a1")
        #expect(stored?.name == "Gym")
        #expect(stored?.categoryIDs == ["cat-1"])
    }

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
