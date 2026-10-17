import SwiftUI

/// Shared chip-group viewport metrics + scroll-edge state
/// (inline-category-creation): `TagSelector` and `RecentActivitiesChips`
/// clamp to the same 3.5 visible rows and fade the same hairline edge
/// dividers. Row heights stay caller-owned (different chip typography);
/// the clamp math and edge derivation are shared so the two groups behave
/// identically.
enum ChipViewport {
    /// Visible-row clamp: three full rows plus the half-row peek that
    /// signals scrollability.
    static let maxVisibleRows: CGFloat = 3.5

    /// Scroll-edge state driving the dividers: the top divider shows only
    /// once content scrolled under it, the bottom one only while content
    /// remains below. Both stay hidden when everything fits.
    struct Edges: Equatable {
        var atTop = true
        var atEnd = true
    }

    /// Viewport height for the row clamp: full rows plus inter-row gaps.
    /// Pure and `nonisolated` so the clamp math is unit-testable.
    nonisolated static func clampedHeight(rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        maxVisibleRows * rowHeight + (ceil(maxVisibleRows) - 1) * spacing
    }

    /// Derives the edge state from scroll geometry. Pure and `nonisolated`
    /// so the divider contract is unit-testable. The half-point tolerance
    /// absorbs float noise at the exact edges.
    nonisolated static func edges(
        offsetY: CGFloat,
        containerHeight: CGFloat,
        contentHeight: CGFloat
    ) -> Edges {
        Edges(
            atTop: offsetY <= 0.5,
            atEnd: offsetY + containerHeight >= contentHeight - 0.5
        )
    }
}
