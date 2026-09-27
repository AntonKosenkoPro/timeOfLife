import SwiftUI

/// Wrapping flow layout for content-sized chips.
///
/// Greedy packing: each row holds as many subviews as fit, with uniform
/// `spacing` gaps both within rows and between rows. A subview wider than
/// the container is clamped to the container width — its content (e.g. a
/// truncating `Text`) lays out in the clamped proposal instead of
/// overflowing.
struct FlowLayout: Layout {
    /// Gap between subviews within a row and between rows.
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
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

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = computeRows(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        var point = bounds.origin
        for row in rows {
            for index in row.indices {
                let width = min(subviews[index].sizeThatFits(.unspecified).width, bounds.width)
                subviews[index].place(
                    at: point,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: nil)
                )
                point.x += width + spacing
            }
            point.x = bounds.minX
            point.y += row.height + spacing
        }
    }

    // MARK: - Packing

    private struct Row {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    /// Greedy row packing over ideal (unspecified-proposal) subview sizes.
    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(indices: [], width: 0, height: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            let projected = current.width + (current.indices.isEmpty ? 0 : spacing) + width
            if current.indices.isEmpty || projected <= maxWidth {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            } else {
                rows.append(current)
                current = Row(indices: [index], width: width, height: size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
