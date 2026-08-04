import SwiftUI

/// Multi-select category chips for an activity (F3). Wrapping `FlowLayout`
/// of tappable chips; toggling a chip adds/removes the category id from
/// `selected`.
struct TagSelector: View {
    let options: [Category]
    @Binding var selected: Set<String>
    let accessibilityId: String

    var body: some View {
        if options.isEmpty {
            Text(L10n.activityEditorNoTags.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        } else {
            FlowLayout(spacing: Theme.spacingSmall) {
                ForEach(options) { category in
                    chip(category)
                }
            }
        }
    }

    private func chip(_ category: Category) -> some View {
        let isSelected = selected.contains(category.id)
        return Button {
            if isSelected {
                selected.remove(category.id)
            } else {
                selected.insert(category.id)
            }
        } label: {
            HStack(spacing: Theme.spacingExtraSmall) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.name)
                    .font(.caption)
            }
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .background(isSelected ? Theme.accentPrimary : Theme.backgroundSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Theme.hairline, lineWidth: 1))
            .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
            .accessibilityLabel("Category, \(category.name)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
        .buttonStyle(.plain)
    }
}
