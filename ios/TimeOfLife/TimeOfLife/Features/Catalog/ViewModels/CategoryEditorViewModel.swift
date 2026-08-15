import Foundation

/// View model for the shared Category Editor (Design/SCREENS/
/// CategoryEditor.md, category-management D4): create/edit modes with a
/// preserved draft, field-level validation, duplicate and persistence
/// errors, and stale-conflict adoption. Saving goes through the atomic
/// `LocalStore` category mutations (single chokepoint).
@MainActor
final class CategoryEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var icon: CatalogIcon
    @Published private(set) var fieldErrors: FieldErrors
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isCreateMode: Bool
    /// True after a successful save, so the view can dismiss itself. Duplicate
    /// and stale outcomes keep this false so the draft remains actionable.
    @Published private(set) var isSavedOrDuplicate = false

    /// The id of the category being edited (nil in create mode).
    let categoryID: String?

    private let store: LocalStore
    private let onSaved: (Category) -> Void
    private let onDuplicate: (Category) -> Void

    struct FieldErrors: Equatable {
        var name: String?
    }

    init(
        store: LocalStore,
        category: Category?,
        onSaved: @escaping (Category) -> Void,
        onDuplicate: @escaping (Category) -> Void
    ) {
        self.store = store
        self.categoryID = category?.id
        self.isCreateMode = category == nil
        self.name = category?.name ?? ""
        self.icon = CatalogIcon(validated: category?.icon ?? "") // "" → tag default
        self.fieldErrors = FieldErrors()
        self.onSaved = onSaved
        self.onDuplicate = onDuplicate
    }

    /// True when the draft name is valid and the editor is not saving.
    var canSave: Bool {
        if case .valid = CategoryName.validate(name) { return !isLoading }
        return false
    }

    /// Validates the draft, collapsing rules into one message per field (U2).
    func validate() {
        switch CategoryName.validate(name) {
        case .valid:
            fieldErrors.name = nil
        case .empty:
            fieldErrors.name = L10n.categoryNameRequired.text
        case .tooLong:
            fieldErrors.name = L10n.categoryNameTooLong.text
        }
    }

    /// Clears the name field error as the user edits.
    func nameDidChange() {
        fieldErrors.name = nil
    }

    /// Saves the draft through the atomic LocalStore mutation. On success the
    /// caller dismisses the editor; on duplicate the caller surfaces the
    /// localized conflict and the draft stays available.
    func save() {
        validate()
        guard canSave else {
            Haptics.error()
            return
        }
        isLoading = true
        errorMessage = nil
        let draft = CategoryDraft(name: name, icon: icon)
        Task {
            do {
                let outcome: LocalStore.CategoryMutation
                if let categoryID {
                    outcome = try await store.updateCategory(id: categoryID, draft: draft)
                } else {
                    outcome = try await store.createCategory(
                        draft: draft,
                        id: store.newRecordID()
                    )
                }
                isLoading = false
                switch outcome {
                case let .saved(category):
                    isSavedOrDuplicate = true
                    onSaved(category)
                case let .duplicate(winner):
                    errorMessage = L10n.errorCategoryExists.text
                    onDuplicate(winner)
                case .invalid:
                    validate()
                case .stale, .missing:
                    await adoptLatestCategory()
                case .failure:
                    errorMessage = L10n.errorLocalPersistence.text
                }
            } catch {
                isLoading = false
                errorMessage = L10n.errorLocalPersistence.text
            }
        }
    }

    /// Adopts the current local version after a stale edit so the user sees
    /// the winning values and can make another explicit change.
    private func adoptLatestCategory() async {
        guard let categoryID else {
            errorMessage = L10n.errorConflict.text
            return
        }
        do {
            guard let latest = try await store.category(id: categoryID) else {
                errorMessage = L10n.errorConflict.text
                return
            }
            name = latest.name
            icon = CatalogIcon(validated: latest.icon)
            fieldErrors = FieldErrors()
            errorMessage = L10n.errorConflict.text
        } catch {
            errorMessage = L10n.errorConflict.text
        }
    }
}
