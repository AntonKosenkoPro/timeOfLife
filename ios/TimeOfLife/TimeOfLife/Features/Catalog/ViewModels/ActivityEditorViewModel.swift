import Foundation
import SwiftUI

/// View model for the shared Activity Editor (Design/SCREENS/
/// ActivityEditor.md), create-from-Track mode (unify-activity-preparation-
/// flow spec, decision 5). Holds the draft, field validation, and the
/// local-first save outcome; the Track search coordinator owns the commit
/// boundary (preparing the saved Activity without starting timing).
@MainActor
final class ActivityEditorViewModel: ObservableObject {
    @Published var name: String
    @Published var notes: String
    @Published var selectedCategoryIDs: Set<String>
    @Published private(set) var availableCategories: [Category] = []
    @Published private(set) var fieldErrors: FieldErrors
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    /// The maximum notes length in characters.
    static let notesMaxLength = 280

    private let store: LocalStore
    private let onSaved: (Activity) -> Void
    private let onCollision: (Activity, ActivityDraft) -> Void

    struct FieldErrors: Equatable {
        var name: String?
        var notes: String?
    }

    init(
        store: LocalStore,
        prefilledName: String,
        onSaved: @escaping (Activity) -> Void,
        onCollision: @escaping (Activity, ActivityDraft) -> Void
    ) {
        self.store = store
        self.name = prefilledName
        self.notes = ""
        self.selectedCategoryIDs = []
        self.fieldErrors = FieldErrors()
        self.onSaved = onSaved
        self.onCollision = onCollision
        Task {
            self.availableCategories = (try? await store.categories()) ?? []
        }
    }

    /// True when the draft name is valid and the editor is not saving.
    var canSave: Bool {
        if case .valid = ActivityName.validate(name) { return !isLoading }
        return false
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

    /// Saves the draft locally (create-or-resolve) and reports the typed
    /// outcome to the Track search coordinator. The editor stays interactive
    /// on failure so the user can retry.
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
            categoryIDs: selectedCategoryIDs.sorted()
        )
        Task {
            do {
                let outcome = try await store.createOrResolveActivity(
                    named: draft.name,
                    notes: draft.notes,
                    categoryIDs: draft.categoryIDs
                )
                isLoading = false
                switch outcome {
                case let .created(activity), let .existing(activity):
                    onSaved(activity)
                case let .restorableDeletion(activity):
                    onCollision(activity, draft)
                case .invalid:
                    validate()
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
