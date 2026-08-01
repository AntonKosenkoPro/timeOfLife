import SwiftUI

/// A left-aligned wrapping flow layout.
///
/// On iOS 16+ uses the native `Layout` protocol (`FlowLayoutModern`); on iOS 15
/// falls back to a `GeometryReader` + `PreferenceKey` measurement pass that
/// wraps children into `HStack` rows (`FlowLayoutLegacy`). The deployment
/// target is iOS 15.0, so the fallback is required for `TagSelector` to render
/// safely on iOS 15. Spacing is controlled by `horizontalSpacing` and
/// `verticalSpacing`.
///
/// - Note: The fallback measures each item's natural width once, then assigns
///   items to rows greedily against the available width. Item widths are
///   measured with a `PreferenceKey`; layout settles after one measurement
///   pass.
struct FlowLayout<Item, RowContent: View>: View {
    let items: [Item]
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: (Item) -> RowContent

    init(items: [Item],
         horizontalSpacing: CGFloat = Theme.spacingSmall,
         verticalSpacing: CGFloat = Theme.spacingSmall,
         @ViewBuilder content: @escaping (Item) -> RowContent) {
        self.items = items
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 16, *) {
            FlowLayoutModern(horizontalSpacing: horizontalSpacing,
                             verticalSpacing: verticalSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    content(items[index])
                }
            }
        } else {
            FlowLayoutLegacy(items: items,
                             horizontalSpacing: horizontalSpacing,
                             verticalSpacing: verticalSpacing,
                             content: content)
        }
    }
}

// MARK: - iOS 16+ (Layout protocol)

@available(iOS 16, *)
private struct FlowLayoutModern: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let computed = rows(subviews: subviews, maxWidth: proposal.width)
        let height = computed.reduce(into: CGFloat(0)) { total, row in
            total += row.height
        } + CGFloat(max(computed.count - 1, 0)) * verticalSpacing
        let naturalWidth = computed.map(\.width).max() ?? 0
        let width = proposal.width ?? naturalWidth
        return CGSize(width: max(width, 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let computed = rows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in computed {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        let indices: [Int]
        let height: CGFloat
        let width: CGFloat
    }

    /// Greedy left-aligned wrap. The first item on a line is never wrapped
    /// (so an item wider than the available width still places at the line
    /// start instead of being offset by one `verticalSpacing`). Both
    /// `sizeThatFits` and `placeSubviews` use this so measurement and placement
    /// agree.
    private func rows(subviews: Subviews, maxWidth: CGFloat?) -> [Row] {
        let limit = maxWidth ?? .infinity
        var rows: [Row] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let added = current.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width
            if !current.isEmpty && added > limit {
                rows.append(Row(indices: current, height: currentHeight, width: currentWidth))
                current = [index]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                current.append(index)
                currentWidth = added
                currentHeight = max(currentHeight, size.height)
            }
        }
        if !current.isEmpty {
            rows.append(Row(indices: current, height: currentHeight, width: currentWidth))
        }
        return rows
    }
}

// MARK: - iOS 15 (GeometryReader + PreferenceKey measurement)

private struct FlowLayoutLegacy<Item, RowContent: View>: View {
    let items: [Item]
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: (Item) -> RowContent

    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let computed = rows(in: geo.size.width)
            VStack(alignment: .leading, spacing: verticalSpacing) {
                ForEach(computed.indices, id: \.self) { r in
                    HStack(spacing: horizontalSpacing) {
                        ForEach(computed[r].indices, id: \.self) { c in
                            content(items[computed[r][c]])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(measurementLayer)
            .onPreferenceChange(FlowLayoutWidthKey.self) { widths = $0 }
        }
    }

    /// Hidden `ZStack` of all items at their natural size; each reports its
    /// width via `FlowLayoutWidthKey`. Placed in an overlay so it does not
    /// contribute to the visible layout.
    private var measurementLayer: some View {
        ZStack {
            ForEach(items.indices, id: \.self) { index in
                content(items[index])
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: FlowLayoutWidthKey.self,
                                                   value: [index: proxy.size.width])
                        }
                    )
            }
        }
        .opacity(0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Greedy left-aligned wrap computed from the measured item widths and the
    /// available width. Until widths are measured, falls back to a single row
    /// so items render and report their widths.
    private func rows(in width: CGFloat) -> [[Int]] {
        guard !widths.isEmpty else {
            return items.isEmpty ? [] : [Array(items.indices)]
        }
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for index in items.indices {
            let itemWidth = widths[index] ?? 0
            let added = current.isEmpty ? itemWidth : currentWidth + horizontalSpacing + itemWidth
            if !current.isEmpty && added > width {
                rows.append(current)
                current = [index]
                currentWidth = itemWidth
            } else {
                current.append(index)
                currentWidth = added
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

private struct FlowLayoutWidthKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
