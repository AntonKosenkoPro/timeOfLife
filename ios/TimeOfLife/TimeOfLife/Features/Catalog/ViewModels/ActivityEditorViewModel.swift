import Foundation

enum ActivityEditorMode: Equatable, Sendable {
    case createFromManage
    case createFromTimer
    case edit(Activity)
}

struct ActivityDraft: Equatable, Sendable {
    let id: UUID
    var name: String
    var color: ActivityColor
    var icon: String
    var notes: String
    var categoryIds: Set<UUID>
    var lastUsedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(mode: ActivityEditorMode, now: Date = Date()) {
        switch mode {
        case let .edit(activity):
            id = activity.id
            name = activity.name
            color = activity.color
            icon = activity.icon.rawValue
            notes = activity.notes ?? ""
            categoryIds = Set(activity.categoryIds)
            lastUsedAt = activity.lastUsedAt
            createdAt = activity.createdAt
            updatedAt = activity.updatedAt
        case .createFromManage, .createFromTimer:
            id = UUID.v7()
            name = ""
            color = .mint
            icon = ActivityIcon.default.rawValue
            notes = ""
            categoryIds = []
            lastUsedAt = nil
            createdAt = now
            updatedAt = now
        }
    }

    func activity() -> Activity? {
        guard let icon = ActivityIcon(rawValue: icon) else { return nil }
        return Activity(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            icon: icon,
            notes: notes.isEmpty ? nil : notes,
            lastUsedAt: lastUsedAt,
            categoryIds: categoryIds.sorted { $0.uuidString < $1.uuidString },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    mutating func adopt(_ activity: Activity) {
        name = activity.name
        color = activity.color
        icon = activity.icon.rawValue
        notes = activity.notes ?? ""
        categoryIds = Set(activity.categoryIds)
        lastUsedAt = activity.lastUsedAt
        updatedAt = activity.updatedAt
    }
}

struct ActivityFieldErrors: Equatable, Sendable {
    var name: String?
    var notes: String?
    var color: String?
    var icon: String?

    init(name: String? = nil, notes: String? = nil, color: String? = nil, icon: String? = nil) {
        self.name = name
        self.notes = notes
        self.color = color
        self.icon = icon
    }
}

enum ActivitySaveResult: Equatable, Sendable {
    case created(Activity, linkAndSelect: Bool)
    case updated(Activity)
    case reused(Activity)
    case cancelled
}

@MainActor
final class ActivityEditorViewModel: ObservableObject {
    @Published var draft: ActivityDraft
    @Published var fieldErrors = ActivityFieldErrors()
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var availableCategories: [Category]
    @Published var onSaveResult: ActivitySaveResult?

    let mode: ActivityEditorMode
    let shouldFocusName: Bool

    private let store: CatalogStoring
    private let repository: CatalogRepository
    private let service: CatalogService
    private let connectivity: Connectivity

    init(
        mode: ActivityEditorMode,
        store: CatalogStoring,
        repository: CatalogRepository,
        service: CatalogService,
        connectivity: Connectivity,
        availableCategories: [Category] = []
    ) {
        self.mode = mode
        self.draft = ActivityDraft(mode: mode)
        self.store = store
        self.repository = repository
        self.service = service
        self.connectivity = connectivity
        self.availableCategories = availableCategories
        self.shouldFocusName = true
    }

    func loadCategories() async {
        availableCategories = await store.loadCategories()
    }

    func clearNameError() {
        fieldErrors.name = nil
    }

    func clearNotesError() {
        fieldErrors.notes = nil
    }

    func cancel() {
        guard !isLoading else { return }
        onSaveResult = .cancelled
    }

    func save() async {
        guard !isLoading else { return }
        fieldErrors = validateDraft()
        guard fieldErrors == ActivityFieldErrors() else {
            Haptics.error()
            return
        }

        let validCategoryIds = Set(availableCategories.map(\.id))
        draft.categoryIds.formIntersection(validCategoryIds)
        if case .edit = mode {
            // The backend accepts a patch only when its LWW timestamp advances.
            draft.updatedAt = Date()
        }
        guard let candidate = draft.activity() else {
            fieldErrors.icon = ActivityValidator.unifiedIconMessage([.iconInvalid])
            Haptics.error()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let saved = try await persist(candidate)
            onSaveResult = result(for: saved)
        } catch {
            await handle(error)
        }
    }

    private func persist(_ candidate: Activity) async throws -> Activity {
        if connectivity.isConnected {
            do {
                let saved = try await persistOnline(candidate)
                await store.upsertActivity(saved)
                return saved
            } catch {
                guard case .offline = CatalogError.map(error) else { throw error }
            }
        }
        return try await persistOffline(candidate)
    }

    private func persistOnline(_ candidate: Activity) async throws -> Activity {
        switch mode {
        case .edit:
            return try await repository.updateActivity(candidate)
        case .createFromManage, .createFromTimer:
            return try await repository.createActivity(candidate)
        }
    }

    private func persistOffline(_ candidate: Activity) async throws -> Activity {
        switch mode {
        case .edit:
            return try await service.updateActivity(candidate)
        case .createFromManage, .createFromTimer:
            return try await service.createActivity(candidate)
        }
    }

    private func result(for saved: Activity) -> ActivitySaveResult {
        switch mode {
        case .edit:
            return .updated(saved)
        case .createFromTimer:
            return .created(saved, linkAndSelect: true)
        case .createFromManage:
            return .created(saved, linkAndSelect: false)
        }
    }

    private func validateDraft() -> ActivityFieldErrors {
        let nameErrors = ActivityValidator.validateName(draft.name)
        let notesErrors = ActivityValidator.validateNotes(draft.notes)
        let colorErrors = ActivityValidator.validateColor(draft.color.rawValue)
        let iconErrors = ActivityValidator.validateIcon(draft.icon)
        return ActivityFieldErrors(
            name: ActivityValidator.unifiedNameMessage(nameErrors),
            notes: ActivityValidator.unifiedNotesMessage(notesErrors),
            color: ActivityValidator.unifiedColorMessage(colorErrors),
            icon: ActivityValidator.unifiedIconMessage(iconErrors)
        )
    }

    private func handle(_ error: Error) async {
        let catalogError = error as? CatalogError ?? CatalogError.map(error)
        switch catalogError {
        case let .validation(fields):
            fieldErrors = ActivityFieldErrors(
                name: fields["name"],
                notes: fields["notes"],
                color: fields["color"],
                icon: fields["icon"]
            )
        case .conflict:
            await adoptServerVersion()
            errorMessage = L10n.errorConflict.text
        case let .activityExists(existingId, existingName):
            let existing = await existingActivity(id: existingId, name: existingName)
            if case .createFromTimer = mode {
                onSaveResult = .reused(existing)
            } else {
                errorMessage = L10n.errorActivityExists.text
            }
        case .offline:
            errorMessage = L10n.text(in: .default, code: "offline")
        default:
            errorMessage = ErrorLocalization.message(for: catalogError)
        }
    }

    private func adoptServerVersion() async {
        guard let server = try? await repository.getActivity(draft.id) else { return }
        draft.adopt(server)
        await store.upsertActivity(server)
    }

    private func existingActivity(id: UUID, name: String) async -> Activity {
        if let activity = try? await repository.getActivity(id) { return activity }
        let now = Date()
        return Activity(
            id: id,
            name: name,
            color: .mint,
            icon: .clock,
            notes: nil,
            lastUsedAt: nil,
            categoryIds: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
