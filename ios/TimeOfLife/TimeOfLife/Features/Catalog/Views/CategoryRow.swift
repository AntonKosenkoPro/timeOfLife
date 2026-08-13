import SwiftUI

/// Manage-categories list row for a category (F2, Design/COMPONENTS.md
/// `CategoryRow`). Tap opens the Category Editor. The icon renders the
/// category's catalog symbol (or the `tag` fallback when the symbol cannot
/// render on this OS); the name is included in the accessibility label so
/// VoiceOver never relies on the symbol alone (category-management spec).
struct CategoryRow: View {
    let category: Category
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(category.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(L10n.manageCategoriesRowA11y.text), \(category.name)")
        .accessibilityHint(L10n.manageCategoriesEditHint.text)
        .accessibilityIdentifier("CategoryRow(\(category.id))")
    }
}

#if DEBUG
#Preview("Category Row") {
    CategoryRow(
        category: TimeOfLife.Category(
            id: "preview", name: "Sport", icon: "figure.run",
            createdAt: Date(), updatedAt: Date()
        )
    ) {}
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}
#endif
