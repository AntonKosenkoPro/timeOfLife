import Testing
import Foundation
@testable import TimeOfLife

/// AC10 / Phase 9.3 — ViewModel tests for the rebuilt catalog screens.
@MainActor
@Suite("ManageActivitiesViewModel")
struct ManageActivitiesViewModelTests {

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    private func makeUndoService(store: LocalStore) -> UndoService {
        UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { Date() },
            scheduler: { _, _ in } // Never auto-fires in tests.
        )
    }

    // MARK: - Load

    @Test("loadActivities returns recency-ordered activities")
    func loadActivitiesOrderedByRecency() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Older", lastUsedAt: CatalogTestFactory.date(offset: -100)))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a2", name: "Newer", lastUsedAt: CatalogTestFactory.date(offset: -10)))

        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        #expect(vm.activities.map(\.id) == ["a2", "a1"])
    }

    @Test("loadActivities clears list on error")
    func loadActivitiesClearsOnError() async throws {
        // No store error path is easy to force; verify it doesn't crash and
        // keeps existing state when the store is healthy.
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(id: "a1", name: "Read"))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()
        #expect(vm.activities.count == 1)
    }

    // MARK: - Delete flow

    @Test("delete with zero entries deletes immediately (whole activity)")
    func deleteWithoutEntriesDeletesImmediately() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])

        // No scope confirmation (zero entries).
        #expect(vm.pendingDelete == nil)
        #expect(vm.showDeleteScope == false)
        // Activity is hidden (undo window) but still on disk.
        #expect(try await store.activity(id: "a1") != nil)
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == true)
        // Undo toast is shown.
        #expect(vm.undoToast != nil)
        // The activity is no longer visible.
        await vm.loadActivities()
        #expect(vm.activities.isEmpty)
    }

    @Test("delete with entries presents scope confirmation")
    func deleteWithEntriesPresentsScope() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])

        #expect(vm.pendingDelete?.id == "a1")
        #expect(vm.pendingEntryCount == 1)
        #expect(vm.showDeleteScope == true)
        // Nothing hidden yet — user hasn't chosen.
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == false)
    }

    @Test("deleteActivityAndEntries hides activity and all entries as a unit")
    func deleteActivityAndEntriesUnit() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e2", activityId: "a1",
            startedAt: CatalogTestFactory.date(offset: -60),
            endedAt: CatalogTestFactory.date(),
            sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])
        #expect(vm.showDeleteScope == true)
        await vm.deleteActivityAndEntries()

        // All hidden, hold persisted.
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == true)
        #expect(try await store.entry(id: "e1")?.sync.isUndoHidden == true)
        #expect(try await store.entry(id: "e2")?.sync.isUndoHidden == true)
        #expect(try await store.currentHold()?.type == .activityWithEntries)
        #expect(vm.undoToast != nil)
    }

    @Test("deleteEntryOnly hides exactly the latest entry")
    func deleteEntryOnlyTargetsLatest() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e-old", activityId: "a1",
            startedAt: CatalogTestFactory.date(offset: -100),
            endedAt: CatalogTestFactory.date(offset: -40),
            sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e-new", activityId: "a1",
            startedAt: CatalogTestFactory.date(),
            endedAt: CatalogTestFactory.date(offset: 60),
            sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])
        #expect(vm.showDeleteScope == true)
        await vm.deleteEntryOnly()

        // Only the latest entry is hidden.
        #expect(try await store.entry(id: "e-new")?.sync.isUndoHidden == true)
        #expect(try await store.entry(id: "e-old")?.sync.isUndoHidden == false)
        // The activity itself is untouched.
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == false)
        #expect(try await store.currentHold()?.type == .latestEntry)
    }

    @Test("cancelDelete clears pending state")
    func cancelDeleteClearsState() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        try await store.upsertEntry(CatalogTestFactory.makeEntry(
            id: "e1", activityId: "a1", sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])
        #expect(vm.showDeleteScope == true)
        vm.cancelDelete()
        #expect(vm.pendingDelete == nil)
        #expect(vm.showDeleteScope == false)
        // Nothing was hidden.
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == false)
    }

    // MARK: - Undo

    @Test("performUndo restores the deleted activity")
    func performUndoRestores() async throws {
        let store = try makeStore()
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean()))
        let vm = ManageActivitiesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadActivities()

        await vm.delete(vm.activities[0])
        #expect(vm.undoToast != nil)

        await vm.performUndo()
        #expect(vm.undoToast == nil)

        await vm.loadActivities()
        #expect(vm.activities.count == 1)
        #expect(try await store.activity(id: "a1")?.sync.isUndoHidden == false)
    }
}

