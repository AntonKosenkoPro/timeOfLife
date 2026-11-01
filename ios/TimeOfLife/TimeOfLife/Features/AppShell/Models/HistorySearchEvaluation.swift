import Foundation

/// Immutable per-row search presentation derived once per query/snapshot,
/// never in row bodies (history-search spec, design D5/D6).
struct HistorySearchRowPresentation: Equatable, Sendable {
    /// Character-offset ranges in `entry.activityText`.
    var nameRanges: [Range<Int>] = []
    /// Character-offset ranges in the composed `categoryNames` caption
    /// (`names.joined(separator: ", ")`); provenance text never carries
    /// ranges.
    var captionRanges: [Range<Int>] = []
    var excerpt: HistorySearchExcerpt?

    var hasVisibleHighlights: Bool {
        !nameRanges.isEmpty || !captionRanges.isEmpty
            || !(excerpt?.highlights.isEmpty ?? true)
    }
}

/// One bounded plain-text notes excerpt with display-coordinate highlights.
struct HistorySearchExcerpt: Equatable, Sendable {
    /// Display text: collapsed whitespace, `…` only at omitted ends.
    var text: String
    /// Character-offset ranges in `text`.
    var highlights: [Range<Int>] = []
}

/// Pure History query evaluation over an account snapshot (design D1/D2).
/// Case-insensitive Unicode-aware substring matching with no accent folding;
/// every range is computed against the original string it highlights.
/// A query matches when ANY group matches; within a group every text term
/// (each in at least one globally selected field), every `started:`
/// constraint on the entry start, every `ended:` constraint on the entry
/// end, every `duration:` constraint on the entry's resolved length, and
/// every `has:` presence constraint must hold (AND).
enum HistorySearchEvaluator {
    // MARK: - Matching

    /// Whether the entry satisfies at least one group. Committed entries
    /// only — callers filter the `LocalStore.entries()` snapshot, which
    /// never contains running drafts. Entries without an end satisfy no
    /// `ended:` constraint.
    static func matches(
        entry: TimeEntry,
        categories: [Category],
        query: HistorySearchQuery,
        calendar: Calendar = .current
    ) -> Bool {
        query.groups.contains {
            matchesGroup($0, entry: entry, categories: categories, fields: query.fields, calendar: calendar)
        }
    }

    private static func matchesGroup(
        _ group: HistorySearchGroup,
        entry: TimeEntry,
        categories: [Category],
        fields: Set<HistorySearchField>,
        calendar: Calendar
    ) -> Bool {
        for term in group.textTerms {
            guard !term.isEmpty, matchesTerm(
                term,
                entry: entry,
                categories: categories,
                fields: fields
            ) else { return false }
        }
        guard matchesStart(group, startedAt: entry.startedAt, calendar: calendar) else { return false }
        guard matchesEnd(group, endedAt: entry.endedAt, calendar: calendar) else { return false }
        guard matchesDuration(group, entry: entry) else { return false }
        return matchesPresence(group, entry: entry)
    }

    private static func matchesStart(
        _ group: HistorySearchGroup,
        startedAt: Date,
        calendar: Calendar
    ) -> Bool {
        for predicate in group.startPredicates {
            guard predicate.matches(startedAt) else { return false }
        }
        guard !group.startClock.isEmpty else { return true }
        let wall = HistorySearchClockPredicate.wallSeconds(of: startedAt, timeZone: calendar.timeZone)
        return group.startClock.allSatisfy { $0.matches(wallSeconds: wall) }
    }

    /// Entries without an end satisfy no `ended:` constraint.
    private static func matchesEnd(
        _ group: HistorySearchGroup,
        endedAt: Date?,
        calendar: Calendar
    ) -> Bool {
        for predicate in group.endPredicates {
            guard let endedAt, predicate.matches(endedAt) else { return false }
        }
        guard !group.endClock.isEmpty else { return true }
        guard let endedAt else { return false }
        let wall = HistorySearchClockPredicate.wallSeconds(of: endedAt, timeZone: calendar.timeZone)
        return group.endClock.allSatisfy { $0.matches(wallSeconds: wall) }
    }

    /// Entries with no resolvable duration satisfy no `duration:`
    /// constraint. Resolution mirrors the displayed duration
    /// (`HistoryViewModel.durationText`): the stored seconds when known,
    /// else the rounded start-to-end interval when the entry ended.
    private static func matchesDuration(_ group: HistorySearchGroup, entry: TimeEntry) -> Bool {
        guard !group.durationPredicates.isEmpty else { return true }
        guard let seconds = resolvedDurationSeconds(for: entry) else { return false }
        return group.durationPredicates.allSatisfy { $0.matches(seconds) }
    }

