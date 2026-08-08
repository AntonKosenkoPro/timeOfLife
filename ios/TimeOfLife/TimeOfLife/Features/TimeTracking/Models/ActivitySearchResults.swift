import Foundation

/// The deterministic result model for the Track Activity search content
/// (unify-activity-preparation-flow spec, decision 3/7). Derived from the
/// query, the recency-ordered catalog, and any non-expired pending-deletion
/// identity:
///
/// 1. Empty query: the complete catalog in recency order.
/// 2. Non-empty query: case-insensitive containment matches in recency order.
/// 3. Exact normalized match: identified first, all creation actions
///    suppressed.
/// 4. Valid unmatched query: quick-create and configure-create actions after
///    existing partial matches — unless a non-expired pending-deletion
///    identity matches, in which case a restore action replaces creation.
/// 5. Invalid query: existing search results stay available, creation is
///    suppressed, and localized validation guidance is shown.
///
/// The empty catalog is a presentation state of the same model, not a
/// separate alert.
enum ActivitySearchResults: Equatable {
    /// The query is empty: browse the complete catalog.
    case browsing([Activity])
    /// The query is non-empty: filtered matches, optionally with an exact
    /// match identified first, a creation candidate, and/or a restorable
    /// pending-deletion identity.
    case searching(Searching)

    struct Searching: Equatable {
        /// Case-insensitive containment matches in recency order.
        let matches: [Activity]
        /// The exact normalized match, when one exists (creation is then
        /// suppressed).
        let exactMatch: Activity?
        /// The valid unmatched creation candidate (trimmed query), when the
        /// query is valid, has no exact match, and no pending-deletion
        /// identity matches.
        let creationCandidate: String?
        /// A non-expired pending-deletion activity whose normalized name
        /// matches the query, when no exact match exists. The restore
        /// action replaces creation for this identity.
        let pendingDeletion: Activity?
        /// The validation outcome of the trimmed query (`.valid` when the
        /// query is a creation candidate).
        let validation: ActivityName.Validation
    }

    /// Derives the result model from the query, the recency-ordered catalog,
    /// and the non-expired pending-deletion identity (nil when none matches).
    static func derive(
        query: String,
        activities: [Activity],
        pendingDeletion: Activity? = nil
    ) -> ActivitySearchResults {
        let trimmed = ActivityName.normalized(query)
        guard !trimmed.isEmpty else {
            return .browsing(activities)
        }
        let matches = activities.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        let exactMatch = activities.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        let validation = ActivityName.validate(trimmed)
        let creationCandidate: String?
        if exactMatch == nil, pendingDeletion == nil, case .valid = validation {
            creationCandidate = trimmed
        } else {
            creationCandidate = nil
        }
        return .searching(Searching(
            matches: matches,
            exactMatch: exactMatch,
            creationCandidate: creationCandidate,
            pendingDeletion: pendingDeletion,
            validation: validation
        ))
    }
}