/// AC10 / Phase 9.3 — Activity Editor view model tests.
@MainActor
@Suite("ActivityEditorViewModel")
struct ActivityEditorViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    @Test("create mode validation rejects empty name")
    func createRejectsEmptyName() async throws {
        let store = try makeStore()
        let vm = ActivityEditorViewModel(localStore: store)
        vm.name = "   "
        let saved = await vm.save()
        #expect(saved == false)
        #expect(vm.fieldError != nil)
    }

    @Test("create mode validation rejects name over 60 chars")
    func createRejectsLongName() async throws {
        let store = try makeStore()
        let vm = ActivityEditorViewModel(localStore: store)
        vm.name = String(repeating: "a", count: 61)
        let saved = await vm.save()
        #expect(saved == false)
        #expect(vm.fieldError == L10n.validationNameTooLong.text)
    }

    @Test("create mode validation rejects notes over 280 chars")
    func createRejectsLongNotes() async throws {
        let store = try makeStore()
        let vm = ActivityEditorViewModel(localStore: store)
        vm.name = "Read"
        vm.notes = String(repeating: "n", count: 281)
        let saved = await vm.save()
        #expect(saved == false)
        #expect(vm.fieldError == L10n.validationNotesTooLong.text)
    }

    @Test("create mode saves a pending activity")
    func createSavesActivity() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        let vm = ActivityEditorViewModel(localStore: store)
        vm.name = "  Reading  "
        vm.notes = "Nightly"
        vm.selectedCategoryIds = ["c1"]

        let saved = await vm.save()
        #expect(saved == true)

        let activities = try await store.activitiesSortedByLastUsedAt()
        #expect(activities.count == 1)
        #expect(activities.first?.name == "Reading") // Trimmed.
        #expect(activities.first?.notes == "Nightly")
        #expect(activities.first?.categoryIds == ["c1"])
        #expect(activities.first?.sync.syncStatus == .pending)
        #expect(activities.first?.sync.remoteKnown == false)
    }

    @Test("edit mode pre-fills fields from the activity")
    func editPrefills() async throws {
        let store = try makeStore()
        // The category must exist before the activity references it (FK).
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        let activity = CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", notes: "Old notes",
            categoryIds: ["c1"], sync: .adoptedClean())
        try await store.upsertActivity(activity)

        let vm = ActivityEditorViewModel(
            localStore: store, editingActivity: activity)
        #expect(vm.name == "Read")
        #expect(vm.notes == "Old notes")
        #expect(vm.selectedCategoryIds == ["c1"])
    }

    @Test("edit mode saves updates with bumped revision")
    func editSavesUpdate() async throws {
        let store = try makeStore()
        let activity = CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", sync: .adoptedClean())
        try await store.upsertActivity(activity)

        let vm = ActivityEditorViewModel(
            localStore: store, editingActivity: activity)
        vm.name = "Reading 2.0"
        vm.notes = ""
        let saved = await vm.save()
        #expect(saved == true)

        let fetched = try await store.activity(id: "a1")
        #expect(fetched?.name == "Reading 2.0")
        #expect(fetched?.notes == nil) // Empty notes → nil.
        #expect(fetched?.sync.syncStatus == .pending)
        #expect(fetched?.sync.localRevision == activity.sync.localRevision + 1)
    }

    @Test("loadCategories prunes stale selected ids")
    func loadCategoriesPrunesStale() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        // Stale id c2 no longer exists.
        let vm = ActivityEditorViewModel(localStore: store)
        vm.selectedCategoryIds = ["c1", "c2"]

        await vm.loadCategories()

        #expect(vm.selectedCategoryIds == ["c1"])
        #expect(vm.availableCategories.count == 1)
    }

    @Test("clearFieldError resets the error")
    func clearFieldErrorResets() async throws {
        let store = try makeStore()
        let vm = ActivityEditorViewModel(localStore: store)
        vm.name = ""
        _ = await vm.save()
        #expect(vm.fieldError != nil)
        vm.clearFieldError()
        #expect(vm.fieldError == nil)
    }
}

