import Foundation

/// Pure parser for the History query language (design D2). Scanning lives
/// in `HistorySearchScanner`, date/time operands in `HistorySearchDates`.
/// No store, view, locale-display, or regex involvement: strict ASCII
/// Gregorian date notation, lowercase English keys. Only fully uppercase
/// `AND`/`OR` are operators (whitespace also conjoints); any other casing
/// and quoted forms stay text. `AND` binds tighter than `OR`; there are
/// no parentheses.
enum HistorySearchParser {
    static func parse(
        _ raw: String,
        calendar: Calendar = .current
    ) -> HistorySearchParseResult {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blank
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        switch HistorySearchScanner.tokenize(raw) {
        case .failure(let diagnostic):
            return .invalid(diagnostic)
        case .success(let tokens):
            if let paren = tokens.first(where: { HistorySearchScanner.containsUnquotedParen(in: $0.text) }) {
                return .invalid(.badOperator(paren.text))
            }
            // `OR` alternation first (`AND`/whitespace conjoint inside).
            // A leading, trailing, or doubled `OR` leaves an empty group.
            guard let groupTokens = splitOR(tokens) else {
                return .invalid(.badOperator("OR"))
            }
            var query = HistorySearchQuery()
            // Repeated `in:` clauses union globally; the first explicit
            // scope replaces the name+categories default (history-search
            // spec). `started:`/`ended:`/`duration:`/`has:` bind to their
            // own group.
            var scopeUnion: Set<HistorySearchField>?
            var scopeOrBoundQualifier = false
            var groups: [HistorySearchGroup] = []
            for tokens in groupTokens {
                var draft = GroupDraft()
                if let diagnostic = parseGroup(tokens, gregorian: gregorian, draft: &draft) {
                    return .invalid(diagnostic)
                }
                if let scope = draft.scope {
                    scopeUnion = (scopeUnion ?? []).union(scope)
                }
                scopeOrBoundQualifier = scopeOrBoundQualifier || draft.hasQualifier
                groups.append(draft.group)
            }
            query.groups = groups
            if let scopeUnion {
                query.fields = scopeUnion
            }
            query.hasScopeOrStart = scopeOrBoundQualifier
            return .valid(query)
        }
    }

    /// Splits whitespace-separated tokens on standalone `OR` operators.
    /// Returns nil when a leading, trailing, or doubled `OR` leaves an
    /// empty group.
    private static func splitOR(
        _ tokens: [HistorySearchScanner.RawToken]
    ) -> [[HistorySearchScanner.RawToken]]? {
        var groups: [[HistorySearchScanner.RawToken]] = [[]]
        for token in tokens {
            if token.text == "OR" {
                groups.append([])
            } else {
                groups[groups.count - 1].append(token)
            }
        }
        return groups.contains(where: \.isEmpty) ? nil : groups
    }

    /// One AND group's in-progress parse: its conjunction plus any global
    /// scope contribution and whether a group-bound qualifier appeared.
    private struct GroupDraft {
        var group = HistorySearchGroup()
        var scope: Set<HistorySearchField>?
        var hasQualifier = false
    }

    /// Parses one `OR` group's tokens into the draft. Returns a
    /// diagnostic for misplaced `AND` or any bad token, else nil.
    private static func parseGroup(
        _ tokens: [HistorySearchScanner.RawToken],
        gregorian: Calendar,
        draft: inout GroupDraft
    ) -> HistorySearchDiagnostic? {
        let flags = tokens.map { $0.text == "AND" }
        // A leading, trailing, or doubled `AND` leaves an empty conjunct
        // position.
        if flags.first == true || flags.last == true
            || zip(flags, flags.dropFirst()).contains(where: { $0.0 && $0.1 }) {
            return .badOperator("AND")
        }
        for token in tokens where token.text != "AND" {
            switch classify(token, gregorian: gregorian) {
            case let .term(value):
                draft.group.textTerms.append(value)
            case let .scope(fields):
                draft.scope = (draft.scope ?? []).union(fields)
                draft.hasQualifier = true
            case let .start(time):
                applyTime(time, isEnd: false, group: &draft.group)
                draft.hasQualifier = true
            case let .end(time):
                applyTime(time, isEnd: true, group: &draft.group)
                draft.hasQualifier = true
            case let .duration(predicates):
                draft.group.durationPredicates.append(contentsOf: predicates)
                draft.hasQualifier = true
            case let .presence(field, positive):
                applyPresence(field: field, positive: positive, group: &draft.group)
                draft.hasQualifier = true
            case .failure(let diagnostic):
                return diagnostic
            }
        }
        return nil
    }

    /// Folds one qualifier's instant/clock predicates into the start or
    /// end side of a group.
    private static func applyTime(
        _ time: HistorySearchTimeResult.Predicates,
        isEnd: Bool,
        group: inout HistorySearchGroup
    ) {
        switch (time, isEnd) {
        case let (.instant(predicates), false):
            group.startPredicates.append(contentsOf: predicates)
        case let (.clock(predicates), false):
            group.startClock.append(contentsOf: predicates)
        case let (.instant(predicates), true):
            group.endPredicates.append(contentsOf: predicates)
        case let (.clock(predicates), true):
            group.endClock.append(contentsOf: predicates)
        }
    }

