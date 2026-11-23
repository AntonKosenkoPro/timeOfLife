import Testing
import Foundation
@testable import TimeOfLife

// MARK: - Helpers

/// Single-column chip sizes: each chip fills the container width, so every
/// chip takes its own row — `k` fitting chips need
/// `k * height + (k - 1) * spacing` content height.
private func columnSizes(_ count: Int, width: CGFloat = 100, height: CGFloat = 44) -> [CGSize] {
    Array(repeating: CGSize(width: width, height: height), count: count)
}

/// Budget that fits exactly `rows` single-column chips (plus clearance).
private func budgetForRows(_ rows: Int, height: CGFloat = 44, spacing: CGFloat = 8) -> CGFloat {
    CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * spacing + ChipViewport.borderBleed
}

private let fitWidth: CGFloat = 100
private let fitSpacing: CGFloat = 8
private let fitRow: CGFloat = 44
private let fitFloor = fitRow + ChipViewport.borderBleed // 46

@Suite("RecentsFitPolicy.counts")
struct RecentsFitPolicyCountsTests {
    @Test("zero candidates offer nothing and never scroll")
    func zeroCandidates() {
        let plan = RecentsFitPolicy.plan(
            itemSizes: [], containerWidth: fitWidth, spacing: fitSpacing,
            budget: 1000, rowHeight: fitRow
        )
        #expect(plan == RecentsFitPolicy.Plan(offered: 0, scrolling: false, viewport: nil))
    }

    @Test("candidate counts 1 through 12 clamp at the ten cap when all fit")
    func countsClampAtTen() {
        for count in 1...12 {
            let plan = RecentsFitPolicy.plan(
                itemSizes: columnSizes(count), containerWidth: 10_000, spacing: fitSpacing,
                budget: 100_000, rowHeight: fitRow
            )
            #expect(plan.offered == min(count, 10), "count \(count)")
            #expect(plan.scrolling == false, "count \(count)")
            #expect(plan.viewport == nil, "count \(count)")
        }
    }

    @Test("small all-fit sets show everything without scrolling")
    func smallAllFit() {
        for count in 1...4 {
            let plan = RecentsFitPolicy.plan(
                itemSizes: columnSizes(count), containerWidth: fitWidth, spacing: fitSpacing,
                budget: budgetForRows(count), rowHeight: fitRow
            )
            #expect(plan.offered == count, "count \(count)")
            #expect(plan.scrolling == false, "count \(count)")
        }
    }

    @Test("fewer than five available candidates still overflow internally")
    func fewerThanFiveOverflow() {
        let plan = RecentsFitPolicy.plan(
            itemSizes: columnSizes(3), containerWidth: fitWidth, spacing: fitSpacing,
            budget: ChipViewport.borderBleed, rowHeight: fitRow
        )
        #expect(plan.offered == 3)
        #expect(plan.scrolling == true)
        #expect(plan.viewport == fitFloor)
    }

    @Test("ten candidates with four fitting offer exactly the newest five")
    func tenCandidatesFourFit() {
        let plan = RecentsFitPolicy.plan(
            itemSizes: columnSizes(10), containerWidth: fitWidth, spacing: fitSpacing,
            budget: budgetForRows(4), rowHeight: fitRow
        )
        #expect(plan.offered == 5)
        #expect(plan.scrolling == true)
        #expect(plan.viewport == budgetForRows(4))
    }
}

@Suite("RecentsFitPolicy.fits")
struct RecentsFitPolicyFitsTests {
    @Test("fitting counts 0, 1, 4, 5, 7, 9, 10 resolve per the contract")
    func fitTable() {
        // (fitting chips, expected offered, expected scrolling)
        let cases: [(Int, Int, Bool)] = [
            (0, 5, true),
            (1, 5, true),
            (4, 5, true),
            (5, 5, false),
            (7, 7, false),
            (9, 9, false),
            (10, 10, false),
        ]
        for (fitting, offered, scrolling) in cases {
            let plan = RecentsFitPolicy.plan(
                itemSizes: columnSizes(10), containerWidth: fitWidth, spacing: fitSpacing,
                budget: budgetForRows(fitting), rowHeight: fitRow
            )
            #expect(plan.offered == offered, "fitting \(fitting)")
            #expect(plan.scrolling == scrolling, "fitting \(fitting)")
            #expect((plan.viewport == nil) == !scrolling, "fitting \(fitting)")
        }
    }

