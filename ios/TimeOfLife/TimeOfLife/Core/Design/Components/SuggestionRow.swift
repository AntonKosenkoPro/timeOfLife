import SwiftUI

/// Recency-based suggestion row on the timer screen (F5/U3). One tap
/// prefills the activity name and links the activity to the entry.
struct SuggestionRow: View {
    let activity: Activity
    let categories: [Category]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                if let firstCategory = categories.first {
                    Image(systemName: firstCategory.icon)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    if !categories.isEmpty {
                        Text(categories.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let lastUsed = activity.lastUsedAt {
                    Text(lastUsed, style: .relative)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
        .accessibilityLabel("Suggestion, \(activity.name)")
        .accessibilityHint("Starts a timer for this activity")
    }
}
