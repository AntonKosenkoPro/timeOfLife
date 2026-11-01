import Foundation

/// `started:`/`ended:` operand parsing for History search
/// (history-search spec, design D3). Strict Gregorian ASCII notation:
/// date-only operands identify device-local calendar days (`S(d)`/`N(d)`
/// via calendar day arithmetic, never 24-hour math); full-second
/// timestamps with `Z` or an explicit offset identify absolute instants;
/// `HH:MM`/`HH:MM:SS` operands filter device-local wall-clock time on
/// any date.
enum HistorySearchDates {
    static func parseTimeQualifier(
        key: String,
        operand: String,
        gregorian: Calendar
    ) -> HistorySearchTimeResult {
        if operand.isEmpty {
            return .invalid(.emptyValue("\(key):"))
        }
        if operand.contains("\"") {
            return .invalid(.badDate(operand))
        }
        let (comparison, rest) = splitComparison(operand)
        if rest.isEmpty || rest == "*" {
            return .invalid(.badDate(operand))
        }
        if rest.contains("..") {
            guard comparison == nil else {
                return .invalid(.badDate(operand))
            }
            return parseRange(operand: operand, rest: rest, gregorian: gregorian)
        }
        if HistorySearchDates.isClockOperand(rest) {
            guard let clock = HistorySearchDates.parseClockOperand(rest) else {
                return .invalid(.badTime(operand))
            }
            return .clock([clock.predicate(comparison: comparison)])
        }
        guard let bound = parseOperand(rest, gregorian: gregorian) else {
            return .invalid(.badDate(operand))
        }
        guard let comparison else {
            return .instant([bound.barePredicate()])
        }
        guard let predicate = bound.comparisonPredicate(comparison) else {
            return .invalid(.badDate(operand))
        }
        return .instant([predicate])
    }

    private static func splitComparison(_ operand: String) -> (String?, String) {
        guard let prefix = [">=", "<=", ">", "<"].first(where: operand.hasPrefix) else {
            return (nil, operand)
        }
        return (prefix, String(operand.dropFirst(prefix.count)))
    }

    private static func parseRange(
        operand: String,
        rest: String,
        gregorian: Calendar
    ) -> HistorySearchTimeResult {
        let parts = rest.components(separatedBy: "..")
        guard parts.count == 2 else {
            return .invalid(.badRange(operand))
        }
        guard parts != ["*", "*"] else {
            return .invalid(.badRange(operand))
        }
        let lowerIsClock = parts[0] != "*" && HistorySearchDates.isClockOperand(parts[0])
        let upperIsClock = parts[1] != "*" && HistorySearchDates.isClockOperand(parts[1])
        let lowerIsInstant = parts[0] != "*" && !lowerIsClock
        let upperIsInstant = parts[1] != "*" && !upperIsClock
        // Clock endpoints pair only with clock endpoints; date and
        // timestamp endpoints pair with each other by their own rules.
        if (lowerIsClock || upperIsClock) && (lowerIsInstant || upperIsInstant) {
            return .invalid(.badRange(operand))
        }
        if lowerIsClock || upperIsClock {
            return HistorySearchDates.parseClockRange(operand: operand, parts: parts)
        }
        var lower: Date?
        if parts[0] != "*" {
            guard let bound = parseOperand(parts[0], gregorian: gregorian) else {
                return .invalid(.badDate(operand))
            }
            lower = bound.rangeLower
        }
        var upper: Date?
        var upperInclusive = false
        if parts[1] != "*" {
            guard let bound = parseOperand(parts[1], gregorian: gregorian) else {
                return .invalid(.badDate(operand))
            }
            upper = bound.inclusiveUpper.date
            upperInclusive = bound.inclusiveUpper.inclusive
        }
        if let lower, let upper,
           lower > upper || (!upperInclusive && lower == upper) {
            // A date-derived upper endpoint is exclusive (`N(d)`), so
            // equality against it is also a reversal: `2026-10-02..2026-10-01`
            // yields `lower == S(Oct 2) == N(Oct 1)`. Inclusive (timestamp)
            // equality stays valid — a zero-width instant range.
            return .invalid(.badRange(operand))
        }
        let predicate = HistorySearchStartPredicate(
            lower: lower,
            lowerInclusive: true,
            upper: upper,
            upperInclusive: upperInclusive
        )
        return .instant([predicate])
    }

