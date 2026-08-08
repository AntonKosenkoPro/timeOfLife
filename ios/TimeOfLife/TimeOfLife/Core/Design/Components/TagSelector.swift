import SwiftUI

/// Multi-select category chips for an activity (Design/COMPONENTS.md,
/// `TagSelector`). Wrapping flow of tappable chips; toggling a chip
/// adds/removes the category id from `selected`. Categories are optional —
/// the selector never forces a selection.
///
/// Implemented with a `LazyVGrid` of flexible columns so it works on the
/// minimum supported iOS 15 runtime (the `Layout` protocol is iOS 16+).
struct TagSelector: View {
    let options: [Category]
    @Binding var selected: Set<String>
    let accessibilityId: String

    private let columns = [
        GridItem(.adaptive(minimum: 96), spacing: Theme.spacingSmall, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.spacingSmall) {
            ForEach(options) { category in
                chip(category)
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
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .padding(.horizontal, Theme.spacingSmall)
            .padding(.vertical, 4)
            .background(isSelected ? Theme.accentPrimary : Theme.backgroundSecondary)
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(Theme.hairline, lineWidth: 1)
                }
            }
        }
        .accessibilityLabel("Category, \(category.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
    }
}
