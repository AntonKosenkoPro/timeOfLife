import Testing
import Foundation
@testable import TimeOfLife

@Suite("HistorySearchDates")
struct HistorySearchDateTests {
    private func gmtCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func nyCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func predicate(
        _ query: String,
        calendar: Calendar? = nil
    ) throws -> HistorySearchStartPredicate {
        let result = HistorySearchParser.parse(query, calendar: calendar ?? gmtCalendar())
        guard case .valid(let parsed) = result else {
            throw TestError.expectedValid(query)
        }
        return try #require(parsed.startPredicates.first)
    }

    private enum TestError: Error {
        case expectedValid(String)
    }

    private func instant(
        _ iso: String,
        calendar: Calendar
    ) -> Date {
        let datePart = iso.split(separator: "T")[0].split(separator: "-").compactMap { Int($0) }
        let timePart = iso.split(separator: "T")[1].split(separator: ":").compactMap { Int($0) }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = datePart[0]
        comps.month = datePart[1]
        comps.day = datePart[2]
        comps.hour = timePart[0]
        comps.minute = timePart[1]
        comps.second = timePart.count > 2 ? timePart[2] : 0
        return comps.date!
    }

    // MARK: - Date-only operators (S(d)/N(d))

    @Test("bare date matches the whole local day, nothing outside")
    func bareDateWholeDay() throws {
        let calendar = gmtCalendar()
        let predicate = try predicate("started:2026-10-01", calendar: calendar)
        #expect(predicate.matches(instant("2026-10-01T00:00:00", calendar: calendar)))
        #expect(predicate.matches(instant("2026-10-01T23:59:59", calendar: calendar)))
        #expect(!predicate.matches(instant("2026-09-30T23:59:59", calendar: calendar)))
        #expect(!predicate.matches(instant("2026-10-02T00:00:00", calendar: calendar)))
    }

    @Test("comparison operators follow whole-day boundaries")
    func comparisonBoundaries() throws {
        let calendar = gmtCalendar()
        let after = try predicate("started:>2026-10-01", calendar: calendar)
        #expect(!after.matches(instant("2026-10-01T23:59:59", calendar: calendar)))
        #expect(after.matches(instant("2026-10-02T00:00:00", calendar: calendar)))

        let onOrAfter = try predicate("started:>=2026-10-01", calendar: calendar)
        #expect(onOrAfter.matches(instant("2026-10-01T00:00:00", calendar: calendar)))
        #expect(!onOrAfter.matches(instant("2026-09-30T23:59:59", calendar: calendar)))

        let before = try predicate("started:<2026-10-01", calendar: calendar)
        #expect(before.matches(instant("2026-09-30T23:59:59", calendar: calendar)))
        #expect(!before.matches(instant("2026-10-01T00:00:00", calendar: calendar)))

        let onOrBefore = try predicate("started:<=2026-10-01", calendar: calendar)
        #expect(onOrBefore.matches(instant("2026-10-01T23:59:59", calendar: calendar)))
        #expect(!onOrBefore.matches(instant("2026-10-02T00:00:00", calendar: calendar)))
    }

    @Test("inclusive date range covers both endpoint days")
    func inclusiveDateRange() throws {
        let calendar = gmtCalendar()
        let predicate = try predicate("started:2026-10-01..2026-10-31", calendar: calendar)
        #expect(predicate.matches(instant("2026-10-01T00:00:00", calendar: calendar)))
        #expect(predicate.matches(instant("2026-10-31T23:59:59", calendar: calendar)))
        #expect(predicate.matches(instant("2026-10-15T12:00:00", calendar: calendar)))
        #expect(!predicate.matches(instant("2026-09-30T23:59:59", calendar: calendar)))
        #expect(!predicate.matches(instant("2026-11-01T00:00:00", calendar: calendar)))
    }

