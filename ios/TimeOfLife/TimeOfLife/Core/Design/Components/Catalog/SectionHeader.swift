import SwiftUI

/// Simple section title used in editor screens to label
/// Color / Icon / Tags sections.
///
/// Pure presentational — no state, no action.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG

#Preview("EN Light") {
    SectionHeader(title: "Color")
        .padding()
}

#Preview("RU Dark") {
    SectionHeader(title: "Цвет")
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
