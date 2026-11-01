import Testing
import Foundation
@testable import TimeOfLife

/// Wall-clock operands and the `ended:` qualifier for History search
/// (`add-history-search` change, section 12): `HH:MM`/`HH:MM:SS`
/// comparisons, inclusive/open/overnight-wrapping ranges, minute-covering
/// bare `HH:MM`, exact-second bare `HH:MM:SS`, same-kind endpoints, and
/// full `ended:` parity with nil-end entries matching nothing.
@Suite("HistorySearchClock")
struct HistorySearchClockTests {
    private func gmtCalendar() -> Calendar {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        return gmt
    }

    private func parseQuery(
        _ raw: String,
        calendar: Calendar? = nil
    ) throws -> HistorySearchQuery {
        let result = HistorySearchParser.parse(raw, calendar: calendar ?? gmtCalendar())
        guard case .valid(let parsed) = result else {
            throw TestError.expectedValid(raw)
        }
        return parsed
    }

    private enum TestError: Error {
        case expectedValid(String)
    }

    private func clockEntry(
        calendar: Calendar,
        startHour: Int,
        startMinute: Int = 0,
        startSecond: Int = 0,
        endHour: Int? = nil,
        endMinute: Int = 0,
        endSecond: Int = 0,
        name: String = "Walk",
        notes: String = "",
        categories: [String] = []
    ) -> (TimeEntry, [Category]) {
        func date(hour: Int, minute: Int, second: Int, day: Int = 5) -> Date {
            var comps = DateComponents()
            comps.calendar = calendar
            comps.timeZone = calendar.timeZone
            comps.year = 2026
            comps.month = 10
            comps.day = day
            comps.hour = hour
            comps.minute = minute
            comps.second = second
            return comps.date!
        }
        let cats = categories.enumerated().map { index, name in
            Category(id: "c\(index)", name: name, icon: "tag")
        }
        let record = TimeEntry(
            id: "e1",
            activityText: name,
            startedAt: date(hour: startHour, minute: startMinute, second: startSecond),
            endedAt: endHour.map { date(hour: $0, minute: endMinute, second: endSecond) },
            durationSeconds: 60,
            categoryIDs: cats.map(\.id),
            notes: notes
        )
        return (record, cats)
    }

    // MARK: - Clock operand parsing (task 12.2)