    @Test("open and mixed ranges normalize each endpoint by its own rule")
    func openAndMixedRanges() throws {
        let calendar = gmtCalendar()
        let from = try predicate("started:2026-10-01..*", calendar: calendar)
        #expect(from.matches(instant("2026-10-01T00:00:00", calendar: calendar)))
        #expect(!from.matches(instant("2026-09-30T23:59:59", calendar: calendar)))

        let until = try predicate("started:*..2026-10-01", calendar: calendar)
        #expect(until.matches(instant("2026-10-01T23:59:59", calendar: calendar)))
        #expect(!until.matches(instant("2026-10-02T00:00:00", calendar: calendar)))

        // Date lower includes its whole day; timestamp upper is one instant.
        let mixed = try predicate(
            "started:2026-10-01..2026-10-31T00:00:00Z",
            calendar: calendar
        )
        #expect(mixed.matches(instant("2026-10-01T12:00:00", calendar: calendar)))
        #expect(mixed.matches(instant("2026-10-31T00:00:00", calendar: calendar)))
        #expect(!mixed.matches(instant("2026-10-31T00:00:01", calendar: calendar)))
    }

    // MARK: - Absolute timestamps

    @Test("equivalent positive, negative, and Z offsets match identically")
    func equivalentOffsets() throws {
        let calendar = gmtCalendar()
        let zulu = try predicate("started:>2012-04-19T11:00:00Z", calendar: calendar)
        let plus = try predicate("started:>2012-04-19T14:00:00+03:00", calendar: calendar)
        let minus = try predicate("started:>2012-04-19T06:00:00-05:00", calendar: calendar)
        let exact = instant("2012-04-19T11:00:00", calendar: calendar)
        let later = instant("2012-04-19T11:00:01", calendar: calendar)
        for predicate in [zulu, plus, minus] {
            #expect(!predicate.matches(exact))
            #expect(predicate.matches(later))
        }
    }

    @Test("bare timestamps mean exact instant equality without rounding")
    func exactTimestampEquality() throws {
        let calendar = gmtCalendar()
        let predicate = try predicate("started:2012-04-19T11:00:00Z", calendar: calendar)
        #expect(predicate.matches(instant("2012-04-19T11:00:00", calendar: calendar)))
        #expect(!predicate.matches(instant("2012-04-19T11:00:01", calendar: calendar)))
        // A stored start with subsecond precision is not equal to the bare instant.
        let subsecond = instant("2012-04-19T11:00:00", calendar: calendar)
            .addingTimeInterval(0.5)
        #expect(!predicate.matches(subsecond))
    }

    @Test("timestamp comparisons are strict or inclusive on exact instants")
    func timestampComparisonStrictness() throws {
        let calendar = gmtCalendar()
        let exact = instant("2012-04-19T11:00:00", calendar: calendar)
        let strict = try predicate("started:<2012-04-19T11:00:00Z", calendar: calendar)
        #expect(!strict.matches(exact))
        let inclusive = try predicate("started:<=2012-04-19T11:00:00Z", calendar: calendar)
        #expect(inclusive.matches(exact))
        let range = try predicate(
            "started:2012-04-19T11:00:00Z..2012-04-19T12:00:00Z",
            calendar: calendar
        )
        #expect(range.matches(exact))
        #expect(range.matches(instant("2012-04-19T12:00:00", calendar: calendar)))
    }

    // MARK: - Calendar edges (task 2.4)

