import SwiftUI

/// Marker attribute for History search matches. Carried on matched `Text`
/// runs so `SearchMatchRenderer` can paint their background (design D5).
struct SearchMatchAttribute: TextAttribute {}

/// Paints the semantic accent wash behind runs carrying
/// `SearchMatchAttribute` and draws everything else normally. Styling
/// resolves `Theme` at render time, so appearance/contrast changes need no
/// reparsing. Limited to highlighted text — never installed screen-wide.
struct SearchMatchRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[SearchMatchAttribute.self] != nil {
                    context.fill(
                        Path(run.typographicBounds.rect),
                        with: .color(Theme.accentPrimary.opacity(Theme.opacityAccentSoft))
                    )
                }
                context.draw(run)
            }
        }
    }
}

/// Renders `text` with character-offset `highlights` as emphasized runs over
/// the accent wash (Design/COMPONENTS.md, history-search spec). Offsets
/// count Characters in `text`; out-of-range values are clamped and empty
/// ranges dropped. With no effective highlights this is plain `Text`.
/// The row keeps a single accessibility element — this view adds none.
struct SearchHighlightedText: View {
    let text: String
    let highlights: [Range<Int>]

    var body: some View {
        // Clamp/merge via the Core helper, not the feature-layer evaluator:
        // this component must stay usable without the search feature, and
        // the presentation derivation already merges once per query — this
        // pass only guards directly supplied ranges.
        let clamped = TextRanges.merged(TextRanges.clamped(highlights, count: text.count))
        if clamped.isEmpty {
            Text(text)
        } else {
            highlighted(text: text, ranges: clamped)
                .textRenderer(SearchMatchRenderer())
        }
    }

    private func highlighted(text: String, ranges: [Range<Int>]) -> Text {
        var segments: [Text] = []
        var cursor = 0
        for range in ranges {
            if cursor < range.lowerBound {
                segments.append(Text(stringSlice(text, range: cursor ..< range.lowerBound)))
            }
            segments.append(
                Text(stringSlice(text, range: range))
                    .bold()
                    .customAttribute(SearchMatchAttribute())
            )
            cursor = range.upperBound
        }
        if cursor < text.count {
            segments.append(Text(stringSlice(text, range: cursor ..< text.count)))
        }
        return segments.reduce(Text(""), +)
    }

    private func stringSlice(_ text: String, range: Range<Int>) -> String {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return String(text[lower ..< upper])
    }
}

#if DEBUG
#Preview("Search highlight") {
    VStack(alignment: .leading) {
        SearchHighlightedText(text: "Morning Gym", highlights: [8 ..< 11])
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
        SearchHighlightedText(text: "Health, Morning", highlights: [9 ..< 16])
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}
#endif
