import SwiftUI

// MARK: - Search states (history-search)

/// Correctable syntax state: the query stays for editing, no rows show,
/// and a compact static example accompanies the diagnostic (not a
/// suggestion list). No pull gesture here — results lists own the
/// sync-only pull.
struct InvalidSearchState: View {
    let diagnostic: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(diagnostic)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("HistorySearchError")
                Text(L10n.historySearchHint.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.backgroundPrimary)
    }
}

/// Valid query, zero matches: distinct from both the empty-History state
/// and the syntax state, with a clear-query action. No pull gesture.
///
/// The clear action keeps the retired compact-timer slot as bottom
/// keyboard clearance (remove-compact-timer deleted the view; the slot
/// reservation stays so the search chrome keeps its pinned clearance).
struct NoMatchingEntriesState: View {
    let clear: () -> Void

    /// The retired compact timer's surface height. A named constant — not
    /// an inline literal — so the clearance below and its test pin the same
    /// value instead of restating independent `62`s that could drift apart.
    static let retiredCompactTimerSurface: CGFloat = 62
    /// Bottom padding reserving the compact-timer slot above the keyboard:
    /// the timer surface plus its top/bottom inset gaps. A single shared
    /// constant (not inline arithmetic) so tests pin the invariant — the
    /// clear action reserves the compact-timer slot — instead of restating
    /// the formula.
    static let timerAbsentClearance: CGFloat = retiredCompactTimerSurface + Theme.spacingExtraSmall * 2

    var body: some View {
        VStack(spacing: 0) {
            EmptyState(
                icon: "magnifyingglass",
                title: L10n.historySearchNoResults.text,
                subtitle: L10n.historySearchNoResultsSubtitle.text
            )
            Button(L10n.historySearchClear.text, action: clear)
                .buttonStyle(.bordered)
                .padding(.top, Theme.spacingSmall)
                .accessibilityIdentifier("HistorySearchClear")
        }
        .padding(.bottom, Self.timerAbsentClearance)
    }
}

/// Scrolling result summary above the first result group (history-search
/// spec, Design/COMPONENTS.md): pluralized match count plus the combined
/// known-duration total. A plain list row — never a pinned header — so it
/// scrolls with the results. Rendered only when the view model publishes a
/// summary (valid non-empty queries with at least one match).
struct SearchResultSummary: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("HistorySearchSummary")
    }
}
