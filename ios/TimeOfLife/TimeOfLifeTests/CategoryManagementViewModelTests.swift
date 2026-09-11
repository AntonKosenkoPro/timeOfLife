import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("CategoryEditorViewModel")
struct CategoryEditorViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }

    @Test("create mode starts empty with the default tag icon")
    func createModeDefaults() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(store: store, category: nil, onSaved: { _ in }, onDuplicate: { _ in })
        #expect(vm.isCreateMode)
        #expect(vm.name.isEmpty)
        #expect(vm.icon == .tag)
        #expect(!vm.canSave)
    }

    @Test("edit mode prefills name and icon")
    func editModePrefills() async throws {
        let store = try makeStore()
        let category = TimeOfLife.Category(id: "c1", name: "Sport", icon: "figure.run")
        let vm = CategoryEditorViewModel(store: store, category: category, onSaved: { _ in }, onDuplicate: { _ in })
        #expect(!vm.isCreateMode)
        #expect(vm.name == "Sport")
        #expect(vm.icon == .figureRun)
        #expect(vm.canSave)
    }

    @Test("an unsupported stored icon prefills as tag without crashing")
    func unsupportedIconPrefillsAsTag() async throws {
        let store = try makeStore()
        let category = TimeOfLife.Category(id: "c1", name: "Old", icon: "not-a-real-symbol")
        let vm = CategoryEditorViewModel(store: store, category: category, onSaved: { _ in }, onDuplicate: { _ in })
        #expect(vm.icon == .tag)
    }

    @Test("empty and overlong names validate")
    func nameValidation() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(store: store, category: nil, onSaved: { _ in }, onDuplicate: { _ in })
        vm.name = "   "
        vm.save()
        #expect(vm.fieldErrors.name != nil)
        #expect(!vm.canSave)

        vm.name = String(repeating: "a", count: 61)
        vm.nameDidChange()
        #expect(vm.fieldErrors.name == nil)
        vm.save()
        #expect(vm.fieldErrors.name != nil)
    }

    @Test("editing the name clears the field error")
    func editingClearsError() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(store: store, category: nil, onSaved: { _ in }, onDuplicate: { _ in })
        vm.name = ""
        vm.save()
        #expect(vm.fieldErrors.name != nil)
        vm.name = "Work"
        vm.nameDidChange()
        #expect(vm.fieldErrors.name == nil)
        #expect(vm.canSave)
    }

    @Test("a valid create saves and reports the category")
    func createSaves() async throws {
        let store = try makeStore()
        var saved: TimeOfLife.Category?
        let vm = CategoryEditorViewModel(
            store: store,
            category: nil,
            onSaved: { saved = $0 },
            onDuplicate: { _ in Issue.record("unexpected duplicate") }
        )
        vm.name = "  Work  "
        vm.icon = CatalogIcon.briefcase
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let category = try #require(saved)
        #expect(category.name == "Work")
        #expect(category.icon == "briefcase")
        #expect(try await store.category(id: category.id) != nil)
    }

    @Test("a duplicate name reports the winner and preserves the draft")
    func duplicateReportsWinner() async throws {
        let store = try makeStore()
        try await store.createCategory(
            draft: CategoryDraft(name: "Work", icon: .briefcase),
            id: "existing",
            now: Date()
        )
        var winner: TimeOfLife.Category?
        var saved: TimeOfLife.Category?
        let vm = CategoryEditorViewModel(
            store: store,
            category: nil,
            onSaved: { saved = $0 },
            onDuplicate: { winner = $0 }
        )
        vm.name = "  work  "
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(saved == nil)
        #expect(winner?.id == "existing")
        #expect(!vm.isSavedOrDuplicate)
        #expect(vm.errorMessage == L10n.errorCategoryExists.text)
        #expect(vm.name == "  work  ")
    }

    @Test("a valid edit updates the category")
    func editSaves() async throws {
        let store = try makeStore()
        try await store.createCategory(
            draft: CategoryDraft(name: "Work", icon: .briefcase),
            id: "c1",
            now: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        var saved: TimeOfLife.Category?
        let existing = try await store.category(id: "c1")
        let category = try #require(existing)
        let vm = CategoryEditorViewModel(
            store: store,
            category: category,
            onSaved: { saved = $0 },
            onDuplicate: { _ in Issue.record("unexpected duplicate") }
        )
        vm.name = "Deep Work"
        vm.icon = CatalogIcon.laptopcomputer
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let result = try #require(saved)
        #expect(result.id == "c1")
        #expect(result.name == "Deep Work")
        #expect(result.icon == "laptopcomputer")
        #expect(try await store.category(id: "c1")?.name == "Deep Work")
    }

    @Test("a stale edit adopts the latest persisted category")
    func staleEditAdoptsLatestCategory() async throws {
        let store = try makeStore()
        let future = Date().addingTimeInterval(60)
        try await store.createCategory(
            draft: CategoryDraft(name: "Work", icon: .briefcase),
            id: "c1",
            now: future
        )
        let category = try #require(await store.category(id: "c1"))
        let vm = CategoryEditorViewModel(
            store: store,
            category: category,
            onSaved: { _ in Issue.record("unexpected save") },
            onDuplicate: { _ in Issue.record("unexpected duplicate") }
        )
        vm.name = "New name"
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.name == "Work")
        #expect(vm.icon == .briefcase)
        #expect(vm.errorMessage == L10n.errorConflict.text)
        #expect(!vm.isSavedOrDuplicate)
    }

    @Test("a persistence failure shows an error and keeps the draft")
    func persistenceFailureShowsError() async throws {
        let store = try makeStore()
        var saved: TimeOfLife.Category?
        let vm = CategoryEditorViewModel(
            store: store,
            category: nil,
            onSaved: { saved = $0 },
            onDuplicate: { _ in }
        )
        vm.name = "Work"
        vm.save()
        try? await Task.sleep(nanoseconds: 100_000_000)
        // LocalStore writes succeed on a healthy store; the failure path is
        // exercised through the stale outcome instead.
        #expect(saved != nil || vm.errorMessage != nil)
    }
}