    @Test("newest five offered but fitting one row still mounts statically")
    func fiveOfferedOneRowFloor() {
        // Five 46pt chips pack into a single 44pt row. A 45pt budget fits
        // none of them by content, yet the offered set fits the one-row
        // floor — so the newest-five fallback mounts statically instead of
        // scrolling (the `offeredHeight + bleed <= viewport + 0.5` branch).
        let sizes = Array(repeating: CGSize(width: 46, height: 44), count: 5)
        let plan = RecentsFitPolicy.plan(
            itemSizes: sizes, containerWidth: 5 * 46 + 4 * 8, spacing: fitSpacing,
            budget: 45, rowHeight: fitRow
        )
        #expect(plan.offered == 5)
        #expect(plan.scrolling == false)
        #expect(plan.viewport == nil)
    }

    @Test("floor clamps a sub-tap-target row up to the tap target")
    func floorClampsBelowTapTarget() {
        #expect(
            RecentsFitPolicy.floorHeight(rowHeight: 20)
                == Theme.minTapArea + ChipViewport.borderBleed
        )
    }

    @Test("a multi-column fit offers the whole fitting prefix without scroll")
    func multiColumnFit() {
        // Two 46pt chips per 100pt row: ten chips pack into five rows.
        let sizes = Array(repeating: CGSize(width: 46, height: 44), count: 10)
        let content = 5 * 44 + 4 * 8
        let plan = RecentsFitPolicy.plan(
            itemSizes: sizes, containerWidth: fitWidth, spacing: fitSpacing,
            budget: CGFloat(content) + ChipViewport.borderBleed, rowHeight: fitRow
        )
        #expect(plan.offered == 10)
        #expect(plan.scrolling == false)
    }

    @Test("one row short of full offers the fitting eight without scroll")
    func multiColumnBoundary() {
        let sizes = Array(repeating: CGSize(width: 46, height: 44), count: 10)
        let content = 5 * 44 + 4 * 8
        let plan = RecentsFitPolicy.plan(
            itemSizes: sizes, containerWidth: fitWidth, spacing: fitSpacing,
            budget: CGFloat(content) + ChipViewport.borderBleed - 0.1, rowHeight: fitRow
        )
        #expect(plan.offered == 8)
        #expect(plan.scrolling == false)
    }
}