    static func resolvedDurationSeconds(for entry: TimeEntry) -> Int? {
        if let stored = entry.durationSeconds {
            return stored
        }
        guard let endedAt = entry.endedAt else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(entry.startedAt).rounded()))
    }
    /// `has:notes` uses the notes-indicator rule: whitespace-only counts
    /// as empty (history-entry-list).
    private static func matchesPresence(_ group: HistorySearchGroup, entry: TimeEntry) -> Bool {
        let hasNotes = !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if group.mustHaveNotes, !hasNotes { return false }
        if group.mustLackNotes, hasNotes { return false }
        let hasCategory = !entry.categoryIDs.isEmpty
        if group.mustHaveCategory, !hasCategory { return false }
        if group.mustLackCategory, hasCategory { return false }
        return true
    }

    private static func matchesTerm(
        _ term: String,
        entry: TimeEntry,
        categories: [Category],
        fields: Set<HistorySearchField>
    ) -> Bool {
        if fields.contains(.name), containsMatch(in: entry.activityText, term: term) {
            return true
        }
        if fields.contains(.categories),
           categories.contains(where: { containsMatch(in: $0.name, term: term) }) {
            return true
        }
        if fields.contains(.notes), containsMatch(in: entry.notes, term: term) {
            return true
        }
        return false
    }

    static func containsMatch(in haystack: String, term: String) -> Bool {
        haystack.range(of: term, options: .caseInsensitive) != nil
    }

    /// All non-overlapping occurrences of `term` in `haystack` as
    /// original-string ranges. Never lowercases a copy: Unicode case
    /// mappings can change length, so lowercased offsets must not be
    /// reused (design D5).
    static func allRanges(in haystack: String, term: String) -> [Range<String.Index>] {
        guard !term.isEmpty, !haystack.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchFrom = haystack.startIndex
        while searchFrom < haystack.endIndex,
              let found = haystack.range(
                  of: term,
                  options: .caseInsensitive,
                  range: searchFrom ..< haystack.endIndex
              ) {
            ranges.append(found)
            if found.upperBound == searchFrom {
                break
            }
            searchFrom = found.upperBound
        }
        return ranges
    }

    /// Character offsets for a string's ranges. Offsets count Characters
    /// (graphemes), so slicing back at the same offsets is always safe.
    static func offsets(
        _ ranges: [Range<String.Index>],
        in string: String
    ) -> [Range<Int>] {
        ranges.map { range in
            string.distance(from: string.startIndex, to: range.lowerBound)
                ..< string.distance(from: string.startIndex, to: range.upperBound)
        }
    }

    /// Sorts by lower bound and merges overlapping or adjacent ranges.
    /// Forwards to the Core helper so feature code and the shared
    /// highlight component merge identically; kept so existing call sites
    /// read at the evaluator level.
    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        TextRanges.merged(ranges)
    }

    // MARK: - Snapshot derivation

    /// Filters a cached snapshot with one query and derives every match's
    /// presentation. Parse once per query, derive once per entry/snapshot
    /// — never in row bodies (design D1/D5).
    static func derive(
        entries: [TimeEntry],
        categoriesByID: [String: Category],
        query: HistorySearchQuery,
        calendar: Calendar = .current
    ) -> (matched: [TimeEntry], presentations: [String: HistorySearchRowPresentation]) {
        var matched: [TimeEntry] = []
        matched.reserveCapacity(entries.count)
        var presentations: [String: HistorySearchRowPresentation] = [:]
        for entry in entries {
            let entryCategories = entry.categoryIDs.compactMap { categoriesByID[$0] }
            guard matches(entry: entry, categories: entryCategories, query: query, calendar: calendar) else {
                continue
            }
            matched.append(entry)
            guard !query.textTerms.isEmpty else { continue }
            presentations[entry.id] = presentation(
                entry: entry,
                categories: entryCategories,
                caption: entryCategories.map(\.name).joined(separator: ", "),
                query: query
            )
        }
        return (matched, presentations)
    }

    // MARK: - Presentation derivation

    /// Derives one entry's highlight ranges and conditional notes excerpt.
    /// `caption` must be the exact string the row renders
    /// (`categories.map(\.name).joined(separator: ", ")`).
    static func presentation(
        entry: TimeEntry,
        categories: [Category],
        caption: String,
        query: HistorySearchQuery
    ) -> HistorySearchRowPresentation {
        var result = HistorySearchRowPresentation()
        if query.fields.contains(.name) {
            result.nameRanges = merged(nameRanges(entry: entry, terms: query.textTerms))
        }
        if query.fields.contains(.categories), !caption.isEmpty {
            result.captionRanges = captionRanges(
                categories: categories,
                caption: caption,
                terms: query.textTerms
            )
        }
        if query.fields.contains(.notes) {
            result.excerpt = HistorySearchExcerptBuilder.make(
                notes: entry.notes,
                terms: query.textTerms
            )
        }
        return result
    }

    private static func nameRanges(entry: TimeEntry, terms: [String]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for term in terms {
            ranges.append(contentsOf: offsets(
                allRanges(in: entry.activityText, term: term),
                in: entry.activityText
            ))
        }
        return ranges
    }

    /// Matches each category separately, then offsets its display ranges
    /// into the composed caption (design D5).
    private static func captionRanges(
        categories: [Category],
        caption: String,
        terms: [String]
    ) -> [Range<Int>] {
        var cursor = caption.startIndex
        var first = true
        var ranges: [Range<Int>] = []
        for category in categories {
            if !first {
                guard let sep = caption.range(
                    of: ", ",
                    range: cursor ..< caption.endIndex
                ) else { break }
                cursor = sep.upperBound
            }
            first = false
            cursor = appendCategoryRanges(
                category: category,
                caption: caption,
                cursor: cursor,
                terms: terms,
                ranges: &ranges
            )
        }
        return merged(clamped(ranges, count: caption.count))
    }

    private static func appendCategoryRanges(
        category: Category,
        caption: String,
        cursor: String.Index,
        terms: [String],
        ranges: inout [Range<Int>]
    ) -> String.Index {
        let base = caption.distance(from: caption.startIndex, to: cursor)
        for term in terms {
            for match in allRanges(in: category.name, term: term) {
                let lower = base + category.name.distance(
                    from: category.name.startIndex, to: match.lowerBound
                )
                let upper = base + category.name.distance(
                    from: category.name.startIndex, to: match.upperBound
                )
                ranges.append(lower ..< upper)
            }
        }
        return caption.index(
            cursor,
            offsetBy: category.name.count,
            limitedBy: caption.endIndex
        ) ?? caption.endIndex
    }

    private static func clamped(_ ranges: [Range<Int>], count: Int) -> [Range<Int>] {
        TextRanges.clamped(ranges, count: count)
    }
}
