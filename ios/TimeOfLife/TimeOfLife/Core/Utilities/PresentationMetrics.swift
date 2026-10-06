import Foundation
import SwiftUI

/// Shared presentation-settle delay before programmatic focus (sheet push
/// and picker push alike): focusing instantly fires the keyboard
/// mid-transition and the keyboard-driven relayout jumps. One constant —
/// the former per-screen `focusDelayNanoseconds` duplicates.
enum FocusDelay {
    /// Push/sheet-transition settle before autofocus (400ms).
    static let settleNanoseconds: UInt64 = 400_000_000

    /// Sleeps through the transition settle; returns false when cancelled
    /// (popped/dismissed mid-wait) so callers skip the focus.
    @discardableResult
    static func settle() async -> Bool {
        try? await Task.sleep(nanoseconds: settleNanoseconds)
        return !Task.isCancelled
    }
}

/// Shared Dynamic Type icon-slot metrics: a fixed slot sized from the
/// scaled glyph (`basePointSize × multiplier`, ceiled) built from a trait
/// collection matching the SwiftUI environment's effective size — so slots
/// track rendering under `.dynamicTypeSize` overrides too. The former
/// per-screen `symbolSlotSize` duplicates, one idiom.
enum DynamicTypeMetrics {
    /// UITextView's default text origin: container top inset (8) plus
    /// line-fragment padding (5). `editorHeight` budgets the vertical
    /// half and placeholder overlays align to the full origin — one
    /// source so the two can never silently drift.
    static let editorTextOriginInsets = (top: CGFloat(8), leading: CGFloat(5))

    /// UITextView's default vertical text-container insets (8 top + 8
    /// bottom): a fixed-height `TextEditor` must add these on top of the
    /// text height or the last reserved line clips.
    private static let textEditorVerticalInsets: CGFloat = 16

    /// Fixed icon slot for a glyph of `basePointSize` at `textStyle`,
    /// widened by `multiplier` (the 1.5× slot both lists use).
    static func symbolSlotSize(
        basePointSize: CGFloat,
        textStyle: UIFont.TextStyle,
        dynamicTypeSize: DynamicTypeSize,
        multiplier: CGFloat = 1.5
    ) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        let trait = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        let pointSize = metrics.scaledFont(
            for: UIFont.systemFont(ofSize: basePointSize),
            compatibleWith: trait
        ).pointSize
        return ceil(pointSize * multiplier)
    }

    /// Fixed `TextEditor` height reserving `lines` of `textStyle` text:
    /// scaled line height × lines plus the editor's vertical insets,
    /// ceiled — so a line reserve tracks Dynamic Type (pass the view's
    /// `dynamicTypeSize` so overrides recompute it) instead of freezing a
    /// point value. Content past the reserve scrolls inside the editor.
    static func editorHeight(
        lines: Int,
        textStyle: UIFont.TextStyle,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        let trait = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        let lineHeight = UIFont.preferredFont(
            forTextStyle: textStyle,
            compatibleWith: trait
        ).lineHeight
        return ceil(lineHeight * CGFloat(max(lines, 1)) + textEditorVerticalInsets)
    }
}
