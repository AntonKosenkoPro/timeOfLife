import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ActivityEditorViewModel")
struct ActivityEditorViewModelTests {
    private func make(connected: Bool = true) -> (
        ActivityEditorViewModel, FakeCatalogRepository, MockCatalogStore, MockConnectivity
    ) {
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let queue = SyncQueue(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
        let undo = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: connected)
        let service = CatalogService(
            store: store, repository: repository, syncQueue: queue,
            undoBuffer: undo, connectivity: connectivity
        )
        let vm = ActivityEditorViewModel(
            mode: .createFromManage, store: store, repository: repository,
            service: service, connectivity: connectivity
        )
        return (vm, repository, store, connectivity)
    }

    @Test("validation does not call the repository")
    func validation() async {
        let (vm, repository, _, _) = make()
        await vm.save()
        #expect(vm.fieldErrors.name == L10n.activityValidationNameEmpty.text)
        #expect(repository.calls.isEmpty)
    }

    @Test("create emits a create result")
    func create() async {
        let (vm, repository, _, _) = make()
        vm.draft.name = "Gym"
        await vm.save()

        #expect(repository.calls.count == 1)
        guard case let .created(activity, linkAndSelect)? = vm.onSaveResult else {
            Issue.record("Expected create result")
            return
        }
        #expect(activity.name == "Gym")
        #expect(!linkAndSelect)
    }

    @Test("edit carries updated_at and adopts the latest version on conflict")
    func editConflict() async {
        let original = TestCatalogFactory.activity(name: "Old")
        let repository = FakeCatalogRepository()
        let store = MockCatalogStore()
        let connectivity = MockConnectivity(connected: true)
        let vm = ActivityEditorViewModel(
            mode: .edit(original), store: store, repository: repository,
            service: makeService(store: store, repository: repository),
            connectivity: connectivity
        )
        let latest = TestCatalogFactory.activity(id: original.id, name: "Latest")
        repository.activityResult = latest
        repository.updateActivityError = CatalogError.conflict(serverUpdatedAt: latest.updatedAt)

        await vm.save()

        #expect(repository.calls.contains {
            if case let .updateActivity(candidate) = $0 {
                return candidate.updatedAt > original.updatedAt
            }
            return false
        })
        #expect(vm.draft.name == "Latest")
        #expect(vm.errorMessage == L10n.errorConflict.text)
    }

    @Test("queues an activity if connectivity drops during an online save")
    func queuesAfterOnlineSaveGoesOffline() async {
        let (vm, repository, store, _) = make()
        repository.createActivityError = CatalogError.offline
        vm.draft.name = "Gym"

        await vm.save()

        #expect(vm.errorMessage == nil)
        #expect(await store.activity(vm.draft.id) != nil)
    }

    @Test("server validation errors map to editor fields")
    func serverValidationErrors() async {
        let (vm, repository, _, _) = make()
        repository.createActivityError = CatalogError.validation(fields: ["notes": "Too long"])
        vm.draft.name = "Gym"

        await vm.save()

        #expect(vm.fieldErrors.notes == "Too long")
    }

    @Test("save prunes category ids that are no longer available")
    func savePrunesDeletedCategories() async {
        let (vm, repository, _, _) = make()
        let available = TestCatalogFactory.category()
        vm.availableCategories = [available]
        vm.draft.name = "Gym"
        vm.draft.categoryIds = [available.id, UUID()]

        await vm.save()

        guard case let .createActivity(activity)? = repository.calls.first else {
            Issue.record("Expected activity create")
            return
        }
        #expect(activity.categoryIds == [available.id])
    }

    @Test("create from manage keeps the editor open on a name collision")
    func manageCreateCollision() async {
        let (vm, repository, _, _) = make()
        repository.createActivityError = CatalogError.activityExists(existingId: UUID(), existingName: "Gym")
        vm.draft.name = "Gym"

        await vm.save()

        #expect(vm.errorMessage == L10n.errorActivityExists.text)
        #expect(vm.onSaveResult == nil)
    }

    @Test("create from timer reuses an activity on activity_exists")
    func timerReuse() async {
        let repository = FakeCatalogRepository()
        let store = MockCatalogStore()
        let connectivity = MockConnectivity(connected: true)
        let existing = TestCatalogFactory.activity(name: "Gym")
        repository.activityResult = existing
        repository.createActivityError = CatalogError.activityExists(
            existingId: existing.id, existingName: existing.name
        )
        let vm = ActivityEditorViewModel(
            mode: .createFromTimer, store: store, repository: repository,
            service: makeService(store: store, repository: repository),
            connectivity: connectivity
        )
        vm.draft.name = "Gym"
        await vm.save()

        guard case let .reused(activity)? = vm.onSaveResult else {
            Issue.record("Expected reuse result")
            return
        }
        #expect(activity == existing)
    }

    @Test("cancel sets the cancelled result and does not call the repository")
    func cancel() async {
        let (vm, repository, _, _) = make()
        vm.cancel()
        #expect(vm.onSaveResult == .cancelled)
        #expect(repository.calls.isEmpty)
    }

    @Test("create from timer emits a create result with the link-and-select signal")
    func createFromTimerLinks() async {
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let connectivity = MockConnectivity(connected: true)
        let vm = ActivityEditorViewModel(
            mode: .createFromTimer, store: store, repository: repository,
            service: makeService(store: store, repository: repository),
            connectivity: connectivity
        )
        vm.draft.name = "Gym"
        await vm.save()

        #expect(repository.calls.count == 1)
        guard case let .created(activity, linkAndSelect)? = vm.onSaveResult else {
            Issue.record("Expected create result")
            return
        }
        #expect(activity.name == "Gym")
        #expect(linkAndSelect)
    }

    private func makeService(store: MockCatalogStore, repository: FakeCatalogRepository) -> CatalogService {
        CatalogService(
            store: store, repository: repository,
            syncQueue: SyncQueue(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)),
            undoBuffer: UndoBuffer(scheduler: .manual),
            connectivity: MockConnectivity(connected: true)
        )
    }
}