    // MARK: - Date/timestamp operands

    /// A validated date-only or timestamp operand with its spec boundary
    /// meanings. Date bounds carry both `S(d)` and `N(d)`; timestamps carry
    /// the exact instant.
    private enum StartBound {
        case day(start: Date, next: Date)
        case instant(Date)

        /// `>=` lower and range lower: `S(d)` for dates, the instant.
        var rangeLower: Date {
            switch self {
            case let .day(start, _):
                start
            case let .instant(instant):
                instant
            }
        }

        /// `>` lower: `N(d)` (inclusive) for dates, the exact instant
        /// (exclusive) for timestamps.
        var strictLower: (date: Date, inclusive: Bool) {
            switch self {
            case let .day(_, next):
                (next, true)
            case let .instant(instant):
                (instant, false)
            }
        }

        /// `<` upper: `S(d)` for dates, the instant for timestamps.
        var rangeUpper: Date {
            switch self {
            case let .day(start, _):
                start
            case let .instant(instant):
                instant
            }
        }

        /// `<=` and range upper: `N(d)` (exclusive) for dates, the instant
        /// (inclusive) for timestamps.
        var inclusiveUpper: (date: Date, inclusive: Bool) {
            switch self {
            case let .day(_, next):
                (next, false)
            case let .instant(instant):
                (instant, true)
            }
        }

        func barePredicate() -> HistorySearchStartPredicate {
            switch self {
            case let .day(start, next):
                HistorySearchStartPredicate(lower: start, upper: next)
            case let .instant(instant):
                HistorySearchStartPredicate(
                    lower: instant,
                    lowerInclusive: true,
                    upper: instant,
                    upperInclusive: true
                )
            }
        }

        func comparisonPredicate(_ comparison: String) -> HistorySearchStartPredicate? {
            switch comparison {
            case ">=":
                HistorySearchStartPredicate(lower: rangeLower, upper: nil)
            case ">":
                HistorySearchStartPredicate(
                    lower: strictLower.date,
                    lowerInclusive: strictLower.inclusive,
                    upper: nil
                )
            case "<":
                HistorySearchStartPredicate(upper: rangeUpper, upperInclusive: false)
            case "<=":
                HistorySearchStartPredicate(
                    upper: inclusiveUpper.date,
                    upperInclusive: inclusiveUpper.inclusive
                )
            default:
                nil
            }
        }
    }

