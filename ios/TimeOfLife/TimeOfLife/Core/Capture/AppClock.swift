import Foundation

/// An explicit bundle of app-owned time inputs (screenshot-capture seam).
///
/// Production uses `.live` (real clock, current calendar), so default behavior
/// is unchanged; the capture composition injects a pinned reference instead.
/// Threaded explicitly through view-model and view initialization — never a
/// global or singleton — so the seam stays bounded (design §3).
struct AppClock {
    /// App-owned "now" (ticker seeds, elapsed math, start/stop anchors).
    var now: () -> Date
    /// Calendar (with locale and time zone) for grouping, intervals, labels.
    var calendar: Calendar

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    /// Production clock: real time, current calendar.
    static var live: AppClock { AppClock() }

    /// Locale for durations/labels (calendar locale, else process locale).
    var locale: Locale { calendar.locale ?? Locale.current }
}
