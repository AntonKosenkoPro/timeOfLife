import Foundation
import Testing
@testable import TimeOfLife

@MainActor
@Suite("CategoryEditorViewModel")
struct CategoryEditorViewModelTests {
    private func make(connected: Bool = true) -> (
        CategoryEditorViewModel,
        FakeCatalogRepository,
        MockCatalogStore,
        SyncQueue
    ) {
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let queue = SyncQueue(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife-")
                .appendingPathComponent(UUID().uuidString)
        )
        let undoBuffer = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: connected)
        let service = CatalogService(
            store: store,
            repository: repository,
            syncQueue: queue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        let viewModel = CategoryEditorViewModel(
            mode: .create,
            store: store,
            repository: repository,
            service: service,
            connectivity: connectivity
        )
        return (viewModel, repository, store, queue)
    }

    @Test("create sends a v7 category and reports success")
    func createSuccess() async {
        let (viewModel, repository, store, _) = make()
        viewModel.name = "Gym"
        await viewModel.save()

        guard case let .saved(category)? = viewModel.onSaveResult else {
            Issue.record("Expected category save result")
            return
        }
        #expect(category.name == "Gym")
        #expect(category.id.uuidString.count == 36)
        #expect(repository.calls.contains {
            if case let .createCategory(candidate) = $0 { return candidate == category }
            return false
        })
        #expect(await store.category(category.id) == category)
    }

    @Test("edit sends a newer updated_at and pre-fills the draft")
    func editSuccess() async {
        let original = TestCatalogFactory.category(name: "Old")
        let (_, repository, store, _) = make()
        await store.upsertCategory(original)
        let editor = CategoryEditorViewModel(
            mode: .edit(original),
            store: store,
            repository: repository,
            service: makeService(store: store, repository: repository),
            connectivity: MockConnectivity(connected: true)
        )
        editor.name = "New"
        await editor.save()

        #expect(editor.name == "New")
        #expect(repository.calls.contains {
            if case let .updateCategory(candidate) = $0 {
                return candidate.id == original.id && candidate.updatedAt > original.updatedAt
            }
            return false
        })
    }

    @Test("empty and long names use unified validation messages")
    func validation() async {
        let (viewModel, repository, _, _) = make()
        await viewModel.save()
        #expect(viewModel.fieldErrors.name == L10n.activityValidationNameEmpty.text)
        #expect(repository.calls.isEmpty)

        viewModel.name = String(repeating: "x", count: 61)
        await viewModel.save()
        #expect(viewModel.fieldErrors.name == L10n.validationNamePrefix.text + " " + L10n.validationNameRuleTooLong.text + ".")
    }

    @Test("server validation maps to the name field")
    func serverValidation() async {
        let (viewModel, repository, _, _) = make()
        repository.createCategoryError = CatalogError.validation(fields: ["name": "Use another name"])
        viewModel.name = "Gym"
        await viewModel.save()

        #expect(viewModel.fieldErrors.name == "Use another name")
    }

    @Test("conflict adopts the server version and keeps the editor open")
    func conflictAdoptsLatest() async {
        let original = TestCatalogFactory.category(name: "Old")
        let latest = TestCatalogFactory.category(id: original.id, name: "Latest")
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        repository.categoryResult = latest
        repository.updateCategoryError = CatalogError.conflict(serverUpdatedAt: latest.updatedAt)
        let connectivity = MockConnectivity(connected: true)
        let viewModel = CategoryEditorViewModel(
            mode: .edit(original),
            store: store,
            repository: repository,
            service: makeService(store: store, repository: repository),
            connectivity: connectivity
        )
        viewModel.name = "Mine"
        await viewModel.save()

        #expect(viewModel.name == "Latest")
        #expect(viewModel.errorMessage == L10n.errorConflict.text)
        #expect(viewModel.onSaveResult == .conflict(latest))
        #expect(await store.category(original.id) == latest)
    }

    @Test("category collision returns the surviving category")
    func categoryExistsReusesSurvivor() async {
        let survivor = TestCatalogFactory.category(name: "Gym")
        let (viewModel, repository, store, _) = make()
        let activity = TestCatalogFactory.activity(categoryIds: [viewModel.id])
        await store.upsertActivity(activity)
        repository.categoryResult = survivor
        repository.createCategoryError = CatalogError.categoryExists(
            existingId: survivor.id,
            existingName: survivor.name
        )
        viewModel.name = "Gym"
        await viewModel.save()

        #expect(viewModel.onSaveResult == .reused(survivor))
        #expect(await store.category(survivor.id) == survivor)
        #expect(await store.activity(activity.id)?.categoryIds == [survivor.id])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("offline create is persisted locally and queued")
    func offlineCreate() async {
        let (viewModel, _, store, queue) = make(connected: false)
        viewModel.name = "Gym"
        await viewModel.save()

        #expect(await store.category(viewModel.id) != nil)
        let pending = await queue.pending()
        #expect(pending.contains { $0.method == .create && $0.resource == .category })
    }

    private func makeService(store: MockCatalogStore, repository: FakeCatalogRepository) -> CatalogService {
        CatalogService(
            store: store,
            repository: repository,
            syncQueue: SyncQueue(
                url: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("TimeOfLife-")
                    .appendingPathComponent(UUID().uuidString)
            ),
            undoBuffer: UndoBuffer(scheduler: .manual),
            connectivity: MockConnectivity(connected: true)
        )
    }
}
