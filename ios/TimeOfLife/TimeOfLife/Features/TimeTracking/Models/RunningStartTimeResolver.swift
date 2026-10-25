import Foundation

/// Pure start-time rules for the running-start editor: the sheet produces
/// a picked wall-clock time, and this resolves it to the draft `startedAt`
/// plus the caption copy. No persistence here — the caller writes through
/// `TimerService`/`TrackViewModel`, which own the validity gate.
enum RunningStartTimeResolver {
    /// Backdate preset offsets, minutes (the "started a while ago" band).
    static let backPresetOffsetsMinutes = [30, 15]
    /// Forward preset offsets, minutes (nudge the start later, e.g. after
    /// overshooting with a back preset). Always clamped at now — a start
    /// can never be in the future.
    static let forwardPresetOffsetsMinutes = [15, 30]

    /// Resolves a picked time to the new draft start: floors to the minute
    /// and folds future times to yesterday (the wheel is time-only, so a
    /// time later than now can only mean the prior day). The result is
    /// always `<= now`, so callers apply the spec gate by construction.
    static func resolve(picked: Date, now: Date, calendar: Calendar = .current) -> Date {
        let floored = floorToMinute(picked, calendar: calendar)
        if floored > now {
            return calendar.date(byAdding: .day, value: -1, to: floored) ?? floored
        }
        return floored
    }

    /// True when the start falls on a prior calendar day (the caption then
    /// uses the localized yesterday form; the picker itself stays
    /// time-only).
    static func isYesterday(_ start: Date, now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(start, inSameDayAs: now)
    }

    /// The caption line for a running start (`Started 14:20`, or the
    /// localized yesterday form for overnight runs).
    static func caption(
        for startedAt: Date,
        now: Date,
        calendar: Calendar = .current,
        timeText: (Date) -> String
    ) -> String {
        let time = timeText(startedAt)
        if isYesterday(startedAt, now: now, calendar: calendar) {
            return String(format: L10n.timerStartedYesterday.text, locale: .current, time)
        }
        return String(format: L10n.timerStartedAt.text, locale: .current, time)
    }

    /// Case-preserving minute floor (seconds dropped, LogTime precedent).
    static func floorToMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: comps) ?? date
    }
}
