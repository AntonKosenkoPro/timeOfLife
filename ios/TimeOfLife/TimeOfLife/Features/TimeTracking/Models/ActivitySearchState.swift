import Foundation

/// Temporary Activity-search interaction state (unify-activity-preparation-
/// flow spec, decision 2; refine-selected-activity-from-track change removes
/// configured creation). Kept separate from the committed `TrackState`:
/// the query, validation, and errors are a draft that never mutates the
/// committed prepared Activity until the user confirms a selection or
/// creation. Track-owned refinement presentation lives on `TrackViewModel`,
/// not here.
struct ActivitySearchState: Equatable {
    /// The raw search-field text (a draft, never committed).
    var query: String = ""
    /// A non-field error surfaced inside the search content (e.g. a local
    /// persistence failure during quick creation).
    var errorMessage: String?

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
}
