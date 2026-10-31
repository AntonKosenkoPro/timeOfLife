import Testing
import Foundation
@testable import TimeOfLife

/// Boolean groups, presence, and `ended:` binding for History search
/// (`add-history-search` change, section 12): uppercase `AND`/`OR`
/// operators (`AND` binds tighter, no parentheses, lowercase/quoted forms
/// stay text), group-bound `started:`/`ended:`/`has:` versus global `in:`,
/// and `-has:` as the only negation.
@Suite("HistorySearchGroups")
struct HistorySearchGroupsTests {
    private func entry(
        name: String,
        categories: [String] = [],
        notes: String = "",
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> (TimeEntry, [Category]) {
        let cats = categories.enumerated().map { index, name in
            Category(id: "c\(index)", name: name, icon: "tag")
        }
        let record = TimeEntry(
            id: "e1",
            activityText: name,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationSeconds: 60,
            categoryIDs: cats.map(\.id),
            notes: notes
        )
        return (record, cats)
    }

    private func parseQuery(
        _ raw: String,
        calendar: Calendar? = nil
    ) throws -> HistorySearchQuery {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let result = HistorySearchParser.parse(raw, calendar: calendar ?? gmt)
        guard case .valid(let parsed) = result else {
            throw TestError.expectedValid(raw)
        }
        return parsed
    }

    private enum TestError: Error {
        case expectedValid(String)
    }

    // MARK: - Operators and grouping (task 12.2)

    @Test("an explicit AND conjoints exactly like whitespace")
    func explicitAnd() {
        #expect(
            HistorySearchParser.parse("gym AND run")
                == HistorySearchParser.parse("gym run")
        )
    }

