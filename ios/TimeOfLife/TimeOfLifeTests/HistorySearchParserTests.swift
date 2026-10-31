import Testing
import Foundation
@testable import TimeOfLife

@Suite("HistorySearchParser")
struct HistorySearchParserTests {
    // MARK: - Blank queries

    @Test("empty and whitespace-only queries are blank, not invalid")
    func blankQueries() {
        #expect(HistorySearchParser.parse("") == .blank)
        #expect(HistorySearchParser.parse("   ") == .blank)
        #expect(HistorySearchParser.parse(" \n\t ") == .blank)
    }

    // MARK: - Plain text and default scope (task 2.1)

    @Test("plain text searches names and categories by default")
    func defaultNameScope() {
        guard case .valid(let query) = HistorySearchParser.parse("gym") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.fields == [.name, .categories])
        #expect(query.groups.count == 1)
        #expect(query.groups[0].textTerms == ["gym"])
        // `gym` and `gym in:name,categories` yield the same entries: the
        // same terms over the same fields (the explicit scope only marks
        // the query filtered).
        guard case .valid(let scoped) = HistorySearchParser.parse("gym in:name,categories") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == scoped.textTerms)
        #expect(query.fields == scoped.fields)
    }

    @Test("an explicit in:name narrows the name+categories default")
    func explicitScopeNarrowsDefault() {
        guard case .valid(let plain) = HistorySearchParser.parse("gym"),
              case .valid(let narrowed) = HistorySearchParser.parse("gym in:name") else {
            Issue.record("expected valid queries")
            return
        }
        #expect(plain.fields == [.name, .categories])
        #expect(narrowed.fields == [.name])
    }

    @Test("whitespace separates terms that combine with AND")
    func multipleTerms() {
        guard case .valid(let query) = HistorySearchParser.parse("morning gym") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["morning", "gym"])
        #expect(query.groups.count == 1)
    }

    @Test("double quotes delimit one phrase preserving inner whitespace")
    func quotedPhrase() {
        guard case .valid(let query) = HistorySearchParser.parse("\"morning gym\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["morning gym"])
    }

    @Test("escaped quotes and backslashes inside phrases are literal")
    func quotedEscapes() {
        guard case .valid(let query) = HistorySearchParser.parse("\"a\\\"b\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["a\"b"])
        guard case .valid(let backslash) = HistorySearchParser.parse("\"a\\\\b\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(backslash.textTerms == ["a\\b"])
    }

    @Test("apostrophes are ordinary text")
    func apostrophesLiteral() {
        guard case .valid(let query) = HistorySearchParser.parse("don't") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["don't"])
    }

    @Test("quoted text containing a colon is literal, not a qualifier")
    func literalQuotedColons() {
        guard case .valid(let query) = HistorySearchParser.parse("\"project:alpha\"") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms == ["project:alpha"])
    }

    // MARK: - Global scope unions (task 2.1)

    @Test("explicit scopes replace the default wherever they appear")
    func scopeReplacesDefault() {
        #expect(HistorySearchParser.parse("gym in:notes") == HistorySearchParser.parse("in:notes gym"))
        guard case .valid(let query) = HistorySearchParser.parse("gym in:notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.fields == [.notes])
    }

    @Test("comma-separated and repeated scopes form a union")
    func scopeUnion() {
        #expect(
            HistorySearchParser.parse("gym in:name in:notes")
                == HistorySearchParser.parse("gym in:name,notes")
        )
        guard case .valid(let query) = HistorySearchParser.parse("gym stretch in:name,notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.fields == [.name, .notes])
        #expect(query.textTerms == ["gym", "stretch"])
    }

    @Test("scope-only queries are valid and filter without text terms")
    func scopeOnlyFilters() {
        guard case .valid(let query) = HistorySearchParser.parse("in:notes") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms.isEmpty)
        #expect(query.fields == [.notes])
        #expect(query.isFiltering)
    }

    @Test("date-only queries are valid and filter without text terms")
    func dateOnlyFilters() {
        guard case .valid(let query) = HistorySearchParser.parse("started:>=2026-10-01") else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.textTerms.isEmpty)
        #expect(query.startPredicates.count == 1)
        #expect(query.isFiltering)
    }

    @Test("multiple start constraints are conjunctive")
    func conjunctiveBounds() {
        guard case .valid(let query) = HistorySearchParser.parse(
            "started:2026-10-01..* started:<2026-11-01"
        ) else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.startPredicates.count == 2)
    }

    // MARK: - Diagnostics (task 2.3)

    @Test("unknown qualifiers are diagnostics, including case variants")
    func unknownQualifiers() {
        guard case .invalid(let first) = HistorySearchParser.parse("source:healthkit") else {
            Issue.record("expected invalid query")
            return
        }
        #expect(first == .unknownQualifier("source"))
        guard case .invalid(let second) = HistorySearchParser.parse("IN:name") else {
            Issue.record("expected invalid query")
            return
        }
        #expect(second == .unknownQualifier("IN"))
    }

    @Test("unknown scopes and empty list elements are diagnostics")
    func badScopes() {
        guard case .invalid(let unknown) = HistorySearchParser.parse("in:source") else {
            Issue.record("expected invalid query")
            return
        }
        #expect(unknown == .unknownScope("source"))
        if case .invalid = HistorySearchParser.parse("gym in:name,,notes") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("gym in:name,") {
        } else {
            Issue.record("expected invalid query")
        }
    }

    @Test("empty qualifier values are diagnostics")
    func emptyValues() {
        if case .invalid = HistorySearchParser.parse("in:") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("started:") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("started:>") {
        } else {
            Issue.record("expected invalid query")
        }
    }

    @Test("quote problems are diagnostics")
    func quoteDiagnostics() {
        for query in ["\"unclosed", "\"a\\qb\"", "\"a\\", "\"\"", "\"   \"", "foo \"\""] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("separated qualifier operands are diagnostics, not trimmed or joined")
    func contiguousQualifierRule() {
        for query in [
            "in: notes",
            "started: >=2026-10-01",
            "started:2026-10-01 .. 2026-10-31",
            "started:\"2026-10-01\"",
            "in:\"name\""
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("standalone range operators are diagnostics")
    func strayOperators() {
        if case .invalid = HistorySearchParser.parse("gym ..") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("..") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("started:*..*") {
        } else {
            Issue.record("expected invalid query")
        }
        if case .invalid = HistorySearchParser.parse("*..*") {
        } else {
            Issue.record("expected invalid query")
        }
    }

    @Test("malformed dates and timestamps are diagnostics")
    func badDates() {
        for query in [
            "started:2026-02-30",
            "started:2026-13-01",
            "started:2026-10-32",
            "started:2026-1-01",
            "started:>2012-04-19T11:00",
            "started:>2012-04-19T11:00:00",
            "started:>2012-04-19T11:00:00.000Z",
            "started:>2012-04-19 11:00:00Z",
            "started:>=2026-10-01..2026-10-31",
            "started:*",
            "started:>*",
            "started:2026-10-01...",
            "started:october"
        ] {
            if case .invalid = HistorySearchParser.parse(query) {
            } else {
                Issue.record("expected invalid query for \(query)")
            }
        }
    }

    @Test("reversed ranges are diagnostics")
    func reversedRanges() {
        if case .invalid = HistorySearchParser.parse("started:2026-10-05..2026-10-01") {
        } else {
            Issue.record("expected invalid query")
        }
    }

    @Test("contradictory but individually valid predicates stay valid")
    func contradictoryPredicatesStayValid() {
        guard case .valid(let query) = HistorySearchParser.parse(
            "started:2026-10-01..2026-10-05 started:2026-11-01..2026-11-05"
        ) else {
            Issue.record("expected valid query")
            return
        }
        #expect(query.startPredicates.count == 2)
        let gmt = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.calendar = gmt
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 10
        components.day = 3
        components.hour = 12
        let probe = components.date!
        #expect(query.startPredicates.allSatisfy { $0.matches(probe) } == false)
    }

    @Test("diagnostics carry localized non-empty messages")
    func diagnosticMessages() {
        let diagnostics: [HistorySearchDiagnostic] = [
            .unknownQualifier("source"),
            .unknownScope("source"),
            .emptyValue("in:"),
            .badQuotes,
            .badDate("started:2026-02-30"),
            .badRange("*..*"),
            .badOperator("OR"),
            .badHas("tag"),
            .badTime("25:00"),
            .badDuration("1H"),
        ]
        for diagnostic in diagnostics {
            #expect(!diagnostic.message.isEmpty)
        }
    }
}
