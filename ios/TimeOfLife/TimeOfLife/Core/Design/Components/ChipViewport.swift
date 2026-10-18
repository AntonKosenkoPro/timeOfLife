import SwiftUI

/// Shared chip-group viewport contract (inline-category-creation):
/// `TagSelector` and `RecentActivitiesChips` share the same flexible
/// viewport (hug content, grow into available slack, scroll internally
/// beyond it) and the same edge-aware hairline dividers. Scroll-edge
/// derivation is shared so the two groups behave identically.
enum ChipViewport {
    /// Scroll-edge state driving the dividers: the top divider shows only
    /// once content scrolled under it, the bottom one only while content
    /// remains below. Both stay hidden when everything fits.
    struct Edges: Equatable {
        var atTop = true
        var atEnd = true
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
