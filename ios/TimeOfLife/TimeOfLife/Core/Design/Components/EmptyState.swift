import SwiftUI

/// Centered placeholder with icon, headline, and subheadline.
///
/// Used by `ManageActivitiesView` and `ManageCategoriesView` for U8.
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.spacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.textSecondary)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG

#Preview("EN Light") {
    EmptyState(
        icon: "plus.circle.fill",
        title: "No Activities Yet",
        subtitle: "Tap + to create your first activity."
    )
}

#Preview("RU Dark") {
    EmptyState(
        icon: "tag",
        title: "Нет категорий",
        subtitle: "Нажмите +, чтобы создать первую категорию."
    )
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#endif