    @Test("OR splits groups; AND binds tighter with no parentheses")
    func orGroupsAndPrecedence() {
        guard case .valid(let query) = HistorySearchParser.parse("gym run OR swim started:>=2026-10-01") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.groups.count == 2)
        #expect(query.groups[0].textTerms == ["gym", "run"])
        #expect(query.groups[0].startPredicates.isEmpty)
        #expect(query.groups[1].textTerms == ["swim"])
        #expect(query.groups[1].startPredicates.count == 1)
    }

    @Test("started: binds to its own group while in: stays global")
    func qualifierBinding() {
        guard case .valid(let query) = HistorySearchParser.parse("gym started:>=2026-10-01 OR run") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.groups.count == 2)
        #expect(query.groups[0].startPredicates.count == 1)
        #expect(query.groups[1].startPredicates.isEmpty)

        guard case .valid(let scoped) = HistorySearchParser.parse("gym in:notes OR run") else {
            Issue.record("expected valid query")
            return
        }
        #expect(scoped.fields == [.notes])
        #expect(scoped.groups.map(\.textTerms) == [["gym"], ["run"]])
    }

    @Test("lowercase and quoted operators stay ordinary text")
    func lowercaseAndQuotedOperatorsAreText() {
        guard case .valid(let query) = HistorySearchParser.parse("fish and chips in:notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["fish", "and", "chips"])
        guard case .valid(let quoted) = HistorySearchParser.parse("\"gym OR run\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(quoted.textTerms == ["gym OR run"])
        #expect(quoted.groups.count == 1)
        guard case .valid(let and) = HistorySearchParser.parse("\"AND\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(and.textTerms == ["AND"])
    }

    @Test("leading, trailing, and doubled operators are diagnostics")
    func operatorPlacement() {
        for query in [
            "OR gym", "gym OR", "gym OR OR run", "gym AND OR run",
            "AND gym", "gym AND", "gym AND AND run", "OR", "AND",
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("unquoted parentheses are diagnostics; quoted parens stay text")
    func parentheses() {
        for query in ["(gym)", "gym (run)", "(", ")", "gym)", "(gym OR run)"] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
        guard case .valid(let quoted) = HistorySearchParser.parse("\"(gym)\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(quoted.textTerms == ["(gym)"])
    }

    @Test("negation exists only as -has:; other negated qualifiers are diagnostics")
    func unsupportedNegations() {
        for query in ["gym -started:2026-10-01", "-ended:2026-10-01", "-in:notes", "-foo:bar"] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
        // A bare `-word` without a colon is literal text, not negation.
        guard case .valid(let query) = HistorySearchParser.parse("-gym") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["-gym"])
    }

    // MARK: - Presence (task 12.2)

    @Test("has:notes and has:category bind presence, negatable as -has:")
    func hasPresence() {
        guard case .valid(let query) = HistorySearchParser.parse("has:notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.groups.count == 1)
        #expect(query.groups[0].mustHaveNotes)
        #expect(!query.groups[0].mustLackNotes)
        guard case .valid(let negated) = HistorySearchParser.parse("walk -has:category") else {
            Issue.record("expected valid query")
            return
        }
        #expect(negated.groups[0].textTerms == ["walk"])
        #expect(negated.groups[0].mustLackCategory)
        guard case .valid(let both) = HistorySearchParser.parse("has:notes -has:category") else {
            Issue.record("expected valid query")
            return
        }
        #expect(both.groups[0].mustHaveNotes && both.groups[0].mustLackCategory)
        // Contradictory presence stays valid and matches nothing (never
        // silently dropped).
        guard case .valid(let conflict) = HistorySearchParser.parse("has:notes -has:notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(conflict.groups[0].mustHaveNotes && conflict.groups[0].mustLackNotes)
    }

    @Test("unknown, listed, quoted, and empty has: values are diagnostics")
    func badHasValues() {
        for query in [
            "has:tag", "has:note", "has:Categories", "has:notes,category",
            "has:\"notes\"", "has:", "-has:tag", "-has:",
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    // MARK: - Ended binding (task 12.2)

    @Test("ended: mirrors started: binding to its own group")
    func endedBinding() {
        guard case .valid(let query) = HistorySearchParser.parse("gym ended:2026-10-01 OR run") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.groups.count == 2)
        #expect(query.groups[0].endPredicates.count == 1)
        #expect(query.groups[0].startPredicates.isEmpty)
        #expect(query.groups[1].endPredicates.isEmpty)
    }

    // MARK: - Group evaluation (task 12.2)

    @Test("the new default highlights names and categories but never notes")
    func defaultScopeHighlights() throws {
        let query = try parseQuery("gym")
        let (record, cats) = entry(name: "Gym", categories: ["Gym"], notes: "gym")
        let caption = cats.map(\.name).joined(separator: ", ")
        let presentation = HistorySearchEvaluator.presentation(
            entry: record,
            categories: cats,
            caption: caption,
            query: query
        )
        #expect(presentation.nameRanges.count == 1)
        #expect(presentation.captionRanges.count == 1)
        #expect(presentation.excerpt == nil)
    }

    @Test("OR alternation matches either group exactly once")
    func orAlternation() throws {
        let query = try parseQuery("gym OR run")
        #expect(query.groups.count == 2)
        let (gym, _) = entry(name: "Morning Gym")
        #expect(HistorySearchEvaluator.matches(entry: gym, categories: [], query: query))
        let (run, _) = entry(name: "Evening Run")
        #expect(HistorySearchEvaluator.matches(entry: run, categories: [], query: query))
        let (both, _) = entry(name: "Gym run combo")
        #expect(HistorySearchEvaluator.matches(entry: both, categories: [], query: query))
        let (neither, _) = entry(name: "Swim")
        #expect(!HistorySearchEvaluator.matches(entry: neither, categories: [], query: query))
    }

    @Test("AND binds tighter: gym run OR swim needs both gym and run")
    func andPrecedence() throws {
        let query = try parseQuery("gym run OR swim")
        let (gymRun, _) = entry(name: "gym run")
        #expect(HistorySearchEvaluator.matches(entry: gymRun, categories: [], query: query))
        let (gymOnly, _) = entry(name: "gym")
        #expect(!HistorySearchEvaluator.matches(entry: gymOnly, categories: [], query: query))
        let (swim, _) = entry(name: "swim")
        #expect(HistorySearchEvaluator.matches(entry: swim, categories: [], query: query))
    }

    @Test("group-bound dates apply only to their group")
    func groupBoundDates() throws {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let query = try parseQuery("gym started:>=2026-10-05 OR run", calendar: gmt)
        func dated(name: String, day: Int) -> (TimeEntry, [Category]) {
            var comps = DateComponents()
            comps.calendar = gmt
            comps.timeZone = gmt.timeZone
            comps.year = 2026
            comps.month = 10
            comps.day = day
            comps.hour = 12
            return (TimeEntry(
                id: name,
                activityText: name,
                startedAt: comps.date!,
                endedAt: comps.date!.addingTimeInterval(60),
                durationSeconds: 60
            ), [])
        }
        let (gymNew, _) = dated(name: "gym", day: 6)
        #expect(HistorySearchEvaluator.matches(entry: gymNew, categories: [], query: query, calendar: gmt))
        let (gymOld, _) = dated(name: "gym", day: 4)
        #expect(!HistorySearchEvaluator.matches(entry: gymOld, categories: [], query: query, calendar: gmt))
        // The `run` group carries no date constraint: any date matches.
        let (runOld, _) = dated(name: "run", day: 1)
        #expect(HistorySearchEvaluator.matches(entry: runOld, categories: [], query: query, calendar: gmt))
    }

    @Test("has:notes and has:category filter presence with -has: negation")
    func hasPresenceEvaluation() throws {
        let query = try parseQuery("has:notes -has:category")
        let (match, _) = entry(name: "Walk", notes: "park loop")
        #expect(HistorySearchEvaluator.matches(entry: match, categories: [], query: query))
        let (noNotes, _) = entry(name: "Walk", notes: "   ")
        #expect(!HistorySearchEvaluator.matches(entry: noNotes, categories: [], query: query))
        let (categorized, cats) = entry(name: "Walk", categories: ["Park"], notes: "park loop")
        #expect(!HistorySearchEvaluator.matches(entry: categorized, categories: cats, query: query))
        // Contradictory presence matches nothing rather than dropping a side.
        let conflict = try parseQuery("has:notes -has:notes")
        #expect(!HistorySearchEvaluator.matches(entry: match, categories: [], query: conflict))
    }
}
