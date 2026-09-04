import SwiftUI

/// Section title used in editor screens to label input sections, and in
/// History as the day-group header (Design/COMPONENTS.md). Purely
/// presentational — no state, no action. In History the parent gates the
/// trailing total on the header's elevation state; this component has no
/// notion of scrolling.
struct SectionHeader<Trailing: View>: View {
    let title: String
    /// Leading inset aligning the title with a row's text column (e.g. flush
    /// with `EntryRow`'s content past its icon column). Nil = default inset.
    let contentLeadingInset: CGFloat?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        contentLeadingInset: CGFloat? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.contentLeadingInset = contentLeadingInset
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.spacingSmall)
            trailing()
        }
        .padding(.leading, contentLeadingInset ?? 0)
        .padding(.vertical, Theme.spacingSmall)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("SectionHeader")
    }
}

#if DEBUG
#Preview("Section header") {
    SectionHeader(title: "Icon") { EmptyView() }
        .padding(.horizontal, Theme.spacingMedium)
        .background(Theme.backgroundPrimary)
}
#endif
