import Foundation

/// The period scoping an Insights breakdown (insights-breakdown spec).
/// `today` covers the calendar day containing now (start-of-day to
/// start-of-next-day, so future-dated manual entries count by `startedAt`
/// with no special-casing); `week` covers the locale week interval
/// containing now; `all` is unbounded.
enum InsightsPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case all

    var id: String { rawValue }

    /// Localized segment label.
    var label: String {
        switch self {
        case .today: return L10n.insightsPeriodToday.text
        case .week: return L10n.insightsPeriodWeek.text
        case .all: return L10n.insightsPeriodAll.text
        }
    }

    /// The per-period empty sentence shown when the period holds no committed
    /// entries. Nil for `all` — its empty state is the true-zero placeholder.
    var emptyText: String? {
        switch self {
        case .today: return L10n.insightsEmptyToday.text
        case .week: return L10n.insightsEmptyWeek.text
        case .all: return nil
        }
    }

    /// The `startedAt` interval included in this period, or nil when
    /// unbounded (`all`).
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: DateComponents(day: 1), to: start)
                ?? start.addingTimeInterval(86400)
            return DateInterval(start: start, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .all:
            return nil
        }
    }
}

/// The breakdown key (insights-breakdown spec): per-category rows with
/// full-credit attribution, or per-activity rows that sum to the hero total.
enum InsightsLens: String, CaseIterable, Identifiable, Sendable {
    case category
    case activity

    var id: String { rawValue }

    /// Localized segment label.
    var label: String {
        switch self {
        case .category: return L10n.insightsLensCategory.text
        case .activity: return L10n.insightsLensActivity.text
        }
    }
}

/// One breakdown row: the summed duration plus the contributing entry ids.
/// The id sets cost nothing now and are what v2 overlap work (shared-hours,
/// stacked segments, combination rows) builds on without store changes.
struct InsightsBucket: Identifiable, Equatable, Sendable {
    /// Category id, activity id, or `uncategorizedID` (never collides: real
    /// ids are UUID v7).
    static let uncategorizedID = "uncategorized"

    let id: String
    let name: String
    /// Validated SF Symbol for the leading icon.
    let icon: String
    let totalSeconds: Int
    /// Contributing entry ids, sorted for determinism.
    let entryIDs: [String]
}

/// A computed breakdown: the unique committed total (hero) plus rows.
/// Category-lens rows may sum above the hero (full-credit overlap); the
/// activity lens always sums to it.
struct InsightsBreakdown: Equatable, Sendable {
    let totalSeconds: Int
    /// Biggest total first, ties broken by name for determinism.
    let rows: [InsightsBucket]
}
