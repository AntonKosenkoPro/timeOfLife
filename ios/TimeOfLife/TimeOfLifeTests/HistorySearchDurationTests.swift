import Testing
import Foundation
@testable import TimeOfLife

/// The `duration:` qualifier for History search (`add-history-search`
/// change, section 13): contiguous `d`/`h`/`m`/`s` components in
/// descending order without repeats, comparisons, inclusive/open ranges
/// with no wrap, bare-operand exact equality, displayed-duration
/// resolution, group binding, and no negation.
@Suite("HistorySearchDuration")
struct HistorySearchDurationTests {
    private func parseQuery(_ raw: String) throws -> HistorySearchQuery {
        let result = HistorySearchParser.parse(raw)
        guard case .valid(let parsed) = result else {
            throw TestError.expectedValid(raw)
        }
        return parsed
    }

    private enum TestError: Error {
        case expectedValid(String)
    }

    private func entry(
        name: String = "Gym",
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date? = nil,
        durationSeconds: Int? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: "\(name)-\(durationSeconds ?? -1)-\(endedAt?.timeIntervalSince1970 ?? -1)",
            activityText: name,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds
        )
    }

    // MARK: - Component parsing (task 13.2)

    @Test("contiguous components sum to exact seconds, skipped units zero")
    func componentSums() {
        let cases: [(String, Int)] = [
            ("1h", 3_600),
            ("90m", 5_400),
            ("45s", 45),
            ("1d", 86_400),
            ("0s", 0),
            ("1h30m", 5_400),
            ("1d1h1m1s", 90_061),
            ("2d34s", 172_834),
            ("2d5h55m34s", 194_134),
            ("07h", 25_200),
        ]
        for (operand, expected) in cases {
            #expect(
                HistorySearchDuration.parseOperand(operand) == expected,
                "\(operand) must parse as \(expected)s"
            )
        }
    }

    @Test("bad duration shapes are diagnostics")
    func badShapes() {
        for query in [
            "duration:",
            "duration:>",
            "duration:1H",
            "duration:h",
            "duration:1",
            "duration:1w",
            "duration:1.5h",
            "duration:-1h",
            "duration:1h1h",
            "duration:1m1h",
            "duration:1s1m",
            "duration:1h30",
            "duration:h1",
            "duration:1hh",
            "duration:\"1h\"",
            "duration:18:00",
            "duration:2026-10-01",
            "duration:9999999999999999999d",
            "duration:*",
            "duration:>*",
            "duration:*..*",
            "duration:>=1h..2h",
            "duration:1h..2h..3h",
            "duration:1h...2h",
            "duration:1h..2026-10-01",
            "duration:2026-10-01..1h",
            "duration:18:00..1h",
            "duration:1H..2H",
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("malformed durations use the duration diagnostic")
    func durationDiagnosticKind() {
        guard case .invalid(let diagnostic) = HistorySearchParser.parse("duration:1H") else {
            Issue.record("expected invalid query")
            return
        }
        #expect(diagnostic == .badDuration("1H"))
        #expect(!diagnostic.message.isEmpty)
    }

    @Test("reversed duration ranges are diagnostics, equal ends are valid")
    func reversedRanges() throws {
        for query in ["duration:2h..1h", "duration:1d..1m", "duration:61s..60s"] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
        let point = try parseQuery("duration:1h..1h")
        #expect(HistorySearchEvaluator.matches(
            entry: entry(endedAt: Date(timeIntervalSince1970: 1_700_003_600), durationSeconds: 3_600),
            categories: [], query: point
        ))
    }

    @Test("negated duration qualifiers are diagnostics")
    func unsupportedNegation() {
        for query in ["-duration:1h", "gym -duration:>1h"] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    // MARK: - Evaluation (task 13.2)

    @Test("bare operands mean exact-second equality")
    func bareExactEquality() throws {
        let query = try parseQuery("duration:1h")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(HistorySearchEvaluator.matches(
            entry: entry(endedAt: base.addingTimeInterval(3_600), durationSeconds: 3_600),
            categories: [], query: query
        ))
        for seconds in [3_599, 3_601] {
            #expect(!HistorySearchEvaluator.matches(
                entry: entry(endedAt: base.addingTimeInterval(TimeInterval(seconds)), durationSeconds: seconds),
                categories: [], query: query
            ), "\(seconds)s must not equal duration:1h")
        }
    }

    @Test("comparisons are strict or inclusive on exact second counts")
    func comparisonBoundaries() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func matches(_ raw: String, seconds: Int) throws -> Bool {
            let query = try parseQuery(raw)
            return HistorySearchEvaluator.matches(
                entry: entry(
                    endedAt: base.addingTimeInterval(TimeInterval(seconds)),
                    durationSeconds: seconds
                ),
                categories: [], query: query
            )
        }
        #expect(try matches("duration:>1h", seconds: 3_601))
        #expect(!(try matches("duration:>1h", seconds: 3_600)))
        #expect(try matches("duration:>=1h", seconds: 3_600))
        #expect(try matches("duration:<1h", seconds: 3_599))
        #expect(!(try matches("duration:<1h", seconds: 3_600)))
        #expect(try matches("duration:<=1h", seconds: 3_600))
    }

    @Test("inclusive and open ranges bound both sides")
    func ranges() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func matches(_ raw: String, seconds: Int) throws -> Bool {
            let query = try parseQuery(raw)
            return HistorySearchEvaluator.matches(
                entry: entry(
                    endedAt: base.addingTimeInterval(TimeInterval(seconds)),
                    durationSeconds: seconds
                ),
                categories: [], query: query
            )
        }
        for seconds in [60, 3_600, 86_400] {
            #expect(try matches("duration:1m..1d", seconds: seconds), "\(seconds)s in 1m..1d")
        }
        #expect(!(try matches("duration:1m..1d", seconds: 59)))
        #expect(!(try matches("duration:1m..1d", seconds: 86_401)))
        #expect(try matches("duration:1h..*", seconds: 3_600))
        #expect(!(try matches("duration:1h..*", seconds: 3_599)))
        #expect(try matches("duration:*..1h", seconds: 3_600))
        #expect(!(try matches("duration:*..1h", seconds: 3_601)))
    }

    @Test("entries without a resolvable duration match nothing")
    func nilDurationMatchesNothing() throws {
        let running = entry(endedAt: nil, durationSeconds: nil)
        #expect(running.endedAt == nil)
        for raw in [
            "duration:1h", "duration:>1h", "duration:>=1h",
            "duration:<1h", "duration:<=1h",
            "duration:1m..1d", "duration:1h..*", "duration:*..1h",
        ] {
            let query = try parseQuery(raw)
            #expect(!HistorySearchEvaluator.matches(
                entry: running, categories: [], query: query
            ), "unresolvable duration must not match \(raw)")
        }
    }

    @Test("stored seconds win; the interval resolves only when stored is nil")
    func resolutionOrder() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Stored 60s over a 2h interval: matches the stored count.
        let stored = entry(
            endedAt: base.addingTimeInterval(7_200),
            durationSeconds: 60
        )
        #expect(HistorySearchEvaluator.resolvedDurationSeconds(for: stored) == 60)
        let storedQuery = try parseQuery("duration:60s")
        #expect(HistorySearchEvaluator.matches(entry: stored, categories: [], query: storedQuery))
        let intervalQuery = try parseQuery("duration:2h")
        #expect(!HistorySearchEvaluator.matches(entry: stored, categories: [], query: intervalQuery))
        // Nil stored over a 2h interval: the interval resolves.
        let interval = entry(
            endedAt: base.addingTimeInterval(7_200),
            durationSeconds: nil
        )
        #expect(HistorySearchEvaluator.resolvedDurationSeconds(for: interval) == 7_200)
        #expect(HistorySearchEvaluator.matches(entry: interval, categories: [], query: intervalQuery))
    }

    @Test("subsecond intervals resolve like displayed durations")
    func subsecondIntervals() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 3600.5s rounds to 3601, the same value the row displays.
        let record = entry(
            endedAt: base.addingTimeInterval(3_600.5),
            durationSeconds: nil
        )
        #expect(HistorySearchEvaluator.resolvedDurationSeconds(for: record) == 3_601)
        let rounded = try parseQuery("duration:3601s")
        #expect(HistorySearchEvaluator.matches(entry: record, categories: [], query: rounded))
        let truncated = try parseQuery("duration:3600s")
        #expect(!HistorySearchEvaluator.matches(entry: record, categories: [], query: truncated))
    }

    @Test("contradictory durations stay valid and match nothing")
    func contradictoryDurations() throws {
        let query = try parseQuery("duration:>2h duration:<1h")
        #expect(query.durationPredicates.count == 2)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!HistorySearchEvaluator.matches(
            entry: entry(endedAt: base.addingTimeInterval(5_400), durationSeconds: 5_400),
            categories: [], query: query
        ))
    }

    // MARK: - Group binding (task 13.2)

    @Test("duration: binds to its own group while in: stays global")
    func durationBinding() throws {
        let query = try parseQuery("gym duration:>1h OR run")
        #expect(query.groups.count == 2)
        #expect(query.groups[0].durationPredicates.count == 1)
        #expect(query.groups[1].durationPredicates.isEmpty)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func named(_ name: String, seconds: Int) -> TimeEntry {
            TimeEntry(
                id: "\(name)-\(seconds)",
                activityText: name,
                startedAt: base,
                endedAt: base.addingTimeInterval(TimeInterval(seconds)),
                durationSeconds: seconds
            )
        }
        #expect(HistorySearchEvaluator.matches(entry: named("gym", seconds: 7_200), categories: [], query: query))
        #expect(!HistorySearchEvaluator.matches(entry: named("gym", seconds: 60), categories: [], query: query))
        // The `run` group carries no duration constraint: any length matches.
        #expect(HistorySearchEvaluator.matches(entry: named("run", seconds: 60), categories: [], query: query))
    }

    @Test("duration combines with text and date constraints using AND")
    func durationAndTextAndDate() throws {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let result = HistorySearchParser.parse("gym duration:>1h started:>=2026-10-05", calendar: gmt)
        guard case .valid(let query) = result else {
            Issue.record("expected valid query")
            return
        }
        func dated(name: String, day: Int, seconds: Int) -> TimeEntry {
            var comps = DateComponents()
            comps.calendar = gmt
            comps.timeZone = gmt.timeZone
            comps.year = 2026
            comps.month = 10
            comps.day = day
            comps.hour = 12
            let start = comps.date!
            return TimeEntry(
                id: "\(name)-\(day)-\(seconds)",
                activityText: name,
                startedAt: start,
                endedAt: start.addingTimeInterval(TimeInterval(seconds)),
                durationSeconds: seconds
            )
        }
        #expect(HistorySearchEvaluator.matches(
            entry: dated(name: "gym", day: 6, seconds: 7_200),
            categories: [], query: query, calendar: gmt
        ))
        #expect(!HistorySearchEvaluator.matches(
            entry: dated(name: "gym", day: 6, seconds: 60),
            categories: [], query: query, calendar: gmt
        ))
        #expect(!HistorySearchEvaluator.matches(
            entry: dated(name: "gym", day: 4, seconds: 7_200),
            categories: [], query: query, calendar: gmt
        ))
        #expect(!HistorySearchEvaluator.matches(
            entry: dated(name: "run", day: 6, seconds: 7_200),
            categories: [], query: query, calendar: gmt
        ))
    }

    @Test("duration-only queries filter with no highlights or excerpts")
    func durationOnlyHasNoPresentation() throws {
        let query = try parseQuery("duration:>1h")
        #expect(query.isFiltering)
        #expect(query.textTerms.isEmpty)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let record = TimeEntry(
            id: "gym-long",
            activityText: "Gym session",
            startedAt: base,
            endedAt: base.addingTimeInterval(7_200),
            durationSeconds: 7_200,
            categoryIDs: ["c0"],
            notes: "long workout"
        )
        let category = Category(id: "c0", name: "Gym", icon: "tag")
        #expect(HistorySearchEvaluator.matches(entry: record, categories: [category], query: query))
        let presentation = HistorySearchEvaluator.presentation(
            entry: record,
            categories: [category],
            caption: "Gym",
            query: query
        )
        #expect(presentation.nameRanges.isEmpty)
        #expect(presentation.captionRanges.isEmpty)
        #expect(presentation.excerpt == nil)
        #expect(!presentation.hasVisibleHighlights)
    }
}
