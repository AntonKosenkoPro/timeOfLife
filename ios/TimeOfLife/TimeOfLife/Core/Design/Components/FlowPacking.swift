import Foundation

/// Pure greedy wrapping arithmetic shared by `FlowLayout` and the Recents
/// fit policy (fit-track-recents): one packing source for placement and
/// fitting, so the fitting prefix can never disagree with what the layout
/// would render. Each row holds as many items as fit, with uniform `spacing`
/// gaps both within rows and between rows. An item wider than the container
/// is clamped to the container width.
///
/// All entry points are `nonisolated` and total (never trap): non-finite or
/// non-positive geometry degrades to a bounded single-column packing instead
/// of producing NaN heights.
enum FlowPacking {
    /// One packed item: its position in the input and its measured size.
    struct Item: Equatable {
        var index: Int
        var size: CGSize
    }

    /// One packed row: the items in order, the row's content width,
    /// and the row height (the largest item height on the row).
    struct Row: Equatable {
        var items: [Item]
        var width: CGFloat
        var height: CGFloat
    }

    /// Greedy row assignment over pre-measured item sizes, mirroring
    /// `FlowLayout.computeRows` exactly on the normal path (finite,
    /// non-negative widths and spacing).
    nonisolated static func pack(
        itemSizes: [CGSize],
        maxWidth: CGFloat,
        spacing: CGFloat
    ) -> [Row] {
        let gap = spacing.isFinite ? spacing : 0
        let container: CGFloat
        if maxWidth.isFinite {
            container = max(0, maxWidth)
        } else if maxWidth == .infinity {
            container = .infinity
        } else {
            container = 0
        }
        var rows: [Row] = []
        var items: [Item] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, rawSize) in itemSizes.enumerated() {
            let itemWidth = rawSize.width.isFinite ? max(0, rawSize.width) : 0
            let itemHeight = rawSize.height.isFinite ? max(0, rawSize.height) : 0
            let width = min(itemWidth, container)
            let projected = rowWidth + (items.isEmpty ? 0 : gap) + width
            if items.isEmpty || projected <= container {
                items.append(Item(index: index, size: CGSize(width: width, height: itemHeight)))
                rowWidth = projected
                rowHeight = max(rowHeight, itemHeight)
            } else {
                rows.append(Row(items: items, width: rowWidth, height: rowHeight))
                items = [Item(index: index, size: CGSize(width: width, height: itemHeight))]
                rowWidth = width
                rowHeight = itemHeight
            }
        }
        if !items.isEmpty {
            rows.append(Row(items: items, width: rowWidth, height: rowHeight))
        }
        return rows
    }

    /// Content size of packed rows: widest row, stacked row heights plus
    /// inter-row gaps. Matches `FlowLayout.totalSize`.
    nonisolated static func totalSize(rows: [Row], spacing: CGFloat) -> CGSize {
        let gap = spacing.isFinite ? spacing : 0
        guard !rows.isEmpty else { return .zero }
        var width: CGFloat = 0
        var height: CGFloat = 0
        for row in rows {
            width = max(width, row.width)
            height += row.height
        }
        height += gap * CGFloat(rows.count - 1)
        return CGSize(width: width, height: height)
    }

    /// Content height of packed rows (the width-independent part of
    /// `totalSize`, for fit comparisons).
    nonisolated static func totalHeight(rows: [Row], spacing: CGFloat) -> CGFloat {
        totalSize(rows: rows, spacing: spacing).height
    }

    /// Largest newest-first prefix whose packed content height fits completely
    /// inside `budget`. Counts items, never skips a longer newer item to pack
    /// an older shorter one. A non-finite or negative budget fits nothing;
    /// an infinite budget fits everything.
    nonisolated static func fittingPrefixCount(
        itemSizes: [CGSize],
        maxWidth: CGFloat,
        spacing: CGFloat,
        budget: CGFloat
    ) -> Int {
        guard !itemSizes.isEmpty else { return 0 }
        if budget == .infinity { return itemSizes.count }
        guard budget.isFinite, budget >= 0 else { return 0 }
        let gap = spacing.isFinite ? spacing : 0
        let rows = pack(itemSizes: itemSizes, maxWidth: maxWidth, spacing: spacing)
        var consumed: CGFloat = 0
        var count = 0
        for (index, row) in rows.enumerated() {
            consumed += row.height + (index == 0 ? 0 : gap)
            if consumed <= budget + 1e-6 {
                count += row.items.count
            } else {
                break
            }
        }
        return count
    }
}
