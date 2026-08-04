import SwiftUI

/// Centered placeholder with icon, headline, and subheadline.
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
#Preview("Empty State") {
    EmptyState(
        icon: "plus.circle.fill",
        title: "No activities yet",
        subtitle: "Add one, or just type a name on the timer."
    )
}
#endif
