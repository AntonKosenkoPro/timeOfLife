import SwiftUI

/// Centered placeholder with icon, headline, and subheadline.
///
/// Used for empty lists, empty history, and placeholder screens.
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
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.spacingLarge)
    }
}

#if DEBUG
#Preview("Empty State") {
    EmptyState(
        icon: "clock.arrow.circlepath",
        title: "No entries yet",
        subtitle: "Start a timer to track where your time goes."
    )
}
#endif
