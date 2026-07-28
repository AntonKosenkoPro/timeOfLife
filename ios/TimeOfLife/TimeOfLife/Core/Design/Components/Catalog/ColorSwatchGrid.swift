import SwiftUI

/// Selectable grid of the fixed 12-key activity/category palette (D15).
///
/// Each swatch is a 32 pt circle with a `Theme.minTapArea` hit area.
/// Tapping a swatch sets `selection` to that key; tapping the selected
/// swatch keeps it selected (no deselect).
struct ColorSwatchGrid: View {
    let options: [ActivityColor]
    @Binding var selection: ActivityColor?
    let accessibilityId: String
    /// When true the whole grid is disabled and swatches are dimmed to 50%
    /// alpha (AC #3 / `COMPONENTS.md` States).
    var disabled: Bool = false

    var body: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: Theme.minTapArea, maximum: Theme.minTapArea))],
                  spacing: Theme.spacingSmall) {
            ForEach(options, id: \.self) { key in
                swatch(for: key)
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private func swatch(for key: ActivityColor) -> some View {
        let isSelected = selection == key

        Button {
            selection = key
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.activityColor(key))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Theme.textPrimary : Theme.hairline,
                                    lineWidth: isSelected ? 2 : 1)
                    )

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: Theme.minTapArea, height: Theme.minTapArea)
            .opacity(disabled ? 0.5 : 1)
        }
        .accessibilityIdentifier("\(accessibilityId)Swatch(\(key))")
        .accessibilityLabel("Color, \(key)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

#if DEBUG

private struct ColorSwatchGridPreview: View {
    @State private var selection: ActivityColor?

    var body: some View {
        ColorSwatchGrid(
            options: ActivityColor.allCases,
            selection: $selection,
            accessibilityId: "Preview"
        )
        .padding()
    }
}

private struct ColorSwatchGridSelectedPreview: View {
    @State private var selection: ActivityColor? = .blue

    var body: some View {
        ColorSwatchGrid(
            options: ActivityColor.allCases,
            selection: $selection,
            accessibilityId: "PreviewSelected"
        )
        .padding()
    }
}

#Preview("EN Light") {
    ColorSwatchGridPreview()
}

#Preview("RU Dark") {
    ColorSwatchGridSelectedPreview()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
