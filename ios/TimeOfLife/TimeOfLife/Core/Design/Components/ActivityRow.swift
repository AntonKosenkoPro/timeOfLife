import SwiftUI

/// Manage-list row for an activity (F8). Tap opens `ActivityEditor`;
/// swipe-to-delete is handled by the parent `List`.
struct ActivityRow: View {
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
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    if !categories.isEmpty {
                        Text(categories.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if let lastUsed = activity.lastUsedAt {
                        Text(lastUsed, style: .relative)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ActivityRow(\(activity.id))")
        .accessibilityLabel("Activity, \(activity.name)")
    }
}