    @Test("clock-time operands parse; mixed-kind ranges are diagnostics")
    func clockOperandsAndMixedRanges() {
        for query in [
            "started:18:00", "started:18:00:30", "started:>18:00",
            "started:22:00..02:00", "started:09:00..17:00",
            "started:22:00..*", "started:*..02:00",
            "ended:18:00", "ended:22:00..02:00",
        ] {
            if case .valid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected valid query for \(query)")
            }
        }
        guard case .valid(let wrap) = HistorySearchParser.parse("started:22:00..02:00") else {
            Issue.record("expected valid query")
            return
        }
        #expect(wrap.groups[0].startClock.count == 1)
        for query in ["started:2026-10-01..18:00", "started:18:00..2026-10-01"] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("malformed clock times are diagnostics")
    func badClockTimes() {
        for query in [
            "started:25:00", "started:18:60", "started:18:00:60",
            "started:9:00", "started:18:0", "started:1800",
            "started:18:00:0", "ended:24:00",
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    // MARK: - Ended qualifier (task 12.2)

    @Test("ended: mirrors started: on the entry end, including earlier starts")
    func endedDateRange() throws {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let query = try parseQuery("ended:2026-10-01..2026-10-31", calendar: gmt)
        func bounded(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int) -> TimeEntry {
            func date(month: Int, day: Int) -> Date {
                var comps = DateComponents()
                comps.calendar = gmt
                comps.timeZone = gmt.timeZone
                comps.year = 2026
                comps.month = month
                comps.day = day
                comps.hour = 12
                return comps.date!
            }
            return TimeEntry(
                id: "\(startMonth)-\(startDay)-\(endMonth)-\(endDay)",
                activityText: "Trip",
                startedAt: date(month: startMonth, day: startDay),
                endedAt: date(month: endMonth, day: endDay),
                durationSeconds: 60
            )
        }
        // Starts in September, ends in October: the end decides.
        #expect(HistorySearchEvaluator.matches(
            entry: bounded(startMonth: 9, startDay: 28, endMonth: 10, endDay: 2),
            categories: [], query: query, calendar: gmt
        ))
        #expect(HistorySearchEvaluator.matches(
            entry: bounded(startMonth: 10, startDay: 5, endMonth: 10, endDay: 6),
            categories: [], query: query, calendar: gmt
        ))
        // Ends in November: no match despite an October start.
        #expect(!HistorySearchEvaluator.matches(
            entry: bounded(startMonth: 10, startDay: 5, endMonth: 11, endDay: 1),
            categories: [], query: query, calendar: gmt
        ))
    }

    @Test("entries without an end satisfy no ended: constraint")
    func nilEndMatchesNothing() throws {
        let calendar = gmtCalendar()
        for raw in ["ended:<2999-01-01", "ended:2026-10-01", "ended:>18:00", "ended:22:00..02:00"] {
            let query = try parseQuery(raw, calendar: calendar)
            let (record, _) = clockEntry(calendar: calendar, startHour: 19, endHour: nil)
            #expect(record.endedAt == nil)
            #expect(!HistorySearchEvaluator.matches(
                entry: record, categories: [], query: query, calendar: calendar
            ), "nil end must not match \(raw)")
        }
        // ... while an ended entry at the same start matches the open bound.
        let query = try parseQuery("ended:<2999-01-01", calendar: calendar)
        let (ended, _) = clockEntry(calendar: calendar, startHour: 19, endHour: 20)
        #expect(HistorySearchEvaluator.matches(
            entry: ended, categories: [], query: query, calendar: calendar
        ))
    }

    // MARK: - Clock-time evaluation (task 12.2)

    @Test("evening clock comparisons filter wall time on any date")
    func eveningClockComparisons() throws {
        let calendar = gmtCalendar()
        let strict = try parseQuery("walk started:>18:00", calendar: calendar)
        let (after, _) = clockEntry(calendar: calendar, startHour: 19)
        #expect(HistorySearchEvaluator.matches(entry: after, categories: [], query: strict, calendar: calendar))
        let (exact, _) = clockEntry(calendar: calendar, startHour: 18)
        #expect(!HistorySearchEvaluator.matches(entry: exact, categories: [], query: strict, calendar: calendar))
        let inclusive = try parseQuery("walk started:>=18:00", calendar: calendar)
        #expect(HistorySearchEvaluator.matches(entry: exact, categories: [], query: inclusive, calendar: calendar))
        let (before, _) = clockEntry(calendar: calendar, startHour: 17, startMinute: 59, startSecond: 59)
        #expect(!HistorySearchEvaluator.matches(entry: before, categories: [], query: inclusive, calendar: calendar))
    }

    @Test("bare HH:MM covers its whole minute; bare HH:MM:SS its exact second")
    func bareClockWindows() throws {
        let calendar = gmtCalendar()
        let minute = try parseQuery("started:18:00", calendar: calendar)
        let (early, _) = clockEntry(calendar: calendar, startHour: 18, startMinute: 0, startSecond: 0)
        #expect(HistorySearchEvaluator.matches(entry: early, categories: [], query: minute, calendar: calendar))
        let (late, _) = clockEntry(calendar: calendar, startHour: 18, startMinute: 0, startSecond: 59)
        #expect(HistorySearchEvaluator.matches(entry: late, categories: [], query: minute, calendar: calendar))
        let (next, _) = clockEntry(calendar: calendar, startHour: 18, startMinute: 1, startSecond: 0)
        #expect(!HistorySearchEvaluator.matches(entry: next, categories: [], query: minute, calendar: calendar))
        let second = try parseQuery("started:18:00:30", calendar: calendar)
        let (hit, _) = clockEntry(calendar: calendar, startHour: 18, startMinute: 0, startSecond: 30)
        #expect(HistorySearchEvaluator.matches(entry: hit, categories: [], query: second, calendar: calendar))
        let (miss, _) = clockEntry(calendar: calendar, startHour: 18, startMinute: 0, startSecond: 31)
        #expect(!HistorySearchEvaluator.matches(entry: miss, categories: [], query: second, calendar: calendar))
    }

    @Test("overnight clock ranges wrap across midnight")
    func overnightWrap() throws {
        let calendar = gmtCalendar()
        let query = try parseQuery("started:22:00..02:00", calendar: calendar)
        for hour in [22, 23, 0, 1, 2] {
            let (record, _) = clockEntry(calendar: calendar, startHour: hour)
            #expect(HistorySearchEvaluator.matches(
                entry: record, categories: [], query: query, calendar: calendar
            ), "hour \(hour) must match the overnight range")
        }
        for hour in [3, 12, 21] {
            let (record, _) = clockEntry(calendar: calendar, startHour: hour)
            #expect(!HistorySearchEvaluator.matches(
                entry: record, categories: [], query: query, calendar: calendar
            ), "hour \(hour) must not match the overnight range")
        }
        let day = try parseQuery("started:09:00..17:00", calendar: calendar)
        let (morning, _) = clockEntry(calendar: calendar, startHour: 10)
        #expect(HistorySearchEvaluator.matches(entry: morning, categories: [], query: day, calendar: calendar))
        let (night, _) = clockEntry(calendar: calendar, startHour: 20)
        #expect(!HistorySearchEvaluator.matches(entry: night, categories: [], query: day, calendar: calendar))
    }

    @Test("date and clock constraints on one key combine with AND")
    func dateAndClockCombine() throws {
        let calendar = gmtCalendar()
        let query = try parseQuery("started:2026-10-05 started:09:00..17:00", calendar: calendar)
        func dated(hour: Int, day: Int) -> TimeEntry {
            var comps = DateComponents()
            comps.calendar = calendar
            comps.timeZone = calendar.timeZone
            comps.year = 2026
            comps.month = 10
            comps.day = day
            comps.hour = hour
            let start = comps.date!
            return TimeEntry(
                id: "\(day)-\(hour)",
                activityText: "Work",
                startedAt: start,
                endedAt: start.addingTimeInterval(60),
                durationSeconds: 60
            )
        }
        #expect(HistorySearchEvaluator.matches(
            entry: dated(hour: 10, day: 5), categories: [], query: query, calendar: calendar
        ))
        #expect(!HistorySearchEvaluator.matches(
            entry: dated(hour: 20, day: 5), categories: [], query: query, calendar: calendar
        ))
        #expect(!HistorySearchEvaluator.matches(
            entry: dated(hour: 10, day: 6), categories: [], query: query, calendar: calendar
        ))
    }
}
