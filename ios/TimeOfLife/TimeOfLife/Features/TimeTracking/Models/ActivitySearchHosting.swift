import Combine
import Foundation
import SwiftUI

/// Hosts the shared Activity search + quick-create presentation
/// (`ActivitySearchSheet` / `ActivitySearchContentView`), used by Track
/// (timer-capture-experience) and the Log Time sheet (manual-entry).
///
/// The contract mirrors the Track search behavior: the query is a draft
/// that never mutates the host's committed selection until `confirmSearchResult`
/// or `quickCreateFromSearch` commits it; `cancelSearch` abandons the draft.
/// `selectedActivityID` marks the host's committed selection with a
/// checkmark; it is nil while nothing is selected.
@MainActor
protocol ActivitySearchHosting: ObservableObject {
    /// The deterministic result model for the active search content.
    var searchResults: ActivitySearchResults { get }
    /// Draft query binding for the native search field.
    var searchQueryBinding: Binding<String> { get }
    /// The draft search state (query, validation, non-field error).
    var search: ActivitySearchState { get }
    /// The committed selection's activity id, if any.
    var selectedActivityID: String? { get }
    /// A pending-deletion activity awaiting explicit restoration, if any.
    var pendingRestore: Activity? { get }

    func setSearchQuery(_ query: String)
    func activateSearch()
    func cancelSearch()
    func confirmSearchResult(_ activity: Activity)
    func quickCreateFromSearch() async
    func restorePendingDeletion() async
    func dismissPendingRestore()
}
