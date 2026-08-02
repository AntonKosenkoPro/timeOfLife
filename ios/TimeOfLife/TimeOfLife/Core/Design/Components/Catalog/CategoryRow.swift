import SwiftUI

/// Manage-categories list row for a category (F2).
///
/// Tap opens `CategoryEditor`. Swipe-to-delete is handled by the parent `List`.
struct CategoryRow: View {
    let category: Category
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                Circle()
                    .fill(Theme.activityColor(category.color))
                    .frame(width: 10, height: 10)

                Text(category.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
        }
        .accessibilityIdentifier("CategoryRow(\(category.id))")
        .accessibilityLabel(L10n.accessibilityCategory.text(category.name))
    }
}

#if DEBUG

private let sampleCategory = Category(
    id: UUID(),
    name: "Work",
    color: .blue,
    createdAt: Date(),
    updatedAt: Date()
)

#Preview("EN Light") {
    CategoryRow(category: sampleCategory) {}
        .padding()
}

#Preview("RU Dark") {
    CategoryRow(category: sampleCategory) {}
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
