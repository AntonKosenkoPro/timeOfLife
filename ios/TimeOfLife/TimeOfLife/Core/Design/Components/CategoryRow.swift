import SwiftUI

/// Manage-categories list row for a category (F2). Tap opens `CategoryEditor`.
struct CategoryRow: View {
    let category: Category
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                Text(category.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("CategoryRow(\(category.id))")
        .accessibilityLabel("Category, \(category.name)")
    }
}
