import SwiftUI

/// Multi-select category chips for an activity (Design/COMPONENTS.md,
/// `TagSelector`). Wrapping flow of content-sized tappable chips with equal
/// `Theme.spacingSmall` gaps; toggling a chip adds/removes the category id
/// from the ordered selection (category-management D5/D6: zero-or-more,
/// selection order preserved). Categories are optional — the selector never
/// forces a selection.
///
/// Chips follow category-management D9: each chip is as wide as its content
/// (uniform `Theme.spacingChip` padding on all sides), unselected chips show
/// only the category icon, selected chips swap the icon for a `checkmark`
/// (both 30% larger than `.caption`, scaling with Dynamic Type), no outline
/// circles, and a 44 pt minimum tap target. Rows are packed from measured
/// chip widths because the `Layout` protocol is iOS 16+ and the app supports
/// iOS 15.
struct TagSelector: View {
    let options: [Category]
    /// The selected ids as a set (for chip rendering state).
    let selected: Set<String>
    /// Called with the toggled category id; the parent owns the ordered
    /// selection.
    let onToggle: (String) -> Void
    let accessibilityId: String

    @State private var containerWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: Theme.spacingSmall) {
                    ForEach(rows[rowIndex]) { category in
                        chip(category)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: TagSelectorWidthKey.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(TagSelectorWidthKey.self) { containerWidth = $0 }
    }

    // MARK: - Sizing

    /// Icon and checkmark glyph size: 30% larger than the caption1 standard
    /// size (12 pt), scaled with Dynamic Type via `UIFontMetrics`.
    private var symbolFontSize: CGFloat {
        UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12 * 1.3)
    }

    /// Fixed symbol slot: wide SF Symbols (e.g. `figure.run`) stay fully
    /// visible while the slot keeps the measured chip width exact. The same
    /// slot serves the icon and the checkmark, so toggling never re-packs
    /// rows.
    private var symbolSlotSize: CGFloat {
        ceil(symbolFontSize * 1.5)
    }

    /// Natural chip width: symbol slot + inner gap + name + uniform padding.
    private func chipWidth(for category: Category) -> CGFloat {
        let nameFont = UIFont.preferredFont(forTextStyle: .caption1)
        let name = category.name.size(withAttributes: [.font: nameFont]).width
        return symbolSlotSize + Theme.spacingExtraSmall + name + Theme.spacingChip * 2
    }

    /// Greedy packing: fill each row with as many content-sized chips as fit,
    /// keeping equal `Theme.spacingSmall` gaps. Until the container width is
    /// measured, every chip sits on its own row (single pass, no flicker).
    private var rows: [[Category]] {
        guard containerWidth > 0 else { return options.map { [$0] } }
        var result: [[Category]] = []
        var current: [Category] = []
        var currentWidth: CGFloat = 0
        for category in options {
            let width = min(chipWidth(for: category), containerWidth)
            let projected = currentWidth + (current.isEmpty ? 0 : Theme.spacingSmall) + width
            if current.isEmpty || projected <= containerWidth {
                current.append(category)
                currentWidth = projected
            } else {
                result.append(current)
                current = [category]
                currentWidth = width
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(_ category: Category) -> some View {
        let isSelected = selected.contains(category.id)
        let label = chipLabel(category: category, isSelected: isSelected)
        // A chip wider than the container gets a fixed container-width frame
        // so its name truncates instead of overflowing. All other chips stay
        // content-sized (no flexible frame that would stretch them).
        if containerWidth > 0, chipWidth(for: category) > containerWidth {
            Button {
                onToggle(category.id)
            } label: {
                label.frame(width: containerWidth)
            }
            .accessibilityLabel("\(L10n.manageCategoriesRowA11y.text), \(category.name)")
            .accessibilityValue(isSelected ? L10n.undoSelected.text : L10n.undoNotSelected.text)
            .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
        } else {
            Button {
                onToggle(category.id)
            } label: {
                label
            }
            .accessibilityLabel("\(L10n.manageCategoriesRowA11y.text), \(category.name)")
            .accessibilityValue(isSelected ? L10n.undoSelected.text : L10n.undoNotSelected.text)
            .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
        }
    }

    private func chipLabel(category: Category, isSelected: Bool) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            Image(systemName: isSelected ? "checkmark" : CatalogIcon(validated: category.icon).displaySymbol)
                .font(.system(size: symbolFontSize, weight: isSelected ? .semibold : .regular))
                .frame(width: symbolSlotSize, height: symbolFontSize)
                .accessibilityHidden(true)
            Text(category.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textPrimary)
        .padding(Theme.spacingChip)
        .frame(minHeight: Theme.minTapArea)
        .background(isSelected ? Theme.accentPrimary : Theme.backgroundSecondary)
        .clipShape(Capsule())
        .overlay {
            if !isSelected {
                Capsule().stroke(Theme.hairline, lineWidth: 1)
            }
        }
    }
}

private struct TagSelectorWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
