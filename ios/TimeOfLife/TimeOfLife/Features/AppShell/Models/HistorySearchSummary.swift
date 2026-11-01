import Foundation

/// Pure History result-summary derivation (history-search spec, section 11).
/// Parse once per query, derive once per entry/snapshot — never in row
/// bodies (design D1/D5). The view model reads these through its published
/// groups, so the summary needs no stored state of its own.
enum HistorySearchSummary {
    /// Combined known-duration seconds across the matched entries:
    /// entries without a known duration (in-progress) contribute zero —
    /// the same rule as day-group totals.
    static func totalSeconds(_ entries: [TimeEntry]) -> Int {
        entries.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    /// Localized result-summary text: pluralized match count plus the
    /// combined known-duration total in the given locale, using the same
    /// duration formatting as day totals. Returns nil for zero matches;
    /// blank/invalid gating is owned by the view model's query state.
    /// - Note: `bundle` is a parameter so tests can pin per-locale
    ///   stringsdicts; production passes the main bundle.
    static func text(
        count: Int,
        totalSeconds: Int,
        locale: Locale = .current,
        bundle: Bundle = .main
    ) -> String? {
        guard count > 0 else { return nil }
        let total = DurationFormatting.natural(totalSeconds, locale: locale)
        let format = NSLocalizedString(
            L10n.historySearchSummary.rawValue,
            bundle: bundle,
            comment: ""
        )
        return String.localizedStringWithFormat(format, count, total)
    }
}
