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
/// circles, and a 44 pt minimum tap target. Chips wrap via the shared
/// `FlowLayout` with equal `Theme.spacingSmall` gaps.
struct TagSelector: View {
    let options: [Category]
    /// The selected ids as a set (for chip rendering state).
    let selected: Set<String>
    /// Called with the toggled category id; the parent owns the ordered
    /// selection.
    let onToggle: (String) -> Void
    let accessibilityId: String

    var body: some View {
        FlowLayout(spacing: Theme.spacingSmall) {
            ForEach(options) { category in
                chip(category)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Chip

    @ViewBuilder
    private func chip(_ category: Category) -> some View {
        let isSelected = selected.contains(category.id)
        Button {
            onToggle(category.id)
        } label: {
            chipLabel(category: category, isSelected: isSelected)
        }
        .accessibilityLabel("\(L10n.manageCategoriesRowA11y.text), \(category.name)")
        .accessibilityValue(isSelected ? L10n.undoSelected.text : L10n.undoNotSelected.text)
        .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
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
