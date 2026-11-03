import Foundation

/// Day-label and time-text formatting for `HistoryViewModel` (History
/// D3/D5). Split into an extension to keep the view model under the
/// file-length limit; behavior is unchanged.
@MainActor
extension HistoryViewModel {
    /// "Today" / "Yesterday" for the two most recent calendar days, then the
    /// device-locale regional date for older days (D3).
    nonisolated static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        switch dayDistance(from: day, to: now, calendar: calendar) {
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
    /// on every keystroke (history-search perf). Configuration plus the
    /// first use (ICU build) stay under the shared lock, like `timeText`;
    /// all subsequent use is
    /// thread-confined to the caller's derivation, so groups need no
    /// per-label locking. Direct callers keep the one-shot overload above.
    nonisolated static func dayLabel(
        for day: Date,
        now: Date,
        calendar: Calendar,
        formatter: inout DateFormatter?
    ) -> String {
        switch dayDistance(from: day, to: now, calendar: calendar) {
        case 0: return L10n.historyDayToday.text
        case 1: return L10n.historyDayYesterday.text
        default:
            let dateFormatter: DateFormatter
            if let reuse = formatter {
                reuse.calendar = calendar
                dateFormatter = reuse
            } else {
                dateFormatter = formatLock.withLock {
                    let fresh = DateFormatter()
                    fresh.dateStyle = .medium
                    fresh.timeStyle = .none
                    fresh.calendar = calendar
                    // First use (ICU regeneration) stays serialized like `timeText`.
                    _ = fresh.string(from: day)
                    return fresh
                }
            }
            formatter = dateFormatter
            return dateFormatter.string(from: day)
        }
    }

    /// Whole-day distance from `day` to `now` (0 = today, 1 = yesterday).
    /// Single branch point for both `dayLabel` overloads, so a future
    /// day-boundary fix (future dates, DST edges, locale-specific
    /// "today") cannot make direct callers and `makeDayGroups` disagree
    /// on labels.
    nonisolated private static func dayDistance(from day: Date, to now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
    }

    /// Short-time caption ("14:00"). Under a capture override the request
    /// locale/time zone win (same-launch chrome fix); otherwise the shared
    /// process-locale formatter.
    ///
    /// The override branch uses a per-call formatter: the shared static
    /// below is process-wide state, and pinning it to the request locale
    /// without restoring would leak the capture locale into every later
    /// label once the override clears (the fallback branch would keep
    /// rendering with the last request's locale/time zone).
    nonisolated static func timeText(for date: Date) -> String {
        #if SCREENSHOT_CAPTURE
        // The Add-entry frame's pills render through this static helper,
        // which otherwise keeps the stale launch locale/time zone.
        if let locale = ScreenshotLocale.appLocale, let timeZone = ScreenshotLocale.appTimeZone {
            return formatLock.withLock {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.locale = locale
                formatter.timeZone = timeZone
                return formatter.string(from: date)
            }
        }
        #endif
        return formatLock.withLock {
            // Restore process defaults first: a prior capture override (or
            // any future caller that pins this shared formatter) must not
            // leak its locale/time zone into later labels.
            timeFormatter.locale = nil
            timeFormatter.timeZone = nil
            return timeFormatter.string(from: date)
        }
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
