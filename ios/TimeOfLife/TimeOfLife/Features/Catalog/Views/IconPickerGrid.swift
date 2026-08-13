import SwiftUI

/// Selectable grid of the supported catalog SF Symbols for categories
/// (F2/U1, Design/COMPONENTS.md `IconPickerGrid`). Only catalog symbols that
/// can render on the running OS are shown (category-management D1); a valid
/// synchronized symbol that cannot render is displayed as `tag` elsewhere
/// without changing the stored value.
struct IconPickerGrid: View {
    let options: [String]
    @Binding var selection: String
    let accessibilityId: String

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: Theme.spacingSmall, alignment: .center)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: Theme.spacingSmall) {
            ForEach(options, id: \.self) { symbol in
                cell(symbol)
            }
        }
    }

    private func cell(_ symbol: String) -> some View {
        let isSelected = selection == symbol
        let icon = CatalogIcon(validated: symbol)
        let isFallback = icon.displaySymbol != symbol
        return Button {
            selection = symbol
        } label: {
            Image(systemName: icon.displaySymbol)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .stroke(isSelected ? Theme.accentPrimary : Theme.transparent, lineWidth: 2)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            "\(L10n.categoryEditorIconLabel.text), \(L10n.catalogIconName(icon))"
        )
        .accessibilityValue(
            isFallback
                ? L10n.categoryEditorIconUnavailable.text
                : (isSelected ? L10n.undoSelected.text : L10n.undoNotSelected.text)
        )
        .accessibilityIdentifier("\(accessibilityId)Cell(\(symbol))")
    }
}

#if DEBUG
private struct IconPickerGridPreview: View {
    @State private var selection = "tag"

    var body: some View {
        IconPickerGrid(
            options: CatalogIcon.renderableSymbols,
            selection: $selection,
            accessibilityId: "PreviewIconPicker"
        )
        .padding()
        .background(Theme.backgroundPrimary)
    }
}

#Preview("Icon Picker Grid") {
    IconPickerGridPreview()
}
#endif
