import Foundation

/// Character-offset range helpers shared by History search derivation and
/// the highlight-rendering component (history-search spec, design D5).
/// Lives in Core so `Core/Design/Components` never imports feature-layer
/// types: `SearchHighlightedText` clamps/merges here, and the search
/// evaluator funnels its own merge/clamp through the same helpers.
enum TextRanges {
    /// Sorts by lower bound and merges overlapping or adjacent ranges.
    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.sorted {
            $0.lowerBound < $1.lowerBound || ($0.lowerBound == $1.lowerBound && $0.upperBound < $1.upperBound)
        }
        var out: [Range<Int>] = []
        for range in sorted {
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// Clamps every range to `0 ..< count`, dropping empty results.
    static func clamped(_ ranges: [Range<Int>], count: Int) -> [Range<Int>] {
        ranges.compactMap { range in
            let lower = max(0, min(range.lowerBound, count))
            let upper = max(0, min(range.upperBound, count))
            guard lower < upper else { return nil }
            return lower ..< upper
        }
    }
}
