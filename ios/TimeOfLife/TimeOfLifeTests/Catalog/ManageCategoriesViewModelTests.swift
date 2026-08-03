import Foundation
import Testing
@testable import TimeOfLife

@MainActor
@Suite("ManageCategoriesViewModel")
struct ManageCategoriesViewModelTests {
    private func make() -> (
        ManageCategoriesViewModel,
        MockCatalogStore,
        FakeCatalogRepository,
        SyncQueue,
        UndoBuffer
    ) {
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let queue = SyncQueue(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife-")
                .appendingPathComponent(UUID().uuidString)
        )
        let undoBuffer = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: true)
        let service = CatalogService(
            store: store,
            repository: repository,
            syncQueue: queue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        let viewModel = ManageCategoriesViewModel(
            store: store,
            service: service,
            repository: repository,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        return (viewModel, store, repository, queue, undoBuffer)
    }

    @Test("loads categories from the local store in locale-aware alpha order")
    func loadsAlphaSortedWithoutNetwork() async {
        let (viewModel, store, repository, _, _) = make()
        await store.upsertCategory(TestCatalogFactory.category(name: "zoo"))
        await store.upsertCategory(TestCatalogFactory.category(name: "Alpha"))
        await store.upsertCategory(TestCatalogFactory.category(name: "beta"))

        await viewModel.loadCategories()

        #expect(viewModel.categories.map(\.name) == ["Alpha", "beta", "zoo"])
        #expect(repository.calls.isEmpty)
    }

    @Test("saveCategory applies create and edit mutations optimistically")
    func savesCreateAndEdit() async {
        let (viewModel, store, repository, _, _) = make()
        let created = await viewModel.saveCategory(
            CategoryDraft(name: "Work", icon: .briefcase)
        )
        guard let created else {
            Issue.record("Expected category create")
            return
        }
        #expect(await store.category(created.id) == created)
        #expect(repository.calls.contains {
            if case let .createCategory(candidate) = $0 { return candidate.name == "Work" }
            return false
        })

