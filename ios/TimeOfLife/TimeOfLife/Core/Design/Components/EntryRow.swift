import SwiftUI

/// Maps an entry's `source` (entry-provenance spec D10) to the localized
/// "via <Source>" row label; `manual` shows nothing. Shared by the History
/// view model and the activity-detail view model.
enum EntryProvenance {
    static func viaText(for source: String) -> String {
        switch source {
        case "widget": return L10n.provenanceViaWidget.text
        case "siri": return L10n.provenanceViaSiri.text
        case "control": return L10n.provenanceViaControl.text
        case "screentime": return L10n.provenanceViaScreentime.text
        case "garmin": return L10n.provenanceViaGarmin.text
        case "calendar": return L10n.provenanceViaCalendar.text
        case "healthkit": return L10n.provenanceViaHealthkit.text
        default: return ""
        }
    }

    /// Bare localized source name for the detail sheet's entry rows, shown
    /// next to the shared sync icon ("Garmin", not "via Garmin"); `manual`
    /// and unknown sources show nothing.
    static func name(for source: String) -> String {
        switch source {
        case "widget": return L10n.provenanceNameWidget.text
        case "siri": return L10n.provenanceNameSiri.text
        case "control": return L10n.provenanceNameControl.text
        case "screentime": return L10n.provenanceNameScreentime.text
        case "garmin": return L10n.provenanceNameGarmin.text
        case "calendar": return L10n.provenanceNameCalendar.text
        case "healthkit": return L10n.provenanceNameHealthkit.text
        default: return ""
        }
    }
}

/// Read-only History row for a committed time entry (Design/COMPONENTS.md,
/// history-entry-list Variant H layout). Purely presentational — grouping,
/// category resolution, and duration formatting are owned by the caller.
struct EntryRow: View {
    /// Width of the leading icon column, shared with the History day-group
    /// header's column alignment (design D10).
    static let iconColumnWidth: CGFloat = 28
    /// Horizontal gap between the icon column and the text column.
    static let columnSpacing: CGFloat = 16
    /// Negative top padding for the icon so its optical top aligns with the
    /// activity name's cap-height top (not the text frame top). Tuned for
    /// `.title3` icon + `.headline` name; re-tune if the font stack changes.
    static let iconTopAdjustment: CGFloat = -1.5

    let entry: TimeEntry
    let icon: String
    let categoryNames: String
    let timeframeText: String
    let durationText: String
    let isInProgress: Bool
    /// Localized "via <Source>" provenance label; empty for `manual`
    /// entries and unknown sources (entry-provenance D7).
    var viaText: String = ""

    /// The caption metadata line: category names, then the provenance
    /// label. Both are caller-computed so the row stays presentational.
    private var captionText: String {
        [categoryNames, viaText]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.iconColumnWidth)
                .padding(.top, Self.iconTopAdjustment)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.activityName)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.spacingSmall)
                    Text(durationText)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(captionText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.spacingSmall)
                    Text(timeframeText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, Theme.spacingSmall)
        .frame(minHeight: Theme.minTapArea)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Self.accessibilityLabel(
                activityName: entry.activityName,
                categoryNames: categoryNames,
                timeframeText: timeframeText,
                durationText: durationText,
                isInProgress: isInProgress,
                viaText: viaText
            )
        )
        .accessibilityIdentifier("EntryRow(\(entry.id))")
    }

    /// The row is a single element whose label folds in the category names,
    /// provenance, and timing (history-entry-list a11y requirement).
    nonisolated static func accessibilityLabel(
        activityName: String,
        categoryNames: String,
        timeframeText: String,
        durationText: String,
        isInProgress: Bool,
        viaText: String = ""
    ) -> String {
        var parts = [activityName, durationText]
        if !categoryNames.isEmpty { parts.append(categoryNames) }
        if !viaText.isEmpty { parts.append(viaText) }
        parts.append(timeframeText)
        if isInProgress { parts.append(L10n.historyInProgress.text) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Entry with categories") {
    EntryRow(
        entry: TimeEntry(
            id: "e1",
            activityID: "a1",
            activityName: "Deep work",
            startedAt: Date(timeIntervalSinceNow: -4800),
            endedAt: Date(),
            durationSeconds: 4800
        ),
        icon: "figure.run",
        categoryNames: "Health, Morning",
        timeframeText: "14:00 – 15:20",
        durationText: "1h 20m",
        isInProgress: false,
        viaText: EntryProvenance.viaText(for: "screentime")
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}

#Preview("Entry without categories") {
    EntryRow(
        entry: TimeEntry(
            id: "e2",
            activityID: "a2",
            activityName: "Reading",
            startedAt: Date(timeIntervalSinceNow: -1980),
            endedAt: Date(),
            durationSeconds: 1980
        ),
        icon: "questionmark",
        categoryNames: "",
        timeframeText: "09:00 – 09:33",
        durationText: "33m",
        isInProgress: false
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}
#endif
