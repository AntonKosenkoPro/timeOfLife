import SwiftUI

/// Section title used in editor screens to label input sections, and in
/// History as the day-group header (Design/COMPONENTS.md). Purely
/// presentational — no state, no action. In History the header is a static
/// two-line block (day label + total subline, Calendar-Agenda-like); it has
/// no notion of scrolling or pinning.
struct SectionHeader<Trailing: View>: View {
    let title: String
    /// Optional second line under the title (History day total). Nil renders
    /// the single-line editor presentation exactly as before.
    let subtitle: String?
    /// Leading inset aligning the title with a row's text column (e.g. flush
    /// with `EntryRow`'s content past its icon column). Nil = default inset.
    let contentLeadingInset: CGFloat?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        contentLeadingInset: CGFloat? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.contentLeadingInset = contentLeadingInset
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
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

#Preview("Section header with subtitle") {
    SectionHeader(title: "Today", subtitle: "8h 30m tracked") { EmptyView() }
        .padding(.horizontal, Theme.spacingMedium)
        .background(.bar)
}
#endif
