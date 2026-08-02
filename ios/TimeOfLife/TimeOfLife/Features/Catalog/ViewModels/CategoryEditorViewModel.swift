import Combine
import Foundation

enum CategoryEditorMode: Equatable, Sendable {
    case create
    case edit(Category)
}

enum CategorySaveResult: Equatable, Sendable {
    case saved(Category)
    case reused(Category)
    case conflict(Category)
    case cancelled
}

struct CategoryFieldErrors: Equatable, Sendable {
    var name: String?

    init(name: String? = nil) {
        self.name = name
    }

    static let empty = CategoryFieldErrors()
}

@MainActor
final class CategoryEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var color: ActivityColor
    @Published private(set) var fieldErrors = CategoryFieldErrors.empty
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var onSaveResult: CategorySaveResult?

    let mode: CategoryEditorMode
    let id: UUID
    let createdAt: Date

    private let store: CatalogStoring
    private let repository: CatalogRepository
    private let service: CatalogService
    private let connectivity: Connectivity

    init(
        mode: CategoryEditorMode,
        store: CatalogStoring,
        repository: CatalogRepository,
        service: CatalogService,
        connectivity: Connectivity,
        now: Date = Date()
    ) {
        self.mode = mode
        self.store = store
        self.repository = repository
        self.service = service
        self.connectivity = connectivity

        switch mode {
        case .create:
            id = UUID.v7()
            name = ""
            color = .mint
            createdAt = now
        case let .edit(category):
            id = category.id
            name = category.name
            color = category.color
            createdAt = category.createdAt
        }
    }

    func clearNameError() {
        fieldErrors.name = nil
        errorMessage = nil
    }

#if DEBUG
    func setPreviewValidation() {
        fieldErrors.name = CategoryValidator.unifiedNameMessage(
            CategoryValidator.validateName(name)
        )
    }

    func setPreviewLoading() {
        isLoading = true
    }
#endif

    func cancel() {
        guard !isLoading else { return }
        onSaveResult = .cancelled
    }

    func save() async {
        guard !isLoading else { return }
        fieldErrors = CategoryFieldErrors(
            name: CategoryValidator.unifiedNameMessage(
                CategoryValidator.validateName(name)
            )
        )
        guard fieldErrors == .empty else {
            Haptics.error()
            return
        }

        let candidate = Category(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            createdAt: createdAt,
            updatedAt: Date()
        )

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let saved = try await persist(candidate)
            onSaveResult = .saved(saved)
            Haptics.success()
        } catch {
            if case .categoryExists = CatalogError.map(error) {
                await handle(error, candidate: candidate)
            } else {
                await rollback(candidate)
                await handle(error, candidate: candidate)
            }
        }
    }

    private func persist(_ candidate: Category) async throws -> Category {
        switch mode {
        case .create:
            return try await service.createCategory(candidate)
        case .edit:
            return try await service.updateCategory(candidate)
        }
    }

    private func handle(_ error: Error, candidate: Category) async {
        let catalogError = CatalogError.map(error)
        switch catalogError {
        case let .validation(fields):
            fieldErrors.name = fields["name"]
        case .conflict:
            if let latest = await adoptServerVersion() {
                errorMessage = L10n.errorConflict.text
                onSaveResult = .conflict(latest)
            } else {
                errorMessage = L10n.errorConflict.text
            }
        case let .categoryExists(existingId, existingName):
            let survivor = await resolveCategory(
                id: existingId,
                name: existingName,
                fallback: candidate
            )
            await store.upsertCategory(survivor)
            if survivor.id != candidate.id {
                await store.replaceCategoryReferences(from: candidate.id, to: survivor.id)
                await store.removeCategory(candidate.id)
            }
            onSaveResult = .reused(survivor)
        case .offline:
            errorMessage = L10n.text(in: .default, code: "offline")
        default:
            errorMessage = ErrorLocalization.message(for: catalogError)
        }
    }

    private func rollback(_ candidate: Category) async {
        if case let .edit(existing) = mode {
            await store.upsertCategory(existing)
        } else {
            await store.removeCategory(candidate.id)
        }
    }

    private func adoptServerVersion() async -> Category? {
        guard let category = try? await repository.getCategory(id) else { return nil }
        name = category.name
        color = category.color
        await store.upsertCategory(category)
        return category
    }

    private func resolveCategory(id: UUID, name: String, fallback: Category) async -> Category {
        if let category = try? await repository.getCategory(id) {
            return category
        }
        return Category(
            id: id,
            name: name,
            color: fallback.color,
            createdAt: fallback.createdAt,
            updatedAt: fallback.updatedAt
        )
    }
}
