import Foundation

/// Day-label and time-text formatting for `HistoryViewModel` (History
/// D3/D5). Split into an extension to keep the view model under the
/// file-length limit; behavior is unchanged.
@MainActor
extension HistoryViewModel {
    /// "Today" / "Yesterday" for the two most recent calendar days, then the
    /// device-locale regional date for older days (D3).
    nonisolated static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
        switch days {
        case 0: return L10n.historyDayToday.text
        case 1: return L10n.historyDayYesterday.text
        default:
            // Serialized (see formatLock): NSDateFormatter — including the
            // ICU data loading behind first use — is not thread-safe, and
            // these helpers are reachable from any thread. Live TestFlight
            // crash: icu::UnicodeString ctor via -[NSDateFormatter
            // _regenerateFormatter] on exactly this path.
            return formatLock.withLock {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                formatter.calendar = calendar
                return formatter.string(from: day)
            }
        }
    }

    /// Grouped-derivation overload of `dayLabel` with a caller-owned
    /// reusable formatter: `makeDayGroups` passes one box per call instead
    /// of building a `DateFormatter` (ICU data load) per non-recent group
    /// on every keystroke (history-search perf). Creation stays under the
    /// shared lock (ICU first-use, see above); all subsequent use is
    /// thread-confined to the caller's derivation, so groups need no
    /// per-label locking. Direct callers keep the one-shot overload above.
    nonisolated static func dayLabel(
        for day: Date,
        now: Date,
        calendar: Calendar,
        formatter: inout DateFormatter?
    ) -> String {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
        switch days {
        case 0: return L10n.historyDayToday.text
        case 1: return L10n.historyDayYesterday.text
        default:
            let dateFormatter: DateFormatter = formatter ?? formatLock.withLock {
                let fresh = DateFormatter()
                fresh.dateStyle = .medium
                fresh.timeStyle = .none
                return fresh
            }
            formatter = dateFormatter
            dateFormatter.calendar = calendar
            return dateFormatter.string(from: day)
        }
    }

    /// Short-time caption ("14:00").
    nonisolated static func timeText(for date: Date) -> String {
        formatLock.withLock { timeFormatter.string(from: date) }
    }

    /// Serializes every NSDateFormatter touch in this type (see dayLabel).
    /// Never held across awaits.
    nonisolated private static let formatLock = NSLock()

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