        let updated = await viewModel.saveCategory(
            CategoryDraft(name: "Office", icon: .briefcase, id: created.id, createdAt: created.createdAt)
        )
        #expect(updated?.name == "Office")
        #expect(repository.calls.contains {
            if case let .updateCategory(candidate) = $0 {
                return candidate.id == created.id && candidate.updatedAt > created.updatedAt
            }
            return false
        })
    }

    @Test("delete holds the category and its activity tags until expiry")
    func deleteHoldsCategoryAndJoinReferences() async {
        let (viewModel, store, _, queue, undoBuffer) = make()
        let category = TestCatalogFactory.category()
        let activity = TestCatalogFactory.activity(categoryIds: [category.id])
        await store.upsertCategory(category)
        await store.upsertActivity(activity)
        await viewModel.loadCategories()

        viewModel.confirmDelete(category)
        await viewModel.confirmDeletePending()

        #expect(viewModel.categories.isEmpty) // Hidden immediately in the UI.
        #expect(await store.category(category.id) == category)
        #expect(await store.activity(activity.id)?.categoryIds == [category.id])
        #expect(await queue.pending().isEmpty)
        guard case .holding(.category(category), expiresAt: _) = undoBuffer.state else {
            Issue.record("Expected category deletion to be held for undo")
            return
        }
    }

    @Test("undo restores the category tag without enqueueing a mutation")
    func undoRestoresJoinReferences() async {
        let (viewModel, store, _, queue, _) = make()
        let category = TestCatalogFactory.category()
        let activity = TestCatalogFactory.activity(categoryIds: [category.id])
        await store.upsertCategory(category)
        await store.upsertActivity(activity)
        await viewModel.loadCategories()

        viewModel.confirmDelete(category)
        await viewModel.confirmDeletePending()
        await viewModel.performUndo()

        #expect(viewModel.categories == [category])
        #expect(await store.activity(activity.id)?.categoryIds == [category.id])
        #expect(await queue.pending().isEmpty)
        #expect(viewModel.undoToast == nil)
    }

    @Test("undo after leaving the categories screen preserves activity tags")
    func undoAfterLeavingScreenPreservesTags() async {
        let (viewModel, store, _, _, undoBuffer) = make()
        let category = TestCatalogFactory.category()
        let activity = TestCatalogFactory.activity(categoryIds: [category.id])
        await store.upsertCategory(category)
        await store.upsertActivity(activity)
        await viewModel.loadCategories()

        viewModel.confirmDelete(category)
        await viewModel.confirmDeletePending()

        // The shared undo buffer may be consumed after this view is popped.
        let restored = undoBuffer.undo()
        if case let .category(restoredCategory)? = restored {
            await store.upsertCategory(restoredCategory)
        } else {
            Issue.record("Expected held category")
        }

        #expect(await store.category(category.id) == category)
        #expect(await store.activity(activity.id)?.categoryIds == [category.id])
    }

    @Test("expiry commits a hard delete and enqueues DELETE")
    func expiryCommitsDelete() async {
        let (viewModel, store, _, queue, undoBuffer) = make()
        let category = TestCatalogFactory.category()
        await store.upsertCategory(category)
        await viewModel.loadCategories()

        viewModel.confirmDelete(category)
        await viewModel.confirmDeletePending()
        await undoBuffer.commit(now: Date().addingTimeInterval(31))

        #expect(await store.category(category.id) == nil)
        #expect(await queue.pending().contains { $0.resource == .category && $0.method == .delete })
    }

    @Test("conflict adopts the server category and shows a banner")
    func conflictKeepsLatest() async {
        let (viewModel, store, repository, _, _) = make()
        let original = TestCatalogFactory.category(name: "Old")
        let latest = TestCatalogFactory.category(id: original.id, name: "Latest")
        repository.updateCategoryError = CatalogError.conflict(serverUpdatedAt: latest.updatedAt)
        repository.categoryResult = latest
        await store.upsertCategory(original)

        let result = await viewModel.saveCategory(
            CategoryDraft(name: "Mine", icon: original.icon, id: original.id, createdAt: original.createdAt)
        )

        #expect(result == nil)
        #expect(viewModel.conflictMessage == L10n.errorConflict.text)
        #expect(await store.category(original.id) == latest)
    }

    @Test("category collision replaces the local category references")
    func categoryExistsReusesSurvivor() async {
        let (viewModel, store, repository, _, _) = make()
        let candidate = TestCatalogFactory.category(name: "Gym")
        let survivor = TestCatalogFactory.category(name: "Gym")
        repository.updateCategoryError = CatalogError.categoryExists(
            existingId: survivor.id,
            existingName: survivor.name
        )
        repository.categoryResult = survivor
        let activity = TestCatalogFactory.activity(categoryIds: [candidate.id])
        await store.upsertActivity(activity)

        let result = await viewModel.saveCategory(
            CategoryDraft(name: candidate.name, icon: candidate.icon, id: candidate.id, createdAt: candidate.createdAt)
        )

        #expect(result == nil)
        #expect(viewModel.conflictMessage == L10n.errorCategoryExists.text)
        #expect(await store.category(candidate.id) == nil)
        #expect(await store.category(survivor.id) == survivor)
        #expect(await store.activity(activity.id)?.categoryIds == [survivor.id])
    }

    @Test("dialog dismissal clears the pending category")
    func dialogDismissalClearsPending() async {
        let (viewModel, store, _, _, _) = make()
        let category = TestCatalogFactory.category()
        await store.upsertCategory(category)

        viewModel.confirmDelete(category)
        #expect(viewModel.pendingDelete == category)
        viewModel.showDeleteConfirm = false

        #expect(viewModel.pendingDelete == nil)
    }
}
