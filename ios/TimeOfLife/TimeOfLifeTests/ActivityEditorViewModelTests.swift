import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ActivityEditorViewModel")
struct ActivityEditorViewModelTests {

    @Test("the draft is prefilled with the trimmed query name")
    func prefillsName() {
        let vm = makeVM(prefilledName: "  Gym  ")
        #expect(vm.name == "  Gym  ")
        #expect(vm.canSave)
    }

    @Test("an empty name disables save and validates")
    func emptyNameValidation() {
        let vm = makeVM(prefilledName: "")
        #expect(!vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.name != nil)
    }

    @Test("an overlong name validates")
    func tooLongNameValidation() {
        let vm = makeVM(prefilledName: String(repeating: "a", count: 61))
        #expect(!vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.name != nil)
    }

    @Test("overlong notes validate")
    func tooLongNotesValidation() {
        let vm = makeVM(prefilledName: "Gym")
        vm.notes = String(repeating: "n", count: 281)
        #expect(vm.canSave)
        vm.save()
        #expect(vm.fieldErrors.notes != nil)
    }

    @Test("editing a field clears its error")
    func editingClearsFieldError() {
        let vm = makeVM(prefilledName: "")
        vm.save()
        #expect(vm.fieldErrors.name != nil)
        vm.name = "Gym"
        vm.nameDidChange()
        #expect(vm.fieldErrors.name == nil)
    }

    @Test("save creates the activity locally and reports it")
    func saveCreates() async throws {
        let store = try makeStore()
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "Gym",
            onSaved: { savedActivity = $0 },
            onCollision: { _, _ in Issue.record("unexpected collision") }
        )
        vm.notes = "Leg day"
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.name == "Gym")
        #expect(savedActivity?.notes == "Leg day")
        let stored = try await store.activity(named: "gym")
        #expect(stored?.name == "Gym")
        let rows = try await store.outboxRows()
        #expect(rows.count == 1)
        #expect(rows.first?.op == "create")
    }

    @Test("save with empty notes stores nil")
    func saveEmptyNotes() async throws {
        let store = try makeStore()
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "Gym",
            onSaved: { savedActivity = $0 },
            onCollision: { _, _ in Issue.record("unexpected collision") }
        )
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.notes == nil)
        let stored = try await store.activity(id: savedActivity?.id ?? "")
        #expect(stored?.notes == nil)
    }

    @Test("save reuses an existing case-insensitive activity")
    func saveReusesExisting() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "GYM",
            onSaved: { savedActivity = $0 },
            onCollision: { _, _ in Issue.record("unexpected collision") }
        )
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.id == "a1")
        let count = try await store.activities().count
        #expect(count == 1)
    }

    @Test("save with optional categories assigns them")
    func saveWithCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))
        var savedActivity: Activity?
        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "Gym",
            onSaved: { savedActivity = $0 },
            onCollision: { _, _ in Issue.record("unexpected collision") }
        )
        vm.selectedCategoryIDs = ["cat-1"]
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(savedActivity?.categoryIDs == ["cat-1"])
        let stored = try await store.activity(id: savedActivity?.id ?? "")
        #expect(stored?.categoryIDs == ["cat-1"])
    }

    @Test("a save colliding with a pending deletion reports the collision")
    func saveCollisionReports() async throws {
        let store = try makeStore()
        let activity = Activity(id: "a1", name: "Coding")
        let snapshot = DeletionSnapshot(records: [
            DeletionSnapshot.Record(
                resource: "activity",
                recordID: activity.id,
                data: try JSONEncoder().encode(activity)
            ),
        ])
        try await store.undoBufferEnter(payload: try JSONEncoder().encode(snapshot), deletedAt: Date())

        var collision: (Activity, ActivityDraft)?
        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "coding",
            onSaved: { _ in Issue.record("unexpected save") },
            onCollision: { existing, draft in collision = (existing, draft) }
        )
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(collision?.0.id == "a1")
        #expect(collision?.1.name == "coding")
        let count = try await store.activities().count
        #expect(count == 0)
        let rows = try await store.outboxRows()
        #expect(rows.isEmpty)
    }

    @Test("availableCategories loads the name-ordered catalog")
    func availableCategoriesLoads() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "cat-2", name: "Life", icon: "heart"))
        try await store.createCategory(TimeOfLife.Category(id: "cat-1", name: "Work", icon: "briefcase"))

        let vm = ActivityEditorViewModel(
            store: store,
            prefilledName: "Gym",
            onSaved: { _ in },
            onCollision: { _, _ in }
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.availableCategories.map(\.name) == ["Life", "Work"])
    }

    // MARK: - Helpers

    private func makeVM(prefilledName: String) -> ActivityEditorViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        return ActivityEditorViewModel(
            store: store,
            prefilledName: prefilledName,
            onSaved: { _ in },
            onCollision: { _, _ in }
        )
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
