import Foundation
import SwiftUI

/// View model for the shared Activity Editor (Design/SCREENS/
/// ActivityEditor.md), edit mode (refine-selected-activity-from-track
/// change, design decision 3). Accepts the selected Activity, initializes
/// name, notes, and selected Category identifiers from its persisted values,
/// and saves via the atomic `LocalStore.refineActivity` operation. Category
/// selection is zero-or-more and ORDERED (category-management D5/D6); the
/// draft is preserved on an atomic save failure. The caller owns the
/// post-save commit boundary.
@MainActor
final class ActivityEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var notes: String
    /// Ordered multi-selection: selection order is preserved in the saved
    /// Activity's `categoryIDs`.
    @Published var selectedCategoryIDs: [String]
    @Published private(set) var availableCategories: [Category] = []
    @Published private(set) var fieldErrors: FieldErrors
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    /// The maximum notes length in characters.
    static let notesMaxLength = 280

    /// The original Activity identifier being refined.
    let activityID: String

    private let store: LocalStore
    private let onSaved: (Activity) -> Void
    private let onCollision: (Activity) -> Void

    /// The injected store used by the optional in-editor Category creation
    /// sheet.
    var categoryStore: LocalStore { store }

    struct FieldErrors: Equatable {
        var name: String?
        var notes: String?
    }

    init(
        store: LocalStore,
        activity: Activity,
        onSaved: @escaping (Activity) -> Void,
        onCollision: @escaping (Activity) -> Void
    ) {
        self.store = store
        self.activityID = activity.id
        self.name = activity.name
        self.notes = activity.notes ?? ""
        self.selectedCategoryIDs = activity.categoryIDs
        self.fieldErrors = FieldErrors()
        self.onSaved = onSaved
        self.onCollision = onCollision
        Task {
            await reloadCategories()
        }
    }

    /// Refreshes the local Category catalog without changing the draft's
    /// ordered selection. Keeping selected ids intact lets an atomic save
    /// report a disappeared Category and preserve the user's retry context.
    func reloadCategories() async {
        do {
            availableCategories = try await store.categories()
        } catch {
            availableCategories = []
            errorMessage = L10n.errorLocalPersistence.text
        }
    }

    /// True when the draft name is valid and the editor is not saving.
    var canSave: Bool {
        if case .valid = ActivityName.validate(name) { return !isLoading }
        return false
    }

    /// Toggles a category in the ordered selection: selecting appends it at
    /// the end; deselecting removes it, keeping the remaining order.
    func toggleCategory(_ categoryID: String) {
        if let index = selectedCategoryIDs.firstIndex(of: categoryID) {
            selectedCategoryIDs.remove(at: index)
        } else {
            selectedCategoryIDs.append(categoryID)
        }
    }

    /// Selects a newly created Category without disturbing existing order.
    func selectCategory(_ categoryID: String) {
        guard !selectedCategoryIDs.contains(categoryID) else { return }
        selectedCategoryIDs.append(categoryID)
    }

    /// Validates the draft and clears field errors as the user edits.
    func validate() {
        switch ActivityName.validate(name) {
        case .valid:
            fieldErrors.name = nil
        case .empty:
            fieldErrors.name = L10n.timerSearchValidationEmpty.text
        case .tooLong:
            fieldErrors.name = L10n.timerSearchValidationTooLong.text
        }
        if notes.count > Self.notesMaxLength {
            fieldErrors.notes = L10n.activityEditorNotesTooLong.text
        } else {
            fieldErrors.notes = nil
        }
    }

    /// Clears the name field error when the user edits the name.
    func nameDidChange() {
        fieldErrors.name = nil
    }

    /// Clears the notes field error when the user edits the notes.
    func notesDidChange() {
        fieldErrors.notes = nil
    }

    /// Saves the draft locally (atomic refine) and reports the typed outcome
    /// to the caller. The editor stays interactive on failure so the user
    /// can retry with the draft intact.
    func save() {
        validate()
        guard canSave else {
            Haptics.error()
            return
        }
        isLoading = true
        errorMessage = nil
        let draft = ActivityDraft(
            name: ActivityName.normalized(name),
            notes: notes.isEmpty ? nil : notes,
            categoryIDs: selectedCategoryIDs
        )
        Task {
            do {
                let outcome = try await store.refineActivity(
                    id: activityID,
                    draft: draft
                )
                isLoading = false
                switch outcome {
                case let .updated(activity):
                    onSaved(activity)
                case let .collision(existing):
                    onCollision(existing)
                case .missing:
                    errorMessage = L10n.timerStalePreparationError.text
                case .invalid:
                    validate()
                case .invalidAssociation:
                    // The draft is preserved; the user can drop the stale
                    // selection and retry.
                    errorMessage = L10n.activityEditorInvalidAssociation.text
                case .failure:
                    errorMessage = L10n.text(in: .default, code: "error.unknown")
                }
            } catch {
                isLoading = false
                errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }
}
