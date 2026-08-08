import Foundation

/// Temporary Activity-search interaction state (unify-activity-preparation-
/// flow spec, decision 2). Kept separate from the committed `TrackState`:
/// the query, validation, errors, and editor/collision presentation are a
/// draft that never mutates the committed prepared Activity until the user
/// confirms a selection or creation.
struct ActivitySearchState: Equatable {
    /// The raw search-field text (a draft, never committed).
    var query: String = ""
    /// A non-field error surfaced inside the search content (e.g. a local
    /// persistence failure during quick creation).
    var errorMessage: String?
    /// The create-from-Track editor presentation (configured creation).
    var editor: EditorPresentation?
    /// A configured-save name collision awaiting an explicit choice.
    var collision: CollisionPresentation?

    /// The trimmed query.
    var trimmedQuery: String {
        ActivityName.normalized(query)
    }

    /// The validation outcome of the trimmed query.
    var validation: ActivityName.Validation {
        ActivityName.validate(trimmedQuery)
    }

    /// True when the trimmed query is a valid unmatched creation candidate.
    var canCreate: Bool {
        if case .valid = validation { return true }
        return false
    }

    /// The create-from-Track editor presentation.
    struct EditorPresentation: Equatable, Identifiable {
        /// The draft prefilled into the editor (the trimmed query).
        var draft: ActivityDraft
        var id: String { draft.name }
    }

    /// A configured-save name collision awaiting an explicit choice.
    struct CollisionPresentation: Equatable {
        /// The existing winning activity (possibly a pending deletion).
        let existing: Activity
        /// The draft the user was trying to save.
        let draft: ActivityDraft
    }
}
