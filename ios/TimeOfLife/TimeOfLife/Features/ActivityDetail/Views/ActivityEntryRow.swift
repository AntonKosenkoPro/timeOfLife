import SwiftUI

/// Entry-only row for the activity detail sheet (activity-detail-sheet
/// spec): time range, provenance (shared sync icon + source name), and
/// duration. Carries no activity identity — the sheet header owns that.
/// Purely presentational; the caller computes all strings.
struct ActivityEntryRow: View {
    /// Shared provenance glyph for every non-manual source.
    static let provenanceIcon = "arrow.triangle.2.circlepath"

    let timeRangeText: String
    /// Bare localized source name; empty for `manual` entries.
    let provenanceName: String
    let durationText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(timeRangeText)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.spacingSmall)
            if !provenanceName.isEmpty {
                HStack(spacing: Theme.spacingExtraSmall) {
                    Image(systemName: Self.provenanceIcon)
                    Text(provenanceName)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Text(durationText)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.spacingSmall)
        .frame(minHeight: Theme.minTapArea)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(
            timeRangeText: timeRangeText,
            provenanceName: provenanceName,
            durationText: durationText
        ))
    }

    nonisolated static func accessibilityLabel(
        timeRangeText: String,
        provenanceName: String,
        durationText: String
    ) -> String {
        var parts = [timeRangeText, durationText]
        if !provenanceName.isEmpty {
            parts.append(provenanceName)
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Entry row") {
    ActivityEntryRow(
        timeRangeText: "2:34 PM – 5:46 PM",
        provenanceName: "Garmin",
        durationText: "3h 11m 46s"
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}

#Preview("Entry row, manual, cross-midnight") {
    ActivityEntryRow(
        timeRangeText: "Yesterday, 11:34 PM – Today, 0:34 AM",
        provenanceName: "",
        durationText: "1h 0m 0s"
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}
#endif
