import SwiftUI

/// Simple section title used in editor screens to label input sections.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(Theme.textPrimary)
            .padding(.leading, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Section Header") {
    SectionHeader(title: "Icon")
}
#endif
