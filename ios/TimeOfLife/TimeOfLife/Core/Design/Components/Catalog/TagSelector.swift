import SwiftUI

/// Multi-select category chips for an activity (F3).
///
/// Wrapping `FlowLayout` of tappable chips; toggling a chip adds/removes
/// the category id from `selected`. When `options` is empty, renders a
/// hint label instead.
struct TagSelector: View {
    let options: [Category]
    @Binding var selected: Set<UUID>
    let accessibilityId: String

    var body: some View {
        if options.isEmpty {
            Text(L10n.tagsEmptyHint.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        } else {
            FlowLayout(items: options,
                       horizontalSpacing: Theme.spacingSmall,
                       verticalSpacing: Theme.spacingSmall) { category in
                chip(for: category)
            }
        }
    }

    @ViewBuilder
    private func chip(for category: Category) -> some View {
        let isSelected = selected.contains(category.id)

        Button {
            if isSelected {
                selected.remove(category.id)
            } else {
                selected.insert(category.id)
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.white)
                }

                Circle()
                    .fill(Theme.activityColor(category.color))
                    .frame(width: 6, height: 6)

                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : Theme.textPrimary)
            }
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.accentPrimary : Theme.backgroundSecondary)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Theme.hairline, lineWidth: 1)
            )
            .frame(minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
        .accessibilityLabel("Category, \(category.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#if DEBUG

private struct TagSelectorPreview: View {
    @State private var selected: Set<UUID> = [Category.sampleBlue.id]

    private let sampleCategories: [Category] = [
        Category.sampleBlue,
        Category.sampleGreen,
        Category.sampleOrange,
    ]

    var body: some View {
        TagSelector(
            options: sampleCategories,
            selected: $selected,
            accessibilityId: "Preview"
        )
        .padding()
    }
}

private struct TagSelectorEmptyPreview: View {
    @State private var selected: Set<UUID> = []

    var body: some View {
        TagSelector(
            options: [],
            selected: $selected,
            accessibilityId: "PreviewEmpty"
        )
        .padding()
    }
}

#Preview("EN Light") {
    TagSelectorPreview()
}

#Preview("RU Dark") {
    TagSelectorPreview()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Empty") {
    TagSelectorEmptyPreview()
}

#endif
