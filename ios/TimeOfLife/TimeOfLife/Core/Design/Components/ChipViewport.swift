import SwiftUI

/// Shared chip-group viewport contract (inline-category-creation):
/// `TagSelector` and `RecentActivitiesChips` clamp to the same fixed row
/// budget with internal scroll, hug smaller content (no dead space), and
/// fade the same edge-aware hairline dividers. Clamp math and edge
/// derivation are shared so the two groups behave identically.
enum ChipViewport {
    /// Visible-row clamp: four full rows. Fixed points (not available
    /// slack): the host is an outer `ScrollView` with unbounded offers, so
    /// a flexible cap would claim the full content height and slide under
    /// the tab bar.
    static let maxVisibleRows: CGFloat = 4
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
