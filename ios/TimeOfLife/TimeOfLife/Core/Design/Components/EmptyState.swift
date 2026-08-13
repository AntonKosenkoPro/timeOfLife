import SwiftUI

/// Centered placeholder with icon, headline, and subheadline
/// (Design/COMPONENTS.md).
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let actionAccessibilityId: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        actionAccessibilityId: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.actionAccessibilityId = actionAccessibilityId
        self.action = action
    }

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
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textOnAccent)
                    .padding(.horizontal, Theme.spacingMedium)
                    .frame(minHeight: Theme.minTapArea)
                    .background(Theme.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .accessibilityIdentifier(actionAccessibilityId ?? "")
            }
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
