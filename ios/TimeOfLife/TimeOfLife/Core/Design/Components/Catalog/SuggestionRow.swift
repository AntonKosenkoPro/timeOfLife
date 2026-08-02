import SwiftUI

/// Recency-based suggestion row on the timer screen (F5/U3).
///
/// One tap prefills the activity name and links the activity to the entry.
struct SuggestionRow: View {
    let activity: Activity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                Circle()
                    .fill(Theme.activityColor(activity.color))
                    .frame(width: 8, height: 8)

                Image(systemName: activity.icon.rawValue)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)

                Text(activity.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
        }
        .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
        .accessibilityLabel(L10n.accessibilitySuggestion.text(activity.name))
        .accessibilityHint(L10n.accessibilitySuggestionHint.text)
    }
}

#if DEBUG

private let sampleActivity = Activity(
    id: UUID(),
    name: "Reading",
    color: .blue,
    icon: .book,
    notes: nil,
    lastUsedAt: Date().addingTimeInterval(-3600),
    categoryIds: [],
    createdAt: Date().addingTimeInterval(-86400),
    updatedAt: Date().addingTimeInterval(-3600)
)

#Preview("EN Light") {
    SuggestionRow(activity: sampleActivity) {}
        .padding()
}

#Preview("RU Dark") {
    SuggestionRow(activity: sampleActivity) {}
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
