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
    /// always `<= now`, so callers apply the spec gate by construction —
    /// including the astronomically unlikely calendar failure below, which
    /// clamps to `now` instead of leaking a future start.
    static func resolve(picked: Date, now: Date, calendar: Calendar = .current) -> Date {
        let floored = floorToMinute(picked, calendar: calendar)
        guard floored > now else { return floored }
        guard let folded = calendar.date(byAdding: .day, value: -1, to: floored), folded <= now else {
            return now
        }
        return folded
    }

    /// Resolves a wheel pick for an explicit day segment (the editor sheet):
    /// Today rebuilds the pick on today's date (a yesterday-based draft can
    /// never leak through — it either lands today or fails the gate), while
    /// Yesterday applies the wheel's hour/minute to the prior day. Returns
    /// nil when the result would be in the future (Today only — the spec
    /// gate: Done stays disabled, no error text) or unrepresentable.
    /// Yesterday always resolves: any prior-day wall time is in the past.
    static func resolveForDay(picked: Date, yesterday: Bool, now: Date, calendar: Calendar = .current) -> Date? {
        // A failed day computation fails closed (nil → Done stays
        // disabled), never resolving to the wrong day.
        let day: Date
        if yesterday {
            guard let priorDay = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            day = priorDay
        } else {
            day = now
        }
        let comps = calendar.dateComponents([.hour, .minute], from: picked)
        guard let candidate = calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: 0,
            of: day
        ) else { return nil }
        return candidate <= now ? candidate : nil
    }

    /// True when the start falls on a prior calendar day (the caption then
    /// uses the localized yesterday form; the picker itself stays
    /// time-only). Future dates report false — they belong to no prior day
    /// (reachable only under a device clock change; the caption then shows
    /// the today form rather than mislabeling the future as yesterday).
    static func isYesterday(_ start: Date, now: Date, calendar: Calendar = .current) -> Bool {
        start < now && !calendar.isDate(start, inSameDayAs: now)
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
