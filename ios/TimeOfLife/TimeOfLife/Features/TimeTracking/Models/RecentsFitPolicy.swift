import Foundation

/// Newest-prefix fit policy for Track Recents (fit-track-recents): selects
/// which candidates to mount and whether they need internal scrolling, from
/// the actual packed chip sizes at the current width. Pure and `nonisolated`
/// so the count/scroll contract is unit-testable without a host view.
///
/// Contract (timer-capture-experience delta):
/// - `C == N` (all candidates fit) → show all, no scrolling — even for
///   fewer than five.
/// - `C >= 5` → show exactly the fitting prefix, no scrolling.
/// - Otherwise → offer only the newest five (or all available when fewer
///   exist), scrolling internally only when that set actually overflows.
/// Counts chips, never rows; never skips a newer chip for an older one.
/// Omitted chips are never mounted, so they cannot stay tappable or
/// VoiceOver-discoverable.
enum RecentsFitPolicy {
    /// Fallback offer size when fewer than five candidates fit.
    static let fallbackCount = 5

    /// The mounting plan for one layout pass.
    struct Plan: Equatable {
        /// Newest-first prefix length to mount.
        var offered: Int
        /// Whether to mount the internal scroller (plain flow otherwise).
        var scrolling: Bool
        /// Scroll-viewport cap (nil when not scrolling).
        var viewport: CGFloat?
    }

    /// One-usable-row floor at the active text size plus border clearance:
    /// the minimum viewport that keeps a full chip tap target visible.
    /// - Parameter rowHeight: one chip row at the active Dynamic Type size
    ///   (already floored at the 44 pt tap target by the caller).
    nonisolated static func floorHeight(rowHeight: CGFloat) -> CGFloat {
        let row = rowHeight.isFinite ? max(0, rowHeight) : 0
        return max(row, Theme.minTapArea) + ChipViewport.borderBleed
    }

    /// Bounded provisional plan for missing/invalid geometry (nil budget,
    /// unmeasured width): at most the fallback five in a one-row viewport.
    /// The viewport hugs smaller content (`fixedSize` in the view), so small
    /// sets never reserve dead space while measuring.
    /// - Parameter maxCandidates: Track's exact-text candidate cap, passed in
    ///   by the view call site (which reads `TrackViewModel.recentsLimit`).
    ///   Threaded as a parameter — never read off the `@MainActor` view
    ///   model — so the policy stays a pure, `nonisolated` Models-layer unit.
    nonisolated static func provisional(
        candidateCount: Int,
        rowHeight: CGFloat,
        maxCandidates: Int
    ) -> Plan {
        let total = min(max(0, candidateCount), maxCandidates)
        guard total > 0 else { return Plan(offered: 0, scrolling: false, viewport: nil) }
        return Plan(
            offered: min(fallbackCount, total),
            scrolling: true,
            viewport: floorHeight(rowHeight: rowHeight)
        )
    }

    /// Resolves the mounting plan from measured chip sizes.
    /// - Parameter itemSizes: measured chip sizes, newest-first.
    /// - Parameter containerWidth: the chip-area width. Non-positive or
    ///   non-finite values are a measurement state: bounded provisional plan.
    /// - Parameter spacing: the inter-chip/row gap used for packing.
    /// - Parameter budget: the finite chip-area height budget (the same
    ///   deductions the viewport uses: caption, gaps, clearance, safe area).
    ///   Nil, non-positive, or non-finite values are a measurement state.
    /// - Parameter rowHeight: one chip row at the active text size.
    /// - Parameter maxCandidates: Track's exact-text candidate cap, passed in
    ///   by the view call site (see `provisional`).
    nonisolated static func plan(
        itemSizes: [CGSize],
        containerWidth: CGFloat,
        spacing: CGFloat,
        budget: CGFloat?,
        rowHeight: CGFloat,
        maxCandidates: Int
    ) -> Plan {
        let floor = floorHeight(rowHeight: rowHeight)
        let total = min(itemSizes.count, maxCandidates)
        guard total > 0 else { return Plan(offered: 0, scrolling: false, viewport: nil) }
        guard containerWidth.isFinite, containerWidth > 0,
              let budget, budget.isFinite, budget > 0
        else {
            return provisional(candidateCount: itemSizes.count, rowHeight: rowHeight, maxCandidates: maxCandidates)
        }
        let sizes = Array(itemSizes.prefix(total))
        let contentBudget = max(0, budget - ChipViewport.borderBleed)
        let fitting = FlowPacking.fittingPrefixCount(
            itemSizes: sizes,
            maxWidth: containerWidth,
            spacing: spacing,
            budget: contentBudget
        )
        if fitting >= total {
            return Plan(offered: total, scrolling: false, viewport: nil)
        }
        if fitting >= fallbackCount {
            return Plan(offered: fitting, scrolling: false, viewport: nil)
        }
        let offered = min(fallbackCount, total)
        let offeredHeight = FlowPacking.totalHeight(
            rows: FlowPacking.pack(
                itemSizes: Array(sizes.prefix(offered)),
                maxWidth: containerWidth,
                spacing: spacing
            ),
            spacing: spacing
        )
        let viewport = min(offeredHeight + ChipViewport.borderBleed, max(budget, floor))
        // Scroll only when the offered set actually overflows its viewport.
        if offeredHeight + ChipViewport.borderBleed <= viewport + 0.5 {
            return Plan(offered: offered, scrolling: false, viewport: nil)
        }
        return Plan(offered: offered, scrolling: true, viewport: viewport)
    }
}
