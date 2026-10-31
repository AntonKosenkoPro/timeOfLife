import Foundation

/// Text field a History search term can inspect (history-search spec).
enum HistorySearchField: String, CaseIterable, Hashable, Sendable {
    case name
    case categories
    case notes
}

/// A half-open/closed instant constraint over one entry instant
/// (history-search spec). Lower bounds are always inclusive (`S(d)`,
/// `N(d)`, or an exact timestamp); upper bounds are exclusive for whole
/// local days (`N(d)`) and inclusive for exact timestamps. `nil` is an
/// unbounded side (open ranges). Despite the name this type applies to
/// either the entry start (`started:`) or the entry end (`ended:`); the
/// group records which instant it constrains.
struct HistorySearchStartPredicate: Equatable, Sendable {
    var lower: Date?
    var lowerInclusive: Bool = true
    var upper: Date?
    var upperInclusive: Bool = false

    func matches(_ date: Date) -> Bool {
        if let lower {
            guard date > lower || (lowerInclusive && date == lower) else { return false }
        }
        if let upper {
            guard date < upper || (upperInclusive && date == upper) else { return false }
        }
        return true
    }
}

/// A wall-clock filter over seconds since local midnight `[0, 86400)`
/// (history-search spec, time-of-day requirement). Evaluated against the
/// device-local clock time of the constrained instant, independent of
/// calendar date.
struct HistorySearchClockPredicate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `>=`/`>` a wall-clock instant (operand denotes the start of its
        /// minute or second). Open ranges `A..*` use the inclusive form.
        case atLeast(seconds: Int, inclusive: Bool)
        /// `<=`/`<` a wall-clock instant. Open ranges `*..B` use the
        /// inclusive form.
        case atMost(seconds: Int, inclusive: Bool)
        /// A bare operand: `HH:MM` covers its whole minute (`length` 60),
        /// bare `HH:MM:SS` its exact second (`length` 1).
        /// Half-open `[start, start + length)`.
        case window(start: Int, length: Int)
        /// A closed range, inclusive on both ends. When `upper < lower`
        /// the range wraps across midnight and matches either side.
        case range(lower: Int, upper: Int)
    }

    var kind: Kind

    func matches(wallSeconds: Int) -> Bool {
        switch kind {
        case let .atLeast(seconds, inclusive):
            wallSeconds > seconds || (inclusive && wallSeconds == seconds)
        case let .atMost(seconds, inclusive):
            wallSeconds < seconds || (inclusive && wallSeconds == seconds)
        case let .window(start, length):
            wallSeconds >= start && wallSeconds < start + length
        case let .range(lower, upper):
            if upper >= lower {
                wallSeconds >= lower && wallSeconds <= upper
            } else {
                wallSeconds >= lower || wallSeconds <= upper
            }
        }
    }

    /// Whole wall-clock seconds of an instant in the given timezone.
    /// Gregorian components independent of the UI calendar, so a
    /// non-Gregorian display calendar cannot shift clock filtering.
    static func wallSeconds(of date: Date, timeZone: TimeZone) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let parts = gregorian.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }
}

/// A duration constraint over an entry's resolved length in whole seconds
/// (history-search spec, duration requirement). All bounds are inclusive
/// except strict `>`/`<` comparisons; `nil` is an unbounded side (open
/// ranges). A bare operand sets both bounds to the same exact count.
struct HistorySearchDurationPredicate: Equatable, Sendable {
    var lower: Int?
    var lowerInclusive: Bool = true
    var upper: Int?
    var upperInclusive: Bool = true

    func matches(_ seconds: Int) -> Bool {
        if let lower {
            guard seconds > lower || (lowerInclusive && seconds == lower) else { return false }
        }
        if let upper {
            guard seconds < upper || (upperInclusive && seconds == upper) else { return false }
        }
        return true
    }
}

