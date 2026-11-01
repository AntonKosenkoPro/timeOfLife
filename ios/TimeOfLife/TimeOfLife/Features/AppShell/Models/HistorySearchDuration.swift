import Foundation

/// `duration:` operand parsing for History search (history-search spec,
/// design D3). Operands are one or more contiguous `<integer><unit>`
/// components with units `d` (days), `h` (hours), `m` (minutes), `s`
/// (seconds): components must appear in descending order without repeats
/// (`1h`, `2d5h55m34s`, `2d34s`); skipped units contribute zero. Any other
/// shape is a syntax diagnostic. Comparisons, inclusive ranges, and open
/// ranges mirror `started:`; there is no midnight wrap — a range whose end
/// is smaller than its start is a reversed-range diagnostic.
enum HistorySearchDuration {
    /// Seconds per duration unit, largest first (grammar order).
    private static let units: [(unit: Character, seconds: Int)] = [
        ("d", 86_400),
        ("h", 3_600),
        ("m", 60),
        ("s", 1),
    ]

    /// Parses one `duration:` qualifier operand (after `duration:`) into
    /// duration predicates, or a diagnostic. `key` is `"duration"` for
    /// `emptyValue` copy.
    static func parseQualifier(
        key: String,
        operand: String
    ) -> HistorySearchDurationResult {
        if operand.isEmpty {
            return .invalid(.emptyValue("\(key):"))
        }
        if operand.contains("\"") {
            return .invalid(.badDuration(operand))
        }
        let (comparison, rest) = splitComparison(operand)
        if rest.isEmpty || rest == "*" {
            return .invalid(.badDuration(operand))
        }
        if rest.contains("..") {
            guard comparison == nil else {
                return .invalid(.badDuration(operand))
            }
            return parseRange(operand: operand, rest: rest)
        }
        guard let seconds = parseOperand(rest) else {
            return .invalid(.badDuration(operand))
        }
        return singlePredicate(seconds: seconds, comparison: comparison, operand: operand)
    }

    /// One bare or compared operand: bare means exact-second equality.
    private static func singlePredicate(
        seconds: Int,
        comparison: String?,
        operand: String
    ) -> HistorySearchDurationResult {
        switch comparison {
        case nil:
            let exact = HistorySearchDurationPredicate(lower: seconds, upper: seconds)
            return .predicates([exact])
        case ">=":
            let from = HistorySearchDurationPredicate(lower: seconds, upper: nil)
            return .predicates([from])
        case ">":
            let above = HistorySearchDurationPredicate(lower: seconds, lowerInclusive: false, upper: nil)
            return .predicates([above])
        case "<=":
            let until = HistorySearchDurationPredicate(lower: nil, upper: seconds)
            return .predicates([until])
        case "<":
            let below = HistorySearchDurationPredicate(lower: nil, upper: seconds, upperInclusive: false)
            return .predicates([below])
        default:
            return .invalid(.badDuration(operand))
        }
    }

    private static func splitComparison(_ operand: String) -> (String?, String) {
        guard let prefix = [">=", "<=", ">", "<"].first(where: operand.hasPrefix) else {
            return (nil, operand)
        }
        return (prefix, String(operand.dropFirst(prefix.count)))
    }

    /// Inclusive both-endpoint ranges with no wrap, plus open ends as
    /// one-sided inclusive comparisons. Date/clock shapes fail duration
    /// parsing here, so mixed-kind endpoints are duration diagnostics.
    private static func parseRange(operand: String, rest: String) -> HistorySearchDurationResult {
        let parts = rest.components(separatedBy: "..")
        guard parts.count == 2 else {
            return .invalid(.badRange(operand))
        }
        guard parts != ["*", "*"] else {
            return .invalid(.badRange(operand))
        }
        var lower: Int?
        if parts[0] != "*" {
            lower = parseOperand(parts[0])
        }
        var upper: Int?
        if parts[1] != "*" {
            upper = parseOperand(parts[1])
        }
        guard parts[0] == "*" || lower != nil else {
            return .invalid(.badDuration(operand))
        }
        guard parts[1] == "*" || upper != nil else {
            return .invalid(.badDuration(operand))
        }
        return boundedRange(lower: lower, upper: upper, operand: operand)
    }

    /// Both bounds inclusive; an end smaller than its start is a
    /// reversed-range diagnostic (never midnight wrap).
    private static func boundedRange(
        lower: Int?,
        upper: Int?,
        operand: String
    ) -> HistorySearchDurationResult {
        switch (lower, upper) {
        case let (lower?, upper?):
            guard upper >= lower else {
                return .invalid(.badRange(operand))
            }
            let range = HistorySearchDurationPredicate(lower: lower, upper: upper)
            return .predicates([range])
        case let (lower?, nil):
            let from = HistorySearchDurationPredicate(lower: lower, upper: nil)
            return .predicates([from])
        case let (nil, upper?):
            let until = HistorySearchDurationPredicate(lower: nil, upper: upper)
            return .predicates([until])
        case (nil, nil):
            return .invalid(.badRange(operand))
        }
    }

    /// Parses contiguous `<integer><unit>` components in strictly
    /// descending unit order without repeats. Returns the exact total in
    /// seconds, or nil for any other shape (including overflow).
    static func parseOperand(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        var total = 0
        var lastRank = -1
        var index = text.startIndex
        var parsedAny = false
        while index < text.endIndex {
            guard let (value, next) = readInteger(text, from: index) else { return nil }
            guard next < text.endIndex else { return nil }
            guard let rank = units.firstIndex(where: { $0.unit == text[next] }) else { return nil }
            guard rank > lastRank else { return nil }
            index = text.index(after: next)
            guard let scaled = multiply(value, by: units[rank].seconds) else { return nil }
            guard let added = add(total, scaled) else { return nil }
            total = added
            lastRank = rank
            parsedAny = true
        }
        guard parsedAny else { return nil }
        return total
    }

    /// Reads ASCII digits from `index`; nil when no digits or on overflow.
    private static func readInteger(_ text: String, from index: String.Index) -> (Int, String.Index)? {
        var value = 0
        var digits = 0
        var cursor = index
        while cursor < text.endIndex, let digit = text[cursor].asciiDigit {
            guard let scaled = multiply(value, by: 10), let added = add(scaled, digit) else {
                return nil
            }
            value = added
            digits += 1
            cursor = text.index(after: cursor)
        }
        guard digits > 0 else { return nil }
        return (value, cursor)
    }

    private static func multiply(_ value: Int, by factor: Int) -> Int? {
        let (result, overflowed) = value.multipliedReportingOverflow(by: factor)
        guard !overflowed else { return nil }
        return result
    }

    private static func add(_ lhs: Int, _ rhs: Int) -> Int? {
        let (result, overflowed) = lhs.addingReportingOverflow(rhs)
        guard !overflowed else { return nil }
        return result
    }
}

/// The outcome of parsing one `duration:` qualifier: duration predicates
/// over resolved entry seconds, or a diagnostic.
enum HistorySearchDurationResult {
    case predicates([HistorySearchDurationPredicate])
    case invalid(HistorySearchDiagnostic)
}

private extension Character {
    var asciiDigit: Int? {
        guard isASCII, let value = asciiValue else { return nil }
        guard value >= 48, value <= 57 else { return nil }
        return Int(value - 48)
    }
}
