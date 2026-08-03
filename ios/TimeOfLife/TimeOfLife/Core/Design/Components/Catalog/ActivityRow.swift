import SwiftUI

/// Manage-list row for an activity (F8).
///
/// Tap opens `ActivityEditor`; swipe-to-delete is handled by the parent `List`.
struct ActivityRow: View {
    let activity: Activity
    let categories: [Category]
    let action: () -> Void

    init(activity: Activity, categories: [Category] = [], action: @escaping () -> Void) {
        self.activity = activity
        self.categories = categories
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingMedium) {
                leadingIcon
                middleContent
                Spacer()
                trailingChevron
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
        }
        .accessibilityIdentifier("ActivityRow(\(activity.id))")
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    @ViewBuilder private var leadingIcon: some View {
        if let category = categories.first {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .fill(Theme.backgroundSecondary)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: category.icon.rawValue)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                }
        }
    }

    private var middleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(activity.name)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if !categories.isEmpty {
                Text(categories.map(\.name).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }

            if let lastUsedAt = activity.lastUsedAt {
                Text(lastUsedAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var trailingChevron: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - Accessibility

    /// Reused across reads of `accessibilityLabel` to avoid per-access
    /// allocation of a `RelativeDateTimeFormatter`.
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var accessibilityLabel: String {
        var parts = [activity.name]
        if !categories.isEmpty {
            parts.append(L10n.accessibilityTagsCount.text(categories.count))
        }
        if let lastUsed = activity.lastUsedAt {
            let relative = Self.relativeDateFormatter
                .localizedString(for: lastUsed, relativeTo: Date())
            parts.append(L10n.activityLastUsed.text(relative))
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG

private let sampleActivityWithTags = Activity(
    id: UUID(),
    name: "Reading",
    notes: nil,
    lastUsedAt: Date().addingTimeInterval(-3600),
    categoryIds: [Category.sampleBlue.id, Category.sampleGreen.id],
    createdAt: Date().addingTimeInterval(-86400),
    updatedAt: Date().addingTimeInterval(-3600)
)

private let sampleActivityNoTags = Activity(
    id: UUID(),
    name: "Gym",
    notes: nil,
    lastUsedAt: Date().addingTimeInterval(-7200),
    categoryIds: [],
    createdAt: Date().addingTimeInterval(-172800),
    updatedAt: Date().addingTimeInterval(-7200)
)

private let sampleActivityNoLastUsed = Activity(
    id: UUID(),
    name: "New Activity",
    notes: nil,
    lastUsedAt: nil,
    categoryIds: [],
    createdAt: Date(),
    updatedAt: Date()
)

#Preview("EN Light — With Tags") {
    ActivityRow(activity: sampleActivityWithTags, categories: [Category.sampleBlue, Category.sampleGreen]) {}
        .padding()
}

#Preview("EN Light — No Tags") {
    ActivityRow(activity: sampleActivityNoTags, categories: []) {}
        .padding()
}

#Preview("RU Dark — No Last Used") {
    ActivityRow(activity: sampleActivityNoLastUsed, categories: []) {}
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