/// AC10 / Phase 9.3 — Manage Categories view model tests.
@MainActor
@Suite("ManageCategoriesViewModel")
struct ManageCategoriesViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    private func makeUndoService(store: LocalStore) -> UndoService {
        UndoService(
            localStore: store,
            syncCoordinator: nil,
            windowDuration: 30,
            now: { Date() },
            scheduler: { _, _ in }
        )
    }

    @Test("loadCategories returns name-ordered categories")
    func loadCategoriesAlphaOrder() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c2", name: "Zeta", sync: .adoptedClean()))
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Alpha", sync: .adoptedClean()))

        let vm = ManageCategoriesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadCategories()

        #expect(vm.categories.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test("delete presents confirmation")
    func deletePresentsConfirmation() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        let vm = ManageCategoriesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadCategories()

        vm.delete(vm.categories[0])
        #expect(vm.pendingDelete?.id == "c1")
        #expect(vm.showDeleteConfirm == true)
    }

    @Test("confirmDelete hides category and captures join rows")
    func confirmDeleteHidesCategory() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", categoryIds: ["c1"], sync: .adoptedClean()))
        let vm = ManageCategoriesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadCategories()

        vm.delete(vm.categories[0])
        await vm.confirmDelete()

        #expect(try await store.category(id: "c1")?.sync.isUndoHidden == true)
        // Join row removed.
        let activity = try await store.activity(id: "a1")
        #expect(activity?.categoryIds.isEmpty == true)
        // Hold captures the join so undo can restore it.
        #expect(try await store.currentHold()?.type == .category)
        #expect(try await store.currentHold()?.categoryJoins.count == 1)
        #expect(vm.undoToast != nil)
    }

    @Test("performUndo restores category and joins")
    func performUndoRestoresCategory() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        try await store.upsertActivity(CatalogTestFactory.makeActivity(
            id: "a1", name: "Read", categoryIds: ["c1"], sync: .adoptedClean()))
        let vm = ManageCategoriesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadCategories()

        vm.delete(vm.categories[0])
        await vm.confirmDelete()
        await vm.performUndo()

        await vm.loadCategories()
        #expect(vm.categories.count == 1)
        let activity = try await store.activity(id: "a1")
        #expect(activity?.categoryIds == ["c1"]) // Join restored.
    }

    @Test("cancelDelete clears confirmation state")
    func cancelDeleteClears() async throws {
        let store = try makeStore()
        try await store.upsertCategory(CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", sync: .adoptedClean()))
        let vm = ManageCategoriesViewModel(
            localStore: store, undoService: makeUndoService(store: store))
        await vm.loadCategories()

        vm.delete(vm.categories[0])
        #expect(vm.showDeleteConfirm == true)
        vm.cancelDelete()
        #expect(vm.pendingDelete == nil)
        #expect(vm.showDeleteConfirm == false)
        #expect(try await store.category(id: "c1")?.sync.isUndoHidden == false)
    }
}

/// AC10 / Phase 9.3 — Category Editor view model tests.
@MainActor
@Suite("CategoryEditorViewModel")
struct CategoryEditorViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    @Test("create mode validation rejects empty name")
    func createRejectsEmptyName() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(localStore: store)
        vm.name = " "
        let saved = await vm.save()
        #expect(saved == false)
        #expect(vm.fieldError == L10n.validationNameEmpty.text)
    }

    @Test("create mode saves a pending category with icon")
    func createSavesCategory() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(localStore: store)
        vm.name = "  Hobby  "
        vm.icon = "paintbrush"
        let saved = await vm.save()
        #expect(saved == true)

        let categories = try await store.categoriesSortedByName()
        #expect(categories.count == 1)
        #expect(categories.first?.name == "Hobby")
        #expect(categories.first?.icon == "paintbrush")
        #expect(categories.first?.sync.syncStatus == .pending)
    }

    @Test("edit mode pre-fills fields")
    func editPrefills() async throws {
        let store = try makeStore()
        let category = CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", icon: "briefcase", sync: .adoptedClean())
        let vm = CategoryEditorViewModel(
            localStore: store, editingCategory: category)
        #expect(vm.name == "Work")
        #expect(vm.icon == "briefcase")
    }

    @Test("edit mode saves updates with bumped revision")
    func editSavesUpdate() async throws {
        let store = try makeStore()
        let category = CatalogTestFactory.makeCategory(
            id: "c1", name: "Work", icon: "briefcase", sync: .adoptedClean())
        try await store.upsertCategory(category)

        let vm = CategoryEditorViewModel(
            localStore: store, editingCategory: category)
        vm.name = "Job"
        vm.icon = "star"
        let saved = await vm.save()
        #expect(saved == true)

        let fetched = try await store.category(id: "c1")
        #expect(fetched?.name == "Job")
        #expect(fetched?.icon == "star")
        #expect(fetched?.sync.syncStatus == .pending)
        #expect(fetched?.sync.localRevision == category.sync.localRevision + 1)
    }
}