    @Test("month, year, and leap-day edges validate real dates")
    func calendarEdges() {
        for query in ["started:2024-02-29", "started:2026-01-31", "started:2026-12-31"] {
            if case .valid = HistorySearchParser.parse(query, calendar: gmtCalendar()) {
            } else {
                Issue.record("expected valid query for \(query)")
            }
        }
        for query in ["started:2026-02-29", "started:2026-04-31", "started:2026-00-10"] {
            if case .invalid = HistorySearchParser.parse(query, calendar: gmtCalendar()) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("local midnight bounds follow the device timezone, not UTC")
    func localMidnight() throws {
        let date = try predicate("started:2026-10-01", calendar: nyCalendar())
        // Oct 1 00:00 in New York (EDT) is Oct 1 04:00 UTC.
        #expect(!date.matches(instant("2026-10-01T03:59:59", calendar: gmtCalendar())))
        #expect(date.matches(instant("2026-10-01T04:00:00", calendar: gmtCalendar())))
        #expect(date.matches(instant("2026-10-02T03:59:59", calendar: gmtCalendar())))
        #expect(!date.matches(instant("2026-10-02T04:00:00", calendar: gmtCalendar())))
    }

    @Test("daylight-saving transitions keep exact calendar days")
    func dstTransitions() throws {
        let calendar = nyCalendar()
        // Spring forward: 2026-03-08 is a 23-hour day.
        let spring = try predicate("started:2026-03-08", calendar: calendar)
        #expect(spring.matches(instant("2026-03-08T01:30:00", calendar: calendar)))
        #expect(spring.matches(instant("2026-03-08T03:30:00", calendar: calendar)))
        #expect(!spring.matches(instant("2026-03-09T00:30:00", calendar: calendar)))
        let afterSpring = try predicate("started:>2026-03-08", calendar: calendar)
        #expect(afterSpring.matches(instant("2026-03-09T00:00:00", calendar: calendar)))
        #expect(!afterSpring.matches(instant("2026-03-08T23:00:00", calendar: calendar)))

        // Fall back: 2026-11-01 is a 25-hour day; both 01:30 folds match.
        let fall = try predicate("started:2026-11-01", calendar: calendar)
        #expect(fall.matches(instant("2026-11-01T12:00:00", calendar: calendar)))
        let firstFold = instant("2026-11-01T01:30:00", calendar: calendar)
        #expect(fall.matches(firstFold))
        #expect(fall.matches(firstFold.addingTimeInterval(3600)))
        #expect(!fall.matches(instant("2026-11-02T00:30:00", calendar: calendar)))
    }

    @Test("non-Gregorian UI calendars still parse Gregorian notation")
    func nonDefaultCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(secondsFromGMT: 0)!
        if case .valid(let query) = HistorySearchParser.parse("started:2026-10-01", calendar: buddhist) {
            #expect(query.startPredicates.count == 1)
            #expect(query.startPredicates[0].matches(
                instant("2026-10-01T12:00:00", calendar: gmtCalendar())
            ))
        } else {
            Issue.record("expected valid query under a Buddhist calendar")
        }
    }

    @Test("the same date query means different instants across timezones")
    func timezoneChangeShiftsBounds() throws {
        let gmt = try predicate("started:2026-10-01", calendar: gmtCalendar())
        let ny = try predicate("started:2026-10-01", calendar: nyCalendar())
        let probe = instant("2026-10-01T02:00:00", calendar: gmtCalendar())
        #expect(gmt.matches(probe))
        #expect(!ny.matches(probe))
    }

    @Test("start constraints use the entry start, never interval overlap")
    func startNotOverlap() throws {
        let calendar = gmtCalendar()
        let predicate = try predicate("started:2026-10-02", calendar: calendar)
        // Starts Oct 1, ends Oct 2: the start day decides.
        #expect(!predicate.matches(instant("2026-10-01T23:00:00", calendar: calendar)))
        #expect(predicate.matches(instant("2026-10-02T00:30:00", calendar: calendar)))
    }

    // MARK: - Wall-clock operands (task 12.2, section 12)

    private func clockQuery(_ raw: String, calendar: Calendar) throws -> HistorySearchQuery {
        let result = HistorySearchParser.parse(raw, calendar: calendar)
        guard case .valid(let parsed) = result else {
            throw TestError.expectedValid(raw)
        }
        return parsed
    }

    private func clockMatches(
        _ raw: String,
        instant iso: String,
        parseCalendar: Calendar,
        evalCalendar: Calendar
    ) throws -> Bool {
        let query = try clockQuery(raw, calendar: parseCalendar)
        let probe = instant(iso, calendar: gmtCalendar())
        let record = TimeEntry(
            id: "probe",
            activityText: "Walk",
            startedAt: probe,
            endedAt: probe.addingTimeInterval(60),
            durationSeconds: 60
        )
        return HistorySearchEvaluator.matches(
            entry: record, categories: [], query: query, calendar: evalCalendar
        )
    }

    @Test("bare clock windows cover the minute vs the exact second")
    func bareClockWindows() throws {
        let calendar = gmtCalendar()
        let minute = try clockQuery("started:18:00", calendar: calendar)
        #expect(minute.groups[0].startClock.count == 1)
        #expect(try clockMatches("started:18:00", instant: "2026-10-01T18:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(try clockMatches("started:18:00", instant: "2026-10-01T18:00:59", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:18:00", instant: "2026-10-01T18:01:00", parseCalendar: calendar, evalCalendar: calendar)))
        #expect(try clockMatches("started:18:00:30", instant: "2026-10-01T18:00:30", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:18:00:30", instant: "2026-10-01T18:00:31", parseCalendar: calendar, evalCalendar: calendar)))
    }

    @Test("clock comparisons are strict or inclusive on exact wall instants")
    func clockComparisonStrictness() throws {
        let calendar = gmtCalendar()
        #expect(!(try clockMatches("started:>18:00", instant: "2026-10-01T18:00:00", parseCalendar: calendar, evalCalendar: calendar)))
        #expect(try clockMatches("started:>=18:00", instant: "2026-10-01T18:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(try clockMatches("started:>18:00", instant: "2026-10-01T18:00:01", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:<18:00", instant: "2026-10-01T18:00:00", parseCalendar: calendar, evalCalendar: calendar)))
        #expect(try clockMatches("started:<=18:00", instant: "2026-10-01T18:00:00", parseCalendar: calendar, evalCalendar: calendar))
    }

    @Test("clock ranges are inclusive; earlier ends wrap across midnight")
    func clockRangeWrapSemantics() throws {
        let calendar = gmtCalendar()
        // Inclusive endpoints on a non-wrapping range.
        #expect(try clockMatches("started:09:00..17:00", instant: "2026-10-01T09:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(try clockMatches("started:09:00..17:00", instant: "2026-10-01T17:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:09:00..17:00", instant: "2026-10-01T17:00:01", parseCalendar: calendar, evalCalendar: calendar)))
        // Wrapping range matches either side, not the middle.
        #expect(try clockMatches("started:22:00..02:00", instant: "2026-10-01T22:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(try clockMatches("started:22:00..02:00", instant: "2026-10-01T02:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:22:00..02:00", instant: "2026-10-01T02:00:01", parseCalendar: calendar, evalCalendar: calendar)))
        #expect(!(try clockMatches("started:22:00..02:00", instant: "2026-10-01T12:00:00", parseCalendar: calendar, evalCalendar: calendar)))
        // Open clock ranges are one-sided inclusive comparisons.
        #expect(try clockMatches("started:22:00..*", instant: "2026-10-01T23:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:22:00..*", instant: "2026-10-01T21:59:59", parseCalendar: calendar, evalCalendar: calendar)))
        #expect(try clockMatches("started:*..02:00", instant: "2026-10-01T02:00:00", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:*..02:00", instant: "2026-10-01T02:00:01", parseCalendar: calendar, evalCalendar: calendar)))
        // Mixed HH:MM/HH:MM:SS endpoints pair as clock with clock.
        #expect(try clockMatches("started:09:00..17:00:30", instant: "2026-10-01T17:00:30", parseCalendar: calendar, evalCalendar: calendar))
        #expect(!(try clockMatches("started:09:00..17:00:30", instant: "2026-10-01T17:00:31", parseCalendar: calendar, evalCalendar: calendar)))
    }

    @Test("clock filtering follows the evaluation timezone, not UTC")
    func clockFollowsTimezone() throws {
        // 15:00 UTC is 11:00 in New York (EDT): after noon UTC, before
        // noon local.
        #expect(try clockMatches(
            "started:>12:00", instant: "2026-10-01T15:00:00",
            parseCalendar: gmtCalendar(), evalCalendar: gmtCalendar()
        ))
        #expect(!(try clockMatches(
            "started:>12:00", instant: "2026-10-01T15:00:00",
            parseCalendar: nyCalendar(), evalCalendar: nyCalendar()
        )))
    }
}
