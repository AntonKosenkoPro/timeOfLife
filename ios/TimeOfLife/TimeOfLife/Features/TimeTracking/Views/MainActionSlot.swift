import SwiftUI
import UIKit

/// Fixed-height slot geometry for the Track main action
/// (refine-track-recents D10): the slot equals the tallest presentation any
/// of the state titles (Choose an activity / Start / Stop) can take at the
/// active Dynamic Type size, so swapping the control between states never
/// resizes or moves it. Title heights are measured with the trait-synced
/// metrics pattern used by `RecentActivitiesChips`, so measurement and
/// rendering scale together (also under a `.dynamicTypeSize` environment
/// override).
enum MainActionSlot {
    /// The body-bold font `PrimaryButton` renders its titles with, at the
    /// effective Dynamic Type size.
    static func titleFont(at dynamicTypeSize: DynamicTypeSize) -> UIFont {
        let trait = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        return UIFontMetrics(forTextStyle: .body)
            .scaledFont(
                for: UIFont.systemFont(ofSize: 17, weight: .bold),
                compatibleWith: trait
            )
    }

    /// The slot height for the given full slot width: the tallest title
    /// wrapped at the title's available width, computed as wrapped lines ×
    /// the font's full line height (which includes leading, matching
    /// SwiftUI Text's rendered line height where `boundingRect`
    /// under-measures). Never below `PrimaryButton.minHeight`. A width of
    /// zero falls back to the content width so the first layout pass
    /// (before the slot width is measured) still reserves a sane slot.
    static func height(
        titles: [String],
        width: CGFloat,
        at dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        let font = titleFont(at: dynamicTypeSize)
        let effectiveWidth = width > 0
            ? width
            : Theme.maxContentWidth - Theme.screenHorizontalPadding * 2
        // Title inset: horizontal padding + icon slot + icon-text spacing.
        // The icon slot is a conservative upper bound so the measured text
        // width is never wider than the rendered one (slot stays an upper
        // bound of the real button height).
        let inset = Theme.spacingMedium * 2 + 24 + Theme.spacingSmall
        let textWidth = max(0, effectiveWidth - inset)
        let lineHeight = ceil(font.lineHeight)
        let tallestLines = titles
            .map { title -> Int in
                guard !title.isEmpty else { return 1 }
                let titleWidth = title.size(withAttributes: [.font: font]).width
                guard textWidth > 0 else { return 1 }
                return max(1, Int(ceil(titleWidth / textWidth)))
            }
            .max() ?? 1
        return max(PrimaryButton.minHeight, CGFloat(tallestLines) * lineHeight)
    }
}
