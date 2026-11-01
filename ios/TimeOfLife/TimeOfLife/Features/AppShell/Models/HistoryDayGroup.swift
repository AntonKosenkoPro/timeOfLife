import Foundation

/// Day-grouped view data for the History list (history-entry-list spec).
struct DayGroup: Identifiable, Equatable {
    /// Stable identifier for the calendar day (e.g. "2026-09-03").
    let id: String
    /// Relative ("Today" / "Yesterday") or absolute regional day label.
    let label: String
    /// The day's entries, newest first.
    let entries: [TimeEntry]
    /// Natural-language sum of the day's known durations (e.g. "2h 35m").
    /// Entries with no duration (in-progress) contribute zero (D8).
    let total: String
}