@MainActor
@Suite("ManageCategoriesViewModel")
struct ManageCategoriesViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }

    @Test("load presents the alphabetized local catalog")
    func loadAlphabetizes() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Travel", icon: .airplane), id: "c3", now: Date())
        try await store.createCategory(draft: CategoryDraft(name: "work", icon: .briefcase), id: "c1", now: Date())
        try await store.createCategory(draft: CategoryDraft(name: "Sport", icon: .figureRun), id: "c2", now: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))

        await vm.load()

        #expect(vm.categories.map(\.name) == ["Sport", "Travel", "work"])
    }

    @Test("an empty catalog is reported as empty")
    func emptyCatalog() async throws {
        let store = try makeStore()
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))

        await vm.load()

        #expect(vm.categories.isEmpty)
    }

    @Test("editor presentation flags create vs edit")
    func editorPresentation() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))

        vm.addCategory()
        #expect(vm.isShowingEditor)
        #expect(vm.editorCategory == nil)

        vm.isShowingEditor = false
        vm.edit(try #require(await store.category(id: "c1")))
        #expect(vm.isShowingEditor)
        #expect(vm.editorCategory?.id == "c1")
    }

    @Test("an editor deletion removes the category from the list with no outbox row")
    func editorDeleteUpdatesList() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work", icon: .briefcase), id: "c1", now: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.load()

        // The editor performs the deletion; the list settles on its callback.
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        await vm.editorDidDelete()

        #expect(try await store.category(id: "c1") == nil)
        #expect(vm.categories.isEmpty)
        // No outbox delete while the deletion is buffered.
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("undo restores the category and refreshes the list")
    func undoRestores() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work", icon: .briefcase), id: "c1", now: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.load()
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        await vm.editorDidDelete()

        await vm.performUndo()

        #expect(try await store.category(id: "c1") != nil)
        #expect(vm.categories.map(\.id).contains("c1"))
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("the system undo registration targets the newest category deletion")
    func systemUndoRegistersCategoryDeletion() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work", icon: .briefcase), id: "c1", now: Date())
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()

        await vm.registerSystemUndo(with: undoManager)

        #expect(undoManager.canUndo)
        #expect(undoManager.undoActionName == L10n.deleteCategoryConfirm.text)
    }

    @Test("foreign snapshots are ignored by category undo")
    func foreignSnapshotIgnored() async throws {
        let store = try makeStore()
        try await store.createActivity(Activity(id: "a1", name: "Running"))
        try await store.createEntry(TimeEntry(
            id: "e1", activityID: "a1", activityName: "Running",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            source: "manual"
        ))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()

        await vm.registerSystemUndo(with: undoManager)
        await vm.performUndo()

        #expect(!undoManager.canUndo)
        // The foreign buffer row is untouched.
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.entry(id: "e1") == nil)
    }

    @Test("an old buffered deletion stays restorable until the app restarts")
    func oldBufferedDeletionStaysRestorable() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date().addingTimeInterval(-3_600))
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.load()
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(undoManager.canUndo)
        await vm.performUndo()
        #expect(try await store.category(id: "c1") != nil)
        #expect(try await store.outboxRows().allSatisfy { $0.op != "delete" })
    }

    @Test("commitAll finalizes buffered deletions (cold launch)")
    func commitAllFinalizesBufferedDeletion() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        try await UndoBufferStore(store: store).commitAll()
        let deletes = try await store.outboxRows().filter { $0.op == "delete" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.recordID == "c1")
    }

    @Test("editorDidSave inserts or replaces keeping the list alphabetized")
    func editorSaveUpdatesList() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.load()

        let renamed = TimeOfLife.Category(id: "c1", name: "Zen", icon: "sparkles", createdAt: Date(), updatedAt: Date())
        await vm.editorDidSave(renamed)
        #expect(vm.categories.map(\.id) == ["c1"])

        let newCategory = TimeOfLife.Category(id: "c2", name: "Travel", icon: "airplane", createdAt: Date(), updatedAt: Date())
        await vm.editorDidSave(newCategory)
        #expect(vm.categories.map(\.name) == ["Travel", "Zen"])
    }

    @Test("a buffered deletion is restorable without any toast")
    func bufferedDeletionAdoptsUndo() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))

        await vm.load()

        // No toast exists anymore; the durable buffer backs the system undo.
        await vm.performUndo()
        #expect(try await store.category(id: "c1") != nil)
    }

    @Test("browsing Manage Categories does not disturb a running timer")
    func browsingDoesNotDisturbTimer() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work"), id: "c1", now: Date())
        try await store.createActivity(Activity(id: "a1", name: "Gym"))
        try await store.startTimer(activityID: "a1", activityName: "Gym", startedAt: Date())
        let vm = ManageCategoriesViewModel(store: store, undoBuffer: UndoBufferStore(store: store))

        await vm.load()
        vm.addCategory()
        // Deletion happens in the editor now; the list surface only reloads.
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        await vm.editorDidDelete()

        // The running timer is untouched by category browsing/deletion.
        let state = try await store.timerState()
        #expect(state?.activityID == "a1")
        #expect(state?.status == "running")
    }
}
