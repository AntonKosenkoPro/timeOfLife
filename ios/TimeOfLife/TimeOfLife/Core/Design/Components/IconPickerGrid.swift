import SwiftUI

/// Selectable grid of allowed SF Symbols for categories (F2/U1).
struct IconPickerGrid: View {
    let options: [String]
    @Binding var selection: String
    let accessibilityId: String

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: Theme.spacingSmall),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.spacingSmall) {
            ForEach(options, id: \.self) { symbol in
                cell(symbol)
            }
        }
    }

    private func cell(_ symbol: String) -> some View {
        let isSelected = selection == symbol
        return Button {
            selection = symbol
        } label: {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .stroke(isSelected ? Theme.accentPrimary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityId)Cell(\(symbol))")
        .accessibilityLabel("Icon, \(symbol)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
