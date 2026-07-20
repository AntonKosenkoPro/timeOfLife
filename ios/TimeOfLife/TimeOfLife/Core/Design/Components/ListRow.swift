import SwiftUI

/// A single row in a settings or history list.
///
/// Provides an optional leading icon, a title, an optional subtitle, and a
/// trailing view supplied by the caller.
struct ListRow<Trailing: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMedium) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Theme.accentPrimary)
                    .frame(width: Theme.minTapArea, height: Theme.minTapArea)
            }

            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
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
    }
}

#if DEBUG
#Preview("List Row") {
    ListRow(
        icon: "clock",
        title: "Design work",
        subtitle: "2h 15m"
    ) {
        Text("Today")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
    .padding()
}
#endif
