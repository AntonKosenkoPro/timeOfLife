import Foundation

/// Minute-bucketed age of the last sync for Profile's "Last synced" row
/// (fix-sync-status-row, sync-client spec).
///
/// Buckets: under a minute, whole minutes 1–59, whole hours 1–23, whole days
/// with no upper cap (never weeks/months/years). A future timestamp (clock
/// skew) renders as `.justNow` — never future tense.
///
/// Quantity words ("37 minutes", "2 минуты") come from the system quantity
/// formatter, which owns pluralization in every locale; only connective
/// words live in L10n. The helper takes elapsed seconds and glue strings, so
/// it is locale-pure and unit-testable without clocks or bundles.
enum SyncAgeBucket: Equatable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
}

enum SyncRelativeTime {
    /// Maps elapsed seconds to a bucket. No `Date()` inside — callers pass
    /// `now.timeIntervalSince(date)`; negative (future) clamps to `.justNow`.
    static func bucket(elapsed: TimeInterval) -> SyncAgeBucket {
        guard elapsed >= 60 else { return .justNow }
        let minutes = Int(elapsed / 60)
        guard minutes >= 60 else { return .minutes(minutes) }
        let hours = minutes / 60
        guard hours >= 24 else { return .hours(hours) }
        return .days(hours / 24)
    }

    /// Localized quantity for a bucket ("59 minutes", "5 минут").
    /// Restricted `allowedUnits` + `maximumUnitCount = 1` truncate and never
    /// escalate units; the numeric fallback is unreachable defense (exact
    /// multiples of the unit always format).
    static func quantity(for bucket: SyncAgeBucket, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        switch bucket {
        case .justNow:
            return ""
        case let .minutes(count):
            formatter.allowedUnits = [.minute]
            return formatter.string(from: TimeInterval(count * 60)) ?? "\(count)"
        case let .hours(count):
            formatter.allowedUnits = [.hour]
            return formatter.string(from: TimeInterval(count * 3600)) ?? "\(count)"
        case let .days(count):
            formatter.allowedUnits = [.day]
            return formatter.string(from: TimeInterval(count * 86400)) ?? "\(count)"
        }
    }

    /// Full "Last synced: …" title. Glue strings are parameters (view passes
    /// L10n, tests pass literals) so composition is pinnable in any locale.
    static func title(
        since date: Date,
        now: Date,
        outer: String,
        ago: String,
        justNow: String,
        locale: Locale = .current
    ) -> String {
        let bucket = bucket(elapsed: now.timeIntervalSince(date))
        guard case .justNow = bucket else {
            return String(format: outer, String(format: ago, quantity(for: bucket, locale: locale)))
        }
        return String(format: outer, justNow)
    }
}