    /// Strict ASCII `YYYY-MM-DD` (Gregorian, device timezone) or
    /// `YYYY-MM-DDTHH:MM:SSZ|±HH:MM`. Timezone-less datetimes, missing
    /// seconds, and fractional seconds are rejected.
    private static func parseOperand(
        _ text: String,
        gregorian: Calendar
    ) -> StartBound? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 10, isDatePrefix(scalars) else { return nil }
        guard let year = asciiInt(scalars[0 ..< 4]) else { return nil }
        guard let month = asciiInt(scalars[5 ..< 7]), (1 ... 12).contains(month) else { return nil }
        guard let day = asciiInt(scalars[8 ..< 10]), (1 ... 31).contains(day) else { return nil }
        guard scalars.count != 10 else {
            return dayBound(year: year, month: month, day: day, gregorian: gregorian)
        }
        guard scalars.count > 11, scalars[10] == "T" else { return nil }
        guard let instant = parseTimestamp(
            year: year,
            month: month,
            day: day,
            tail: String(text.dropFirst(11))
        ) else { return nil }
        return .instant(instant)
    }

    private static func dayBound(
        year: Int,
        month: Int,
        day: Int,
        gregorian: Calendar
    ) -> StartBound? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = gregorian.date(from: comps) else { return nil }
        let check = gregorian.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        let start = gregorian.startOfDay(for: date)
        guard let next = gregorian.date(byAdding: .day, value: 1, to: start) else { return nil }
        return .day(start: start, next: next)
    }

    private static func isDatePrefix(_ scalars: [Unicode.Scalar]) -> Bool {
        scalars[4] == "-" && scalars[7] == "-"
            && scalars[0].isASCIIDigit && scalars[1].isASCIIDigit
            && scalars[2].isASCIIDigit && scalars[3].isASCIIDigit
            && scalars[5].isASCIIDigit && scalars[6].isASCIIDigit
            && scalars[8].isASCIIDigit && scalars[9].isASCIIDigit
    }

    private static func asciiInt(_ scalars: ArraySlice<Unicode.Scalar>) -> Int? {
        var value = 0
        for scalar in scalars {
            guard scalar.isASCIIDigit else { return nil }
            value = value * 10 + Int(scalar.value - Unicode.Scalar("0").value)
        }
        return value
    }

    private static func parseTimestamp(
        year: Int,
        month: Int,
        day: Int,
        tail: String
    ) -> Date? {
        // `HH:MM:SS` + `Z` or `±HH:MM`: exactly 8 + 1 or 8 + 6 chars.
        let chars = Array(tail)
        guard chars.count == 9 || chars.count == 14 else { return nil }
        guard chars[2] == ":", chars[5] == ":" else { return nil }
        guard let hour = twoDigits(chars[0], chars[1]), (0 ... 23).contains(hour) else { return nil }
        guard let minute = twoDigits(chars[3], chars[4]), (0 ... 59).contains(minute) else {
            return nil
        }
        guard let second = twoDigits(chars[6], chars[7]), (0 ... 59).contains(second) else {
            return nil
        }
        guard let offsetSeconds = parseZone(chars: chars) else { return nil }
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        guard let wallClock = gmt.date(from: comps) else { return nil }
        let check = gmt.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wallClock
        )
        guard check.year == year, check.month == month, check.day == day else { return nil }
        guard check.hour == hour, check.minute == minute, check.second == second else { return nil }
        return wallClock.addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    private static func parseZone(chars: [Character]) -> Int? {
        if chars.count == 9 {
            guard chars[8] == "Z" else { return nil }
            return 0
        }
        guard chars[8] == "+" || chars[8] == "-" else { return nil }
        guard chars[11] == ":" else { return nil }
        guard let offHour = twoDigits(chars[9], chars[10]) else { return nil }
        guard let offMinute = twoDigits(chars[12], chars[13]) else { return nil }
        guard (0 ... 23).contains(offHour), (0 ... 59).contains(offMinute) else { return nil }
        let magnitude = offHour * 3600 + offMinute * 60
        return chars[8] == "+" ? magnitude : -magnitude
    }

    static func twoDigits(_ first: Character, _ second: Character) -> Int? {
        guard let high = first.asciiDigit, let low = second.asciiDigit else { return nil }
        return high * 10 + low
    }
}

/// The outcome of parsing one `started:`/`ended:` qualifier: instant
/// bounds, wall-clock filters, or a diagnostic.
enum HistorySearchTimeResult {
    /// One qualifier's instant or clock predicates (a single qualifier
    /// always yields one kind; multiple qualifiers AND together).
    enum Predicates {
        case instant([HistorySearchStartPredicate])
        case clock([HistorySearchClockPredicate])
    }

    case instant([HistorySearchStartPredicate])
    case clock([HistorySearchClockPredicate])
    case invalid(HistorySearchDiagnostic)
}

private extension Character {
    var asciiDigit: Int? {
        guard isASCII, let value = asciiValue else { return nil }
        guard value >= 48, value <= 57 else { return nil }
        return Int(value - 48)
    }
}

private extension Unicode.Scalar {
    var isASCIIDigit: Bool {
        value >= 48 && value <= 57
    }
}
