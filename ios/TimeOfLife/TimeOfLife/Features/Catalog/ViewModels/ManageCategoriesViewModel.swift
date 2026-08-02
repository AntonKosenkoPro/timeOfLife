import Combine
import Foundation

struct CategoryDraft: Equatable, Sendable {
    let id: UUID?
    var name: String
    var color: ActivityColor
    let createdAt: Date

    init(
        name: String,
        color: ActivityColor,
        id: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.color = color
        self.id = id
        self.createdAt = createdAt
    }
}

enum CategoryEditorSheetState: Identifiable, Equatable {
    case create
    case edit(Category)

    var id: UUID {
        switch self {
        case .create:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        case let .edit(category):
            return category.id
        }
    }
}

@MainActor
final class ManageCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published var undoToast: UndoToastState?
    @Published var conflictMessage: String?
    @Published var errorMessage: String?
    @Published var showDeleteConfirm = false {
        didSet {
            if !showDeleteConfirm { pendingDelete = nil }
        }
    }
    @Published var pendingDelete: Category?
    @Published private(set) var isLoading = false
    @Published var editorSheet: CategoryEditorSheetState?

    private let store: CatalogStoring
    private let service: CatalogService
    private let repository: CatalogRepository
    private let undoBuffer: UndoBuffer
    private let connectivity: Connectivity
    private var toastTask: Task<Void, Never>?

    init(
        store: CatalogStoring,
        service: CatalogService,
        repository: CatalogRepository,
        undoBuffer: UndoBuffer,
        connectivity: Connectivity,
        initialCategories: [Category] = []
    ) {
        self.store = store
        self.service = service
        self.repository = repository
        self.undoBuffer = undoBuffer
        self.connectivity = connectivity
        self.categories = Self.sorted(initialCategories)
    }

    func loadCategories() async {
        isLoading = true
        categories = Self.sorted(
            await store.loadCategories().filter { !undoBuffer.heldIds.contains($0.id) }
        )
        isLoading = false
    }

    func openCreate() {
        editorSheet = .create
    }

    func openEdit(_ category: Category) {
        editorSheet = .edit(category)
    }

    @discardableResult
    func saveCategory(_ draft: CategoryDraft) async -> Category? {
        let candidate = Category(
            id: draft.id ?? UUID.v7(),
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: draft.color,
            createdAt: draft.createdAt,
            updatedAt: Date()
        )
        let previous = await store.category(candidate.id)

        do {
            let saved = try await persistCategory(candidate, isCreate: draft.id == nil)
            await loadCategories()
            return saved
        } catch {
            let catalogError = CatalogError.map(error)
            if case .categoryExists = catalogError {
                // Keep the optimistic record until references are remapped to
                // the server's surviving category.
                await handleSaveError(error, candidate: candidate)
                return nil
            } else {
                await rollback(previous, candidateId: candidate.id)
            }
            await handleSaveError(error, candidate: candidate)
            return nil
        }
    }

    func editorDidFinish(_ result: CategorySaveResult) {
        switch result {
        case let .saved(category):
            editorSheet = nil
            conflictMessage = nil
            Task { await reloadAfterEditor(category) }
        case let .reused(category):
            editorSheet = nil
            conflictMessage = L10n.errorCategoryExists.text
            Task { await reloadAfterEditor(category) }
        case let .conflict(category):
            conflictMessage = L10n.errorConflict.text
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index] = category
            } else {
                categories.append(category)
                categories = Self.sorted(categories)
            }
        case .cancelled:
            editorSheet = nil
        }
    }

    func confirmDelete(_ category: Category) {
        guard pendingDelete == nil else { return }
        pendingDelete = category
        showDeleteConfirm = true
    }

    func confirmDeletePending() async {
        guard let category = pendingDelete else { return }
        await confirmDeletePending(category)
    }

    func confirmDeletePending(_ category: Category) async {
        pendingDelete = nil
        showDeleteConfirm = false

        categories.removeAll { $0.id == category.id }
        undoBuffer.record(.category(category))
        errorMessage = nil
        showUndoToast()
    }

    func performUndo() async {
        guard undoBuffer.state != .empty else { return }
        guard await service.undo() != nil else {
            errorMessage = L10n.errorUndoFailed.text
            return
        }

        await loadCategories()
        toastTask?.cancel()
        toastTask = nil
        undoToast = nil
        errorMessage = nil
    }

    func dismissUndo() {
        toastTask?.cancel()
        toastTask = nil
        undoToast = nil
    }

    func dialogDismissed() {
        if !showDeleteConfirm { pendingDelete = nil }
    }

    func onShake() {
        Task { await performUndo() }
    }

    private func showUndoToast() {
        toastTask?.cancel()
        undoToast = UndoToastState(message: L10n.undoCategoryDeleted.text, startedAt: Date())
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.undoToast = nil }
        }
    }

    private func reloadAfterEditor(_ category: Category) async {
        await store.upsertCategory(category)
        await loadCategories()
    }

    private func persistCategory(_ category: Category, isCreate: Bool) async throws -> Category {
        if isCreate {
            return try await service.createCategory(category)
        } else {
            return try await service.updateCategory(category)
        }
    }

    private func rollback(_ previous: Category?, candidateId: UUID) async {
        if let previous {
            await store.upsertCategory(previous)
        } else {
            await store.removeCategory(candidateId)
        }
    }

    private func handleSaveError(_ error: Error, candidate: Category) async {
        switch CatalogError.map(error) {
        case .conflict:
            if let latest = try? await repository.getCategory(candidate.id) {
                await store.upsertCategory(latest)
                categories = Self.sorted(
                    await store.loadCategories().filter { !undoBuffer.heldIds.contains($0.id) }
                )
            }
            conflictMessage = L10n.errorConflict.text
        case let .categoryExists(existingId, existingName):
            let survivor = try? await repository.getCategory(existingId)
            let replacement = survivor ?? Category(
                id: existingId,
                name: existingName,
                color: candidate.color,
                createdAt: candidate.createdAt,
                updatedAt: candidate.updatedAt
            )
            await store.upsertCategory(replacement)
            if replacement.id != candidate.id {
                await store.replaceCategoryReferences(from: candidate.id, to: replacement.id)
                await store.removeCategory(candidate.id)
            }
            conflictMessage = L10n.errorCategoryExists.text
            await loadCategories()
        case let .validation(fields):
            errorMessage = fields["name"] ?? L10n.text(in: .default, code: "validation_error")
        default:
            errorMessage = ErrorLocalization.message(for: CatalogError.map(error))
        }
    }

    private static func sorted(_ categories: [Category]) -> [Category] {
        categories.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
            return order == .orderedAscending
        }
    }
}
