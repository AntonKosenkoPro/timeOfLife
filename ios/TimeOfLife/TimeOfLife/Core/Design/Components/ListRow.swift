import SwiftUI

/// A single row in a settings or history list (Design/COMPONENTS.md).
struct ListRow<Trailing: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        icon: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }
    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.accentPrimary)
                    .font(.body)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, Theme.spacingSmall)
        .frame(minHeight: Theme.minTapArea)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("List Row") {
    ListRow(title: "Deep work", icon: "clock", subtitle: "2h 14m") {
        Text("Today")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
    .padding(.horizontal)
    .background(Theme.backgroundPrimary)
}
#endif
