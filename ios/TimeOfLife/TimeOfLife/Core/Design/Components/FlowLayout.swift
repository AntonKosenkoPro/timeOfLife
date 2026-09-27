import SwiftUI

/// Wrapping flow layout for content-sized chips.
///
/// Greedy packing: each row holds as many subviews as fit, with uniform
/// `spacing` gaps both within rows and between rows. A subview wider than
/// the container is clamped to the container width — its content (e.g. a
/// truncating `Text`) lays out in the clamped proposal instead of
/// overflowing.
///
/// Row packing is memoized in the layout cache: `sizeThatFits` computes the
/// rows and `placeSubviews` reuses them when the width is unchanged, so each
/// subview is measured once per layout pass instead of on every phase.
struct FlowLayout: Layout {
    /// Gap between subviews within a row and between rows.
    var spacing: CGFloat

    /// One packed row: per-subview sizes measured under the clamped width,
    /// so packing and placement agree even for width-dependent heights.
    struct RowItem {
        var index: Int
        var size: CGSize
    }

    struct Row {
        var items: [RowItem]
        var width: CGFloat
        var height: CGFloat
    }

    struct Cache {
        var width: CGFloat?
        var rows: [Row] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        cache.width = proposal.width
        cache.rows = rows
        return totalSize(rows: rows)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let rows: [Row]
        if cache.width == bounds.width, !cache.rows.isEmpty {
            rows = cache.rows
        } else {
            rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        }
        var point = bounds.origin
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: point,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                point.x += item.size.width + spacing
            }
            point.x = bounds.minX
            point.y += row.height + spacing
        }
    }

    // MARK: - Packing

    /// Greedy row packing over ideal subview widths, with each row item's
    /// height measured under its clamped width.
    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var items: [RowItem] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let idealWidth = subviews[index].sizeThatFits(.unspecified).width
            let width = min(idealWidth, maxWidth)
            let height = subviews[index]
                .sizeThatFits(ProposedViewSize(width: width, height: nil))
                .height
            let projected = rowWidth + (items.isEmpty ? 0 : spacing) + width
            if items.isEmpty || projected <= maxWidth {
                items.append(RowItem(index: index, size: CGSize(width: width, height: height)))
                rowWidth = projected
                rowHeight = max(rowHeight, height)
            } else {
                rows.append(Row(items: items, width: rowWidth, height: rowHeight))
                items = [RowItem(index: index, size: CGSize(width: width, height: height))]
                rowWidth = width
                rowHeight = height
            }
        }
        if !items.isEmpty { rows.append(Row(items: items, width: rowWidth, height: rowHeight)) }
        return rows
    }

    private func totalSize(rows: [Row]) -> CGSize {
        guard !rows.isEmpty else { return .zero }
        var width: CGFloat = 0
        var height: CGFloat = 0
        for row in rows {
            width = max(width, row.width)
            height += row.height
        }
        height += spacing * CGFloat(rows.count - 1)
        return CGSize(width: width, height: height)
    }
}
