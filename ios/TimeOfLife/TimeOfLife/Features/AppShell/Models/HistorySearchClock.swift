import Foundation

// MARK: - Wall-clock operands (history-search spec, time-of-day requirement)

extension HistorySearchDates {
    /// An operand containing `:` but no `T` is a wall-clock attempt:
    /// timestamps always carry `T`, dates never carry `:`. Anything else
    /// follows the date/timestamp path.
    static func isClockOperand(_ text: String) -> Bool {
        text.contains(":") && !text.contains("T")
    }

    /// A validated `HH:MM`/`HH:MM:SS` operand: whole wall-clock seconds
    /// since local midnight plus whether the operand named a minute
    /// (bare `HH:MM` covers all 60 seconds) or a second.
    struct ClockOperand {
        var seconds: Int
        var isMinute: Bool

        /// A bare operand's match window: the whole minute, or the exact
        /// second. Comparisons use the operand as an exact wall-clock
        /// instant (the start of its minute/second).
        func predicate(comparison: String?) -> HistorySearchClockPredicate {
            switch comparison {
            case ">=":
                HistorySearchClockPredicate(kind: .atLeast(seconds: seconds, inclusive: true))
            case ">":
                HistorySearchClockPredicate(kind: .atLeast(seconds: seconds, inclusive: false))
            case "<=":
                HistorySearchClockPredicate(kind: .atMost(seconds: seconds, inclusive: true))
            case "<":
                HistorySearchClockPredicate(kind: .atMost(seconds: seconds, inclusive: false))
            default:
                HistorySearchClockPredicate(kind: .window(
                    start: seconds,
                    length: isMinute ? 60 : 1
                ))
            }
        }
    }

    /// Strict 24-hour `HH:MM` (`00:00`–`23:59`) or `HH:MM:SS` (seconds
    /// `00`–`59`). Single-digit hours, out-of-range values, and any other
    /// shape are rejected.
    static func parseClockOperand(_ text: String) -> ClockOperand? {
        let chars = Array(text)
        guard chars.count == 5 || chars.count == 8 else { return nil }
        guard chars[2] == ":" else { return nil }
        guard let hour = twoDigits(chars[0], chars[1]), (0 ... 23).contains(hour) else { return nil }
        guard let minute = twoDigits(chars[3], chars[4]), (0 ... 59).contains(minute) else {
            return nil
        }
        if chars.count == 5 {
            return ClockOperand(seconds: hour * 3600 + minute * 60, isMinute: true)
        }
        guard chars[5] == ":" else { return nil }
        guard let second = twoDigits(chars[6], chars[7]), (0 ... 59).contains(second) else {
            return nil
        }
        return ClockOperand(seconds: hour * 3600 + minute * 60 + second, isMinute: false)
    }

    /// A both-endpoint clock range: exact inclusive wall-clock intervals.
    /// An end earlier than the start wraps across midnight (matches
    /// either side); open ends become inclusive one-sided comparisons.
    static func parseClockRange(operand: String, parts: [String]) -> HistorySearchTimeResult {
        var lower: Int?
        if parts[0] != "*" {
            guard let bound = parseClockOperand(parts[0]) else {
                return .invalid(.badTime(operand))
            }
            lower = bound.seconds
        }
        var upper: Int?
        if parts[1] != "*" {
            guard let bound = parseClockOperand(parts[1]) else {
                return .invalid(.badTime(operand))
            }
            upper = bound.seconds
        }
        switch (lower, upper) {
        case let (lower?, upper?):
            return .clock([HistorySearchClockPredicate(kind: .range(lower: lower, upper: upper))])
        case let (lower?, nil):
            return .clock([HistorySearchClockPredicate(kind: .atLeast(seconds: lower, inclusive: true))])
        case let (nil, upper?):
            return .clock([HistorySearchClockPredicate(kind: .atMost(seconds: upper, inclusive: true))])
        case (nil, nil):
            return .invalid(.badRange(operand))
        }
    }
}
