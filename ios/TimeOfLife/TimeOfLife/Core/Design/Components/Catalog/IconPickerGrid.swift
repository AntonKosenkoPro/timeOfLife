import SwiftUI

/// Selectable grid of allowed SF Symbols for `activity.icon` (F1/U1).
///
/// Mirrors `ColorSwatchGrid` geometry. Each cell is 44 × 44 pt with
/// `Theme.backgroundSecondary` fill and a 2 pt accent border when selected.
struct IconPickerGrid: View {
    let options: [String]
    @Binding var selection: String
    let accessibilityId: String

    var body: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: Theme.minTapArea, maximum: Theme.minTapArea))],
                  spacing: Theme.spacingSmall) {
            ForEach(options, id: \.self) { symbol in
                cell(for: symbol)
            }
        }
    }

    @ViewBuilder
    private func cell(for symbol: String) -> some View {
        let isSelected = selection == symbol

        Button {
            selection = symbol
        } label: {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.minTapArea, height: Theme.minTapArea)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .fill(Theme.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .stroke(isSelected ? Theme.accentPrimary : Color.clear, lineWidth: 2)
                )
        }
        .accessibilityIdentifier("\(accessibilityId)Cell(\(symbol))")
        .accessibilityLabel(L10n.accessibilityIcon.text(symbol))
        .accessibilityValue(isSelected ? L10n.accessibilitySelected.text : "")
    }
}

#if DEBUG

private struct IconPickerGridPreview: View {
    @State private var selection = "clock"

    var body: some View {
        IconPickerGrid(
            options: ["clock", "book", "laptopcomputer", "heart", "star", "moon"],
            selection: $selection,
            accessibilityId: "Preview"
        )
        .padding()
    }
}

#Preview("EN Light") {
    IconPickerGridPreview()
}

#Preview("RU Dark") {
    IconPickerGridPreview()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
