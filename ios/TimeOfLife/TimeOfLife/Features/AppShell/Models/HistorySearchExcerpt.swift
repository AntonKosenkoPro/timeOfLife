import Foundation

// MARK: - Notes excerpt (design D6)

/// One bounded excerpt around the earliest in-scope notes hit.
enum HistorySearchExcerptBuilder {
    static let leadingContext = 48
    static let trailingContext = 48

    /// Returns nil when notes hold no positive term match. Display text
    /// collapses whitespace runs to one space and adds `…` only at ends
    /// where content was omitted.
    static func make(notes: String, terms: [String]) -> HistorySearchExcerpt? {
        let matches = allMatches(notes: notes, terms: terms)
        guard let focal = earliestMatch(in: matches) else { return nil }
        let window = excerptWindow(notes: notes, focal: focal)
        let (display, mapping) = trimmedDisplay(
            notes: notes,
            window: window
        )
        let highlights = translateHighlights(
            matches: matches,
            notes: notes,
            window: window,
            mapping: mapping
        )
        var text = display
        var shifted = highlights
        if window.lowerBound > notes.startIndex {
            text = "…" + text
            shifted = shifted.map { ($0.lowerBound + 1) ..< ($0.upperBound + 1) }
        }
        if window.upperBound < notes.endIndex {
            text += "…"
        }
        return HistorySearchExcerpt(
            text: text,
            highlights: HistorySearchEvaluator.merged(shifted)
        )
    }

    private static func earliestMatch(in matches: [NotesMatch]) -> NotesMatch? {
        matches.min { first, second in
            first.lowerBound != second.lowerBound
                ? first.lowerBound < second.lowerBound
                : first.upperBound > second.upperBound
        }
    }

    private static func excerptWindow(
        notes: String,
        focal: NotesMatch
    ) -> Range<String.Index> {
        var start = notes.index(
            focal.lowerBound,
            offsetBy: -leadingContext,
            limitedBy: notes.startIndex
        ) ?? notes.startIndex
        var end = notes.index(
            focal.upperBound,
            offsetBy: trailingContext,
            limitedBy: notes.endIndex
        ) ?? notes.endIndex
        // Prefer whitespace boundaries without assuming space-delimited
        // languages; never shrink past the focal match.
        if start > notes.startIndex,
           let boundary = firstWhitespace(in: start ..< focal.lowerBound, of: notes) {
            start = notes.index(after: boundary)
        }
        if end < notes.endIndex,
           let boundary = lastWhitespace(in: focal.upperBound ..< end, of: notes) {
            end = boundary
        }
        return start ..< end
    }

    private static func trimmedDisplay(
        notes: String,
        window: Range<String.Index>
    ) -> (String, [Int]) {
        let (collapsed, rawMapping) = collapsedDisplay(notes: notes, window: window)
        // Drop one trailing collapsed space so excerpts never end in
        // whitespace before a suffix ellipsis or the row edge.
        guard collapsed.last?.isWhitespace == true else {
            return (collapsed, rawMapping)
        }
        var display = collapsed
        display.removeLast()
        return (display, rawMapping.map { min($0, display.count) })
    }

    private static func translateHighlights(
        matches: [NotesMatch],
        notes: String,
        window: Range<String.Index>,
        mapping: [Int]
    ) -> [Range<Int>] {
        let windowLower = notes.distance(from: notes.startIndex, to: window.lowerBound)
        let windowUpper = notes.distance(from: notes.startIndex, to: window.upperBound)
        var highlights: [Range<Int>] = []
        for match in matches {
            let lower = max(
                notes.distance(from: notes.startIndex, to: match.lowerBound),
                windowLower
            )
            let upper = min(
                notes.distance(from: notes.startIndex, to: match.upperBound),
                windowUpper
            )
            guard lower < upper else { continue }
            let displayLower = mapping[lower - windowLower]
            let displayUpper = mapping[upper - windowLower]
            guard displayLower < displayUpper else { continue }
            highlights.append(displayLower ..< displayUpper)
        }
        return highlights
    }

    private struct NotesMatch {
        var lowerBound: String.Index
        var upperBound: String.Index
    }

    private static func allMatches(notes: String, terms: [String]) -> [NotesMatch] {
        var out: [NotesMatch] = []
        for term in terms where !term.isEmpty {
            for range in HistorySearchEvaluator.allRanges(in: notes, term: term) {
                out.append(NotesMatch(lowerBound: range.lowerBound, upperBound: range.upperBound))
            }
        }
        return out
    }

    private static func firstWhitespace(
        in range: Range<String.Index>,
        of string: String
    ) -> String.Index? {
        var index = range.lowerBound
        while index < range.upperBound {
            if string[index].isWhitespace {
                return index
            }
            index = string.index(after: index)
        }
        return nil
    }

    private static func lastWhitespace(
        in range: Range<String.Index>,
        of string: String
    ) -> String.Index? {
        var index = range.upperBound
        while index > range.lowerBound {
            index = string.index(before: index)
            if string[index].isWhitespace {
                return index
            }
        }
        return nil
    }

    /// Collapses each maximal whitespace run in the window to one space.
    /// Returns the display string plus, for each original character offset
    /// relative to the window start, the display offset it produced (plus a
    /// trailing sentinel mapping the window end to `display.count`).
    private static func collapsedDisplay(
        notes: String,
        window: Range<String.Index>
    ) -> (String, [Int]) {
        var display = ""
        display.reserveCapacity(notes.distance(from: window.lowerBound, to: window.upperBound))
        var mapping: [Int] = []
        var inWhitespace = false
        var index = window.lowerBound
        while index < window.upperBound {
            let char = notes[index]
            if char.isWhitespace {
                // The collapsed space's own display index (pre-append);
                // continuation chars collapse to the current end.
                mapping.append(display.count)
                if !inWhitespace, !display.isEmpty {
                    display.append(" ")
                }
                inWhitespace = true
            } else {
                display.append(char)
                mapping.append(display.count - 1)
                inWhitespace = false
            }
            index = notes.index(after: index)
        }
        mapping.append(display.count)
        return (display, mapping)
    }
}