@Suite("FlowPacking.packing")
struct FlowPackingTests {
    @Test("packs greedily with uniform gaps within and between rows")
    func greedyPacking() {
        let rows = FlowPacking.pack(
            itemSizes: [CGSize(width: 40, height: 44), CGSize(width: 40, height: 44), CGSize(width: 40, height: 44)],
            maxWidth: 100, spacing: 8
        )
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 2)
        #expect(rows[1].items.count == 1)
        #expect(rows[0].items.map(\.index) == [0, 1])
        #expect(rows[1].items.map(\.index) == [2])
    }

    @Test("clamps an over-wide chip to the container width")
    func widthClamp() {
        let rows = FlowPacking.pack(
            itemSizes: [CGSize(width: 300, height: 44)],
            maxWidth: 100, spacing: 8
        )
        #expect(rows.count == 1)
        #expect(rows[0].items[0].size.width == 100)
    }

    @Test("a long newer chip forces its own row without skipping recency")
    func longNewerChip() {
        let sizes = [CGSize(width: 300, height: 44)] + Array(repeating: CGSize(width: 40, height: 44), count: 9)
        let fitting = FlowPacking.fittingPrefixCount(
            itemSizes: sizes, maxWidth: 100, spacing: 8, budget: 44
        )
        #expect(fitting == 1)
        let plan = RecentsFitPolicy.plan(
            itemSizes: sizes, containerWidth: 100, spacing: 8,
            budget: 44 + ChipViewport.borderBleed, rowHeight: 44
        )
        // One fits (< 5): offer the newest five — the long newer chip stays
        // first, nothing is skipped for a shorter older chip.
        #expect(plan.offered == 5)
        #expect(plan.scrolling == true)
    }

    @Test("row height is the largest item height on that row")
    func variableRowHeights() {
        let rows = FlowPacking.pack(
            itemSizes: [CGSize(width: 40, height: 44), CGSize(width: 40, height: 60)],
            maxWidth: 100, spacing: 8
        )
        #expect(rows.count == 1)
        #expect(rows[0].height == 60)
        #expect(FlowPacking.totalHeight(rows: rows, spacing: 8) == 60)
        // A taller chip growing its row shrinks the fitting prefix.
        let fittingTall = FlowPacking.fittingPrefixCount(
            itemSizes: [CGSize(width: 40, height: 44), CGSize(width: 40, height: 60)],
            maxWidth: 100, spacing: 8, budget: 59
        )
        #expect(fittingTall == 0)
        let fittingExact = FlowPacking.fittingPrefixCount(
            itemSizes: [CGSize(width: 40, height: 44), CGSize(width: 40, height: 60)],
            maxWidth: 100, spacing: 8, budget: 60
        )
        #expect(fittingExact == 2)
    }

    @Test("exact-fit boundaries hold to the point")
    func exactFitBoundaries() {
        let sizes = columnSizes(3)
        let exact = 3 * 44 + 2 * 8
        #expect(FlowPacking.fittingPrefixCount(
            itemSizes: sizes, maxWidth: fitWidth, spacing: 8, budget: CGFloat(exact)
        ) == 3)
        #expect(FlowPacking.fittingPrefixCount(
            itemSizes: sizes, maxWidth: fitWidth, spacing: 8, budget: CGFloat(exact) - 0.01
        ) == 2)
    }

    @Test("a narrower width repacks and shrinks the fitting prefix")
    func widthInvalidation() {
        let sizes = Array(repeating: CGSize(width: 46, height: 44), count: 6)
        let wide = FlowPacking.fittingPrefixCount(
            itemSizes: sizes, maxWidth: 100, spacing: 8, budget: 44 + 8 + 44
        )
        #expect(wide == 4)
        let narrow = FlowPacking.fittingPrefixCount(
            itemSizes: sizes, maxWidth: 50, spacing: 8, budget: 44 + 8 + 44
        )
        #expect(narrow == 2)
    }

    @Test("a taller active row height raises the floor and shrinks fits")
    func textSizeInvalidation() {
        #expect(RecentsFitPolicy.floorHeight(rowHeight: 44) == 46)
        #expect(RecentsFitPolicy.floorHeight(rowHeight: 60) == 62)
        let plan = RecentsFitPolicy.plan(
            itemSizes: columnSizes(10, height: 60), containerWidth: fitWidth, spacing: fitSpacing,
            budget: budgetForRows(5, height: 44), rowHeight: 60
        )
        // Five 44pt rows of budget fit only three 60pt rows (< 5 → fallback).
        #expect(plan.offered == 5)
        #expect(plan.scrolling == true)
    }

    @Test("nil, zero, negative, and non-finite geometry stay bounded")
    func invalidGeometry() {
        let sizes = columnSizes(10)
        let badBudgets: [CGFloat?] = [nil, 0, -50, .nan, .infinity, -.infinity]
        for budget in badBudgets {
            let plan = RecentsFitPolicy.plan(
                itemSizes: sizes, containerWidth: fitWidth, spacing: fitSpacing,
                budget: budget, rowHeight: fitRow
            )
            #expect(plan.offered == 5, "budget \(String(describing: budget))")
            #expect(plan.scrolling == true, "budget \(String(describing: budget))")
            #expect(plan.viewport == fitFloor, "budget \(String(describing: budget))")
        }
        let badWidths: [CGFloat] = [0, -100, .nan, .infinity, -.infinity]
        for width in badWidths {
            let plan = RecentsFitPolicy.plan(
                itemSizes: sizes, containerWidth: width, spacing: fitSpacing,
                budget: 1000, rowHeight: fitRow
            )
            #expect(plan.offered == 5, "width \(width)")
            #expect(plan.scrolling == true, "width \(width)")
            #expect(plan.viewport == fitFloor, "width \(width)")
        }
    }

    @Test("non-finite item sizes never trap and never claim fit")
    func invalidItemSizes() {
        let sizes = [CGSize(width: CGFloat.nan, height: 44), CGSize(width: 40, height: CGFloat.infinity)]
        let rows = FlowPacking.pack(itemSizes: sizes, maxWidth: 100, spacing: 8)
        #expect(!rows.isEmpty)
        let measured = rows.flatMap { $0.items }
        #expect(measured.allSatisfy { $0.size.width.isFinite && $0.size.height.isFinite })
        let fitting = FlowPacking.fittingPrefixCount(
            itemSizes: [CGSize(width: CGFloat.nan, height: CGFloat.nan)],
            maxWidth: CGFloat.nan, spacing: CGFloat.nan, budget: CGFloat.nan
        )
        #expect(fitting == 0)
    }

    @Test("offered sets are always newest-first prefixes — recency never skips")
    func prefixInvariantAcrossSweep() {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed % UInt64(max(1, bound)))
        }
        for _ in 0..<200 {
            let count = next(13)
            let sizes = (0..<count).map { _ in
                CGSize(width: CGFloat(next(220)), height: [30, 44, 60][next(3)])
            }
            let widths: [CGFloat] = [0, 50, 100, 320, .nan, .infinity]
            let budgets: [CGFloat] = [0, 10, 46, 100, 358, 10_000]
            let width = widths[next(widths.count)]
            let budget = budgets[next(budgets.count)]
            let plan = RecentsFitPolicy.plan(
                itemSizes: sizes,
                containerWidth: width,
                spacing: 8,
                budget: budget,
                rowHeight: 44
            )
            #expect(plan.offered >= 0 && plan.offered <= min(count, 10))
            if plan.scrolling {
                #expect(plan.viewport != nil)
                // Scrolling only ever mounts the newest-five fallback (or
                // all candidates when fewer exist) — never a longer prefix.
                #expect(plan.offered == min(RecentsFitPolicy.fallbackCount, min(count, 10)))
            } else {
                #expect(plan.viewport == nil)
                // The mounted newest-first prefix genuinely fits: repacking
                // exactly the offered prefix fills the plan's budget (floor
                // content when the one-row floor dominates, plus the policy
                // tolerance), so substituting an older chip for a newer one
                // — or skipping a newer chip — would fail here.
                let floorContent = RecentsFitPolicy.floorHeight(rowHeight: 44)
                    - ChipViewport.borderBleed
                let fitBudget = max(max(0, budget - ChipViewport.borderBleed), floorContent) + 0.5
                #expect(FlowPacking.fittingPrefixCount(
                    itemSizes: Array(sizes.prefix(plan.offered)),
                    maxWidth: width,
                    spacing: 8,
                    budget: fitBudget
                ) == plan.offered)
            }
        }
    }

    @Test("empty packing is zero-sized with no rows")
    func emptyPacking() {
        #expect(FlowPacking.pack(itemSizes: [], maxWidth: 100, spacing: 8).isEmpty)
        #expect(FlowPacking.totalSize(rows: [], spacing: 8) == .zero)
        #expect(FlowPacking.fittingPrefixCount(
            itemSizes: [], maxWidth: 100, spacing: 8, budget: 1000
        ) == 0)
    }
}
