import Testing
import Foundation
@testable import TimeOfLife

@Suite("HistorySearchEvaluation")
struct HistorySearchEvaluationTests {
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

    private func caption(for categories: [Category]) -> String {
        categories.map(\.name).joined(separator: ", ")
    }

    // MARK: - Matching (task 3.1)

    @Test("default scope matches names and categories, never notes")
    func defaultScopeNamesOnly() throws {
        let query = try parseQuery("Gym")
        let (named, noCats) = entry(name: "Morning Gym")
        #expect(HistorySearchEvaluator.matches(entry: named, categories: noCats, query: query))
        let (catOnly, cats) = entry(name: "Run", categories: ["Gymnastics"])
        #expect(HistorySearchEvaluator.matches(entry: catOnly, categories: cats, query: query))
        let (notesOnly, _) = entry(name: "Run", notes: "gym day")
        #expect(!HistorySearchEvaluator.matches(
            entry: notesOnly, categories: [], query: query
        ))
    }

    @Test("matching is case-insensitive but preserves identity")
    func caseInsensitiveIdentity() throws {
        let query = try parseQuery("gym")
        for name in ["Morning Gym", "GYM", "gym"] {
            let (record, cats) = entry(name: name)
            #expect(HistorySearchEvaluator.matches(entry: record, categories: cats, query: query))
            #expect(record.activityText == name)
        }
    }

    @Test("accent differences stay significant")
    func accentsSignificant() throws {
        let query = try parseQuery("cafe")
        let (record, cats) = entry(name: "café")
        #expect(!HistorySearchEvaluator.matches(entry: record, categories: cats, query: query))
        let accented = try parseQuery("café")
        #expect(HistorySearchEvaluator.matches(entry: record, categories: cats, query: accented))
    }

    @Test("every term must match somewhere in the selected fields")
    func termsCombineWithAND() throws {
        let query = try parseQuery("gym stretch in:name,notes")
        let (both, _) = entry(name: "Gym", notes: "stretching well")
        #expect(HistorySearchEvaluator.matches(entry: both, categories: [], query: query))
        let (nameOnly, _) = entry(name: "Gym", notes: "unrelated")
        #expect(!HistorySearchEvaluator.matches(entry: nameOnly, categories: [], query: query))
    }

    @Test("phrases require contiguity")
    func phraseContiguity() throws {
        let query = try parseQuery("\"morning gym\"")
        let (contiguous, _) = entry(name: "morning gym session")
        #expect(HistorySearchEvaluator.matches(entry: contiguous, categories: [], query: query))
        let (split, _) = entry(name: "morning run, gym later")
        #expect(!HistorySearchEvaluator.matches(entry: split, categories: [], query: query))
    }

    @Test("category matching inspects every attached category")
    func everyCategoryPosition() throws {
        let query = try parseQuery("sport in:categories")
        let (_, cats) = entry(name: "Trip", categories: ["Travel", "Sport club", "Food"])
        let record = entry(name: "Trip", categories: ["Travel", "Sport club", "Food"]).0
        #expect(HistorySearchEvaluator.matches(entry: record, categories: cats, query: query))
        let (firstOnly, firstCats) = entry(name: "Trip", categories: ["Sport", "Food"])
        #expect(HistorySearchEvaluator.matches(
            entry: firstOnly, categories: firstCats, query: query
        ))
    }

    @Test("substring matching needs no word boundaries")
    func substringMatching() throws {
        let query = try parseQuery("stretch in:notes")
        let (record, _) = entry(name: "Gym", notes: "stretching")
        #expect(HistorySearchEvaluator.matches(entry: record, categories: [], query: query))
    }

    @Test("scope-only queries impose no field-content constraint")
    func scopeOnlyMatchesAll() throws {
        let query = try parseQuery("in:notes")
        let (bare, _) = entry(name: "Gym", notes: "")
        #expect(HistorySearchEvaluator.matches(entry: bare, categories: [], query: query))
    }

    @Test("non-Latin scripts and emoji match literally")
    func nonLatinAndEmoji() throws {
        let cjk = try parseQuery("ランニング")
        let (record, _) = entry(name: "朝ランニング記録")
        #expect(HistorySearchEvaluator.matches(entry: record, categories: [], query: cjk))
        let emoji = try parseQuery("🏃")
        let (emojiRecord, _) = entry(name: "Run 🏃 fast")
        #expect(HistorySearchEvaluator.matches(entry: emojiRecord, categories: [], query: emoji))
    }

    // MARK: - Highlight ranges (task 3.2)

    private func slice(_ string: String, _ range: Range<Int>) -> String {
        let lower = string.index(string.startIndex, offsetBy: range.lowerBound)
        let upper = string.index(string.startIndex, offsetBy: range.upperBound)
        return String(string[lower ..< upper])
    }

    @Test("name ranges point at original-string occurrences")
    func nameRanges() throws {
        let query = try parseQuery("gym")
        let (record, _) = entry(name: "Gym and gym")
        let presentation = HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query)
        #expect(presentation.nameRanges.count == 2)
        #expect(presentation.nameRanges.map { slice(record.activityText, $0) } == ["Gym", "gym"])
        #expect(presentation.captionRanges.isEmpty)
        #expect(presentation.excerpt == nil)
    }

    @Test("repeated matches produce every occurrence")
    func repeatedMatches() throws {
        let ranges = HistorySearchEvaluator.offsets(
            HistorySearchEvaluator.allRanges(in: "aaaa", term: "aa"),
            in: "aaaa"
        )
        #expect(ranges == [0 ..< 2, 2 ..< 4])
    }

    @Test("overlapping display ranges merge")
    func mergedRanges() {
        #expect(HistorySearchEvaluator.merged([0 ..< 3, 2 ..< 5, 8 ..< 9]) == [0 ..< 5, 8 ..< 9])
    }

    @Test("caption ranges offset each category into the composed caption")
    func captionOffsets() throws {
        let query = try parseQuery("or in:categories")
        let (record, cats) = entry(name: "Trip", categories: ["Work", "Morning", "Sport"])
        let text = caption(for: cats)
        #expect(text == "Work, Morning, Sport")
        let presentation = HistorySearchEvaluator.presentation(
            entry: record, categories: cats, caption: text, query: query
        )
        #expect(presentation.nameRanges.isEmpty)
        let slices = presentation.captionRanges.map { slice(text, $0) }
        #expect(slices == ["or", "or", "or"])
        // Real invariant (clamping alone cannot guarantee it): ranges land
        // inside category names, never on a ", " separator. Separators are
        // derived from the fixture so the guard cannot drift.
        var separators: [Range<Int>] = []
        var searchStart = text.startIndex
        while let sep = text.range(of: ", ", range: searchStart ..< text.endIndex) {
            separators.append(
                text.distance(from: text.startIndex, to: sep.lowerBound)
                    ..< text.distance(from: text.startIndex, to: sep.upperBound)
            )
            searchStart = sep.upperBound
        }
        #expect(separators == [4 ..< 6, 13 ..< 15])
        for range in presentation.captionRanges {
            #expect(!separators.contains { $0.overlaps(range) })
        }
    }

    @Test("out-of-scope fields receive no ranges")
    func outOfScopeExcluded() throws {
        let query = try parseQuery("gym in:name")
        let (record, cats) = entry(name: "Gym", categories: ["Gym"], notes: "gym")
        let presentation = HistorySearchEvaluator.presentation(
            entry: record,
            categories: cats,
            caption: caption(for: cats),
            query: query
        )
        #expect(presentation.nameRanges.count == 1)
        #expect(presentation.captionRanges.isEmpty)
        #expect(presentation.excerpt == nil)
    }

    @Test("date-only and scope-only queries show no highlights")
    func noHighlightsWithoutTerms() throws {
        let dated = try parseQuery("started:2026-10-01")
        let (record, cats) = entry(name: "Gym", categories: ["Gym"], notes: "gym")
        let presentation = HistorySearchEvaluator.presentation(
            entry: record,
            categories: cats,
            caption: caption(for: cats),
            query: dated
        )
        #expect(!presentation.hasVisibleHighlights)
        let scoped = try parseQuery("in:notes")
        let scopedPresentation = HistorySearchEvaluator.presentation(
            entry: record, categories: cats, caption: "", query: scoped
        )
        #expect(!scopedPresentation.hasVisibleHighlights)
    }

    @Test("case mappings with different lengths keep valid ranges")
    func trickyCaseMapping() throws {
        let query = try parseQuery("ss")
        let (record, _) = entry(name: "Straße")
        let presentation = HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query)
        // A lost ß→ss fold must fail loudly, not pass with zero ranges.
        #expect(!presentation.nameRanges.isEmpty, "case-mapped match must still yield a range")
        for range in presentation.nameRanges {
            let piece = slice(record.activityText, range)
            #expect(!piece.isEmpty)
        }
    }

    @Test("composed and decomposed forms match their own normalization")
    func composedForms() throws {
        let composed = "caf\u{E9}"
        let query = try parseQuery(composed)
        let (record, _) = entry(name: composed)
        #expect(HistorySearchEvaluator.matches(entry: record, categories: [], query: query))
        let presentation = HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query)
        #expect(presentation.nameRanges.map { slice(composed, $0) } == [composed])
    }

    // MARK: - Notes excerpts (task 3.3)

    @Test("a deep match yields a bounded excerpt with both ellipses")
    func deepMatchExcerpt() throws {
        let query = try parseQuery("squats in:notes")
        let notes = String(repeating: "warmup routine text filler ", count: 8)
            + "squats "
            + String(repeating: "cooldown routine text filler ", count: 8)
        let (record, _) = entry(name: "Gym", notes: notes)
        let presentation = HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query)
        let excerpt = try #require(presentation.excerpt)
        #expect(excerpt.text.hasPrefix("…"))
        #expect(excerpt.text.hasSuffix("…"))
        #expect(excerpt.text.count < notes.count)
        #expect(excerpt.text.contains("squats"))
        let hits = excerpt.highlights.map { slice(excerpt.text, $0) }
        #expect(hits.contains("squats"))
    }

    @Test("leading and trailing hits omit only the kept-side ellipsis")
    func edgeHitExcerpts() throws {
        let query = try parseQuery("alpha in:notes")
        let (leading, _) = entry(name: "Gym", notes: "alpha " + String(repeating: "filler ", count: 40))
        let leadingExcerpt = try #require(HistorySearchEvaluator.presentation(
            entry: leading, categories: [], caption: "", query: query
        ).excerpt)
        #expect(!leadingExcerpt.text.hasPrefix("…"))
        #expect(leadingExcerpt.text.hasSuffix("…"))

        let (trailing, _) = entry(name: "Gym", notes: String(repeating: "filler ", count: 40) + "alpha")
        let trailingExcerpt = try #require(HistorySearchEvaluator.presentation(
            entry: trailing, categories: [], caption: "", query: query
        ).excerpt)
        #expect(trailingExcerpt.text.hasPrefix("…"))
        #expect(!trailingExcerpt.text.hasSuffix("…"))
    }

    @Test("short notes render whole with no ellipses")
    func shortNotesWhole() throws {
        let query = try parseQuery("belt in:notes")
        let (record, _) = entry(name: "Gym", notes: "remember the HR belt")
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(excerpt.text == "remember the HR belt")
        #expect(excerpt.highlights.map { slice(excerpt.text, $0) } == ["belt"])
    }

    @Test("multiline Markdown collapses to literal display text")
    func multilineMarkdownExcerpt() throws {
        let query = try parseQuery("squats in:notes")
        let (record, _) = entry(name: "Gym", notes: "**Sets**\n\n- pullups\n- squats x10\n\ndone 🎉")
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(!excerpt.text.contains("\n"))
        #expect(excerpt.text.contains("squats"))
        #expect(excerpt.text.contains("**Sets**"))
        let hits = excerpt.highlights.map { slice(excerpt.text, $0) }
        #expect(hits.contains("squats"))
    }

    @Test("CJK text without spaces still centers the focal match")
    func cjkExcerpt() throws {
        let query = try parseQuery("深蹲 in:notes")
        let notes = String(repeating: "热身准备活动内容填充", count: 10)
            + "深蹲十次"
            + String(repeating: "放松整理活动内容填充", count: 10)
        let (record, _) = entry(name: "Gym", notes: notes)
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(excerpt.text.contains("深蹲"))
        let hits = excerpt.highlights.map { slice(excerpt.text, $0) }
        #expect(hits.contains("深蹲"))
    }

    @Test("emoji survive excerpt clipping intact")
    func emojiExcerpt() throws {
        let query = try parseQuery("belt in:notes")
        let (record, _) = entry(
            name: "Gym",
            notes: String(repeating: "🏃 warmup filler text here ", count: 10) + "belt 🎉"
        )
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(excerpt.text.contains("belt"))
        for range in excerpt.highlights {
            #expect(!slice(excerpt.text, range).isEmpty)
        }
    }

    @Test("the earliest occurrence anchors the excerpt")
    func earliestAnchorsExcerpt() throws {
        let query = try parseQuery("run in:notes")
        let notes = "run start " + String(repeating: "filler text here ", count: 30) + "run end"
        let (record, _) = entry(name: "Gym", notes: notes)
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(!excerpt.text.hasPrefix("…"))
        #expect(excerpt.text.hasSuffix("…"))
        #expect(excerpt.text.contains("run start"))
    }

    @Test("very long focal terms are preserved past the context budget")
    func longFocalTermPreserved() throws {
        let term = String(repeating: "a", count: 200)
        let query = try parseQuery("\(term) in:notes")
        let (record, _) = entry(name: "Gym", notes: "prefix \(term) suffix")
        let excerpt = try #require(HistorySearchEvaluator.presentation(entry: record, categories: [], caption: "", query: query).excerpt)
        #expect(excerpt.text.contains(term))
    }

    @Test("no excerpt without notes scope or without a notes hit")
    func excerptGating() throws {
        let nameOnly = try parseQuery("gym")
        let (record, cats) = entry(name: "Gym", notes: "gym notes here")
        #expect(HistorySearchEvaluator.presentation(
            entry: record, categories: cats, caption: "", query: nameOnly
        ).excerpt == nil)
        let notesScope = try parseQuery("absent in:notes")
        #expect(HistorySearchEvaluator.presentation(
            entry: record, categories: cats, caption: "", query: notesScope
        ).excerpt == nil)
    }

    // MARK: - Row accessibility (task 4.5)

    @Test("the row label reads the displayed excerpt, not the full note")
    func excerptAccessibilityLabel() {
        let label = EntryRow.accessibilityLabel(
            entryText: "Gym",
            categoryNames: "Health",
            timeframeText: "14:00 – 15:20",
            durationText: "1h 20m",
            isInProgress: false,
            viaText: "",
            hasNotes: true,
            excerptText: "… around squats …"
        )
        #expect(label.contains("… around squats …"))
        #expect(label.contains(L10n.historyHasNotes.text))
    }
}