/// One conjunction (AND group) of a History query: text terms plus the
/// `started:`/`ended:`/`duration:`/`has:` constraints bound to this group
/// (history-search spec, design D2). `in:` scopes stay global on the
/// query, never here.
struct HistorySearchGroup: Equatable, Sendable {
    var textTerms: [String] = []
    var startPredicates: [HistorySearchStartPredicate] = []
    var startClock: [HistorySearchClockPredicate] = []
    var endPredicates: [HistorySearchStartPredicate] = []
    var endClock: [HistorySearchClockPredicate] = []
    var durationPredicates: [HistorySearchDurationPredicate] = []
    /// `has:notes` / `-has:notes`. Both true is a contradiction that
    /// matches nothing (never silently dropped).
    var mustHaveNotes = false
    var mustLackNotes = false
    /// `has:category` / `-has:category`, same contradiction rule.
    var mustHaveCategory = false
    var mustLackCategory = false

    var isEmpty: Bool {
        textTerms.isEmpty && startPredicates.isEmpty && startClock.isEmpty
            && endPredicates.isEmpty && endClock.isEmpty
            && durationPredicates.isEmpty
            && !mustHaveNotes && !mustLackNotes
            && !mustHaveCategory && !mustLackCategory
    }
}

/// A successfully parsed History query (history-search spec, design D2):
/// an alternation (OR) of conjunction (AND) groups with a global union
/// scope. The default scope is names + categories; any explicit `in:`
/// replaces that default. `hasScopeOrStart` is true when the raw query
/// held any qualifier, so scope-only/date-only queries still enter
/// filtered presentation (matching totals) instead of blank History.
struct HistorySearchQuery: Equatable, Sendable {
    var groups: [HistorySearchGroup] = []
    var fields: Set<HistorySearchField> = [.name, .categories]
    var startPredicates: [HistorySearchStartPredicate] {
        groups.flatMap(\.startPredicates)
    }
    var durationPredicates: [HistorySearchDurationPredicate] {
        groups.flatMap(\.durationPredicates)
    }

    var hasScopeOrStart: Bool = false

    /// Every text term across all groups, for highlight/excerpt
    /// derivation (any in-scope occurrence explains a match).
    var textTerms: [String] {
        groups.flatMap(\.textTerms)
    }

    var isFiltering: Bool {
        hasScopeOrStart || groups.contains { !$0.isEmpty }
    }
}

/// A correctable syntax problem. The query text is always preserved for
/// editing; invalid queries show neither unfiltered History nor stale
/// results (history-search spec).
enum HistorySearchDiagnostic: Equatable, Sendable {
    case unknownQualifier(String)
    case unknownScope(String)
    case emptyValue(String)
    case badQuotes
    case badDate(String)
    case badRange(String)
    case badOperator(String)
    case badHas(String)
    case badTime(String)
    case badDuration(String)

    /// Localized explanation. `%@` slots are filled by plain replacement
    /// (never `String(format:)`) so qualifier text containing `%` cannot
    /// corrupt the message.
    var message: String {
        switch self {
        case let .unknownQualifier(token):
            L10n.historySearchErrorUnknown.text.replacingOccurrences(of: "%@", with: token)
        case let .unknownScope(token):
            L10n.historySearchErrorScope.text.replacingOccurrences(of: "%@", with: token)
        case let .emptyValue(token):
            L10n.historySearchErrorEmpty.text.replacingOccurrences(of: "%@", with: token)
        case .badQuotes:
            L10n.historySearchErrorQuote.text
        case let .badDate(token):
            L10n.historySearchErrorDate.text.replacingOccurrences(of: "%@", with: token)
        case let .badRange(token):
            L10n.historySearchErrorRange.text.replacingOccurrences(of: "%@", with: token)
        case let .badOperator(token):
            L10n.historySearchErrorOperator.text.replacingOccurrences(of: "%@", with: token)
        case let .badHas(token):
            L10n.historySearchErrorHas.text.replacingOccurrences(of: "%@", with: token)
        case let .badTime(token):
            L10n.historySearchErrorTime.text.replacingOccurrences(of: "%@", with: token)
        case let .badDuration(token):
            L10n.historySearchErrorDuration.text.replacingOccurrences(of: "%@", with: token)
        }
    }
}

enum HistorySearchParseResult: Equatable, Sendable {
    case blank
    case valid(HistorySearchQuery)
    case invalid(HistorySearchDiagnostic)
}
