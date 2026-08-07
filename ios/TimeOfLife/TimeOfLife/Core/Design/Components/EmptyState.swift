import SwiftUI

/// Centered placeholder with icon, headline, and subheadline
/// (Design/COMPONENTS.md).
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Empty State") {
    EmptyState(
        icon: "clock.arrow.circlepath",
        title: L10n.historyEmptyTitle.text,
        subtitle: L10n.historyEmptySubtitle.text
    )
    .background(Theme.backgroundPrimary)
}
#endif
