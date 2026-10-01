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
}