    /// Folds one `has:`/`-has:` qualifier into a group's presence flags.
    /// Contradictory pairs stay set and match nothing (never dropped).
    private static func applyPresence(
        field: PresenceField,
        positive: Bool,
        group: inout HistorySearchGroup
    ) {
        switch field {
        case .notes:
            if positive {
                group.mustHaveNotes = true
            } else {
                group.mustLackNotes = true
            }
        case .category:
            if positive {
                group.mustHaveCategory = true
            } else {
                group.mustLackCategory = true
            }
        }
    }

    /// Which presence field a `has:` qualifier constrains.
    private enum PresenceField {
        case notes
        case category
    }

    private enum TokenMeaning {
        case term(String)
        case scope(Set<HistorySearchField>)
        case start(HistorySearchTimeResult.Predicates)
        case end(HistorySearchTimeResult.Predicates)
        case duration([HistorySearchDurationPredicate])
        case presence(PresenceField, Bool)
        case failure(HistorySearchDiagnostic)
    }

    private static func classify(
        _ token: HistorySearchScanner.RawToken,
        gregorian: Calendar
    ) -> TokenMeaning {
        if token.text == ".." || token.text == "*..*" {
            return .failure(.badRange(token.text))
        }
        guard let colon = HistorySearchScanner.firstUnquotedColon(in: token.text) else {
            if token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A token of only `""` or a whitespace-only phrase: quotes
                // removed, nothing searchable left.
                return .failure(.badQuotes)
            }
            return .term(token.value)
        }
        let key = String(token.text[..<colon])
        let operand = String(token.text[token.text.index(after: colon)...])
        if key.isEmpty {
            return .term(token.value)
        }
        // Negation exists only as `-has:`; any other `-` qualifier is a
        // diagnostic (a bare `-word` without a colon stays literal text).
        if key.hasPrefix("-"), key != "-has" {
            return .failure(.badOperator(token.text))
        }
        return classifyQualifier(key: key, operand: operand, gregorian: gregorian)
    }

    /// Dispatches a recognized qualifier key to its operand parser.
    private static func classifyQualifier(
        key: String,
        operand: String,
        gregorian: Calendar
    ) -> TokenMeaning {
        switch key {
        case "in":
            return parseScope(operand: operand)
        case "started":
            return classifyTime(key: key, operand: operand, gregorian: gregorian, isEnd: false)
        case "ended":
            return classifyTime(key: key, operand: operand, gregorian: gregorian, isEnd: true)
        case "duration":
            switch HistorySearchDuration.parseQualifier(key: key, operand: operand) {
            case let .predicates(predicates):
                return .duration(predicates)
            case let .invalid(diagnostic):
                return .failure(diagnostic)
            }
        case "has", "-has":
            return parseHas(operand: operand, negated: key == "-has")
        default:
            return .failure(.unknownQualifier(key))
        }
    }

    /// `started:`/`ended:` share operand rules; only the binding side
    /// differs.
    private static func classifyTime(
        key: String,
        operand: String,
        gregorian: Calendar,
        isEnd: Bool
    ) -> TokenMeaning {
        switch HistorySearchDates.parseTimeQualifier(key: key, operand: operand, gregorian: gregorian) {
        case let .instant(predicates):
            return isEnd ? .end(.instant(predicates)) : .start(.instant(predicates))
        case let .clock(predicates):
            return isEnd ? .end(.clock(predicates)) : .start(.clock(predicates))
        case let .invalid(diagnostic):
            return .failure(diagnostic)
        }
    }

    /// `in:` scopes: comma-separated/repeated unions replacing the default
    /// name+categories scope (design D2). Empty operands, quoted values,
    /// and unknown fields are diagnostics.
    private static func parseScope(operand: String) -> TokenMeaning {
        if operand.isEmpty {
            return .failure(.emptyValue("in:"))
        }
        if operand.contains("\"") {
            return .failure(.unknownScope(operand))
        }
        var fields = Set<HistorySearchField>()
        let elements = operand.split(separator: ",", omittingEmptySubsequences: false)
        for element in elements where element.isEmpty {
            return .failure(.emptyValue("in:\(operand)"))
        }
        for element in elements {
            guard let field = HistorySearchField(rawValue: String(element)) else {
                return .failure(.unknownScope(String(element)))
            }
            fields.insert(field)
        }
        return .scope(fields)
    }

    /// `has:`/`-has:` presence: exactly `notes` or `category` as one
    /// contiguous unquoted token. Value lists, quoted values, other
    /// values, and an empty value are diagnostics.
    private static func parseHas(operand: String, negated: Bool) -> TokenMeaning {
        let key = negated ? "-has:" : "has:"
        if operand.isEmpty {
            return .failure(.emptyValue(key))
        }
        if operand.contains("\"") || operand.contains(",") {
            return .failure(.badHas(operand))
        }
        switch operand {
        case "notes":
            return .presence(.notes, !negated)
        case "category":
            return .presence(.category, !negated)
        default:
            return .failure(.badHas(operand))
        }
    }
}
