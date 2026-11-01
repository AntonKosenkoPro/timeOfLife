import SwiftUI

/// Read-only History row for a committed time entry (Design/COMPONENTS.md,
/// history-entry-list Variant H layout). Purely presentational — grouping,
/// category resolution, and duration formatting are owned by the caller.
/// Rows carry no provenance: only the entry's own categories and timing
/// are shown.
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
    /// Whether the entry carries non-empty notes. When true, a small blue
    /// notes icon renders on line 2, immediately left of the timeframe
    /// (history-entry-list notes indicator). Caller-computed so the row
    /// stays presentational.
    var hasNotes: Bool = false
    /// Optional History search presentation (history-search spec,
    /// Design/COMPONENTS.md): in-scope highlight ranges plus a conditional
    /// notes excerpt. `nil` renders exactly the blank-query row.
    var searchPresentation: HistorySearchRowPresentation?

    /// The caption metadata line: the entry's own category names.
    /// Caller-computed so the row stays presentational.
    private var captionText: String {
        categoryNames
    }

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.iconColumnWidth)
                .padding(.top, Self.iconTopAdjustment)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    SearchHighlightedText(
                        text: entry.activityText,
                        highlights: searchPresentation?.nameRanges ?? []
                    )
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.spacingSmall)
                    Text(durationText)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    SearchHighlightedText(
                        text: captionText,
                        highlights: searchPresentation?.captionRanges ?? []
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.spacingSmall)
                    if hasNotes {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(Theme.accentPrimary)
                    }
                    Text(timeframeText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                if let excerpt = searchPresentation?.excerpt {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacingExtraSmall) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(L10n.historySearchNotesLabel.text)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        SearchHighlightedText(
                            text: excerpt.text,
                            highlights: excerpt.highlights
                        )
                        .font(.caption.italic())
                        .foregroundStyle(Theme.textSecondary)
                        // The excerpt builder keeps ~48 characters of leading
                        // context before the focal match; at large Dynamic
                        // Type sizes the caption line holds far fewer
                        // characters, so a 2-line cap could hide the focal
                        // match entirely — relax the cap from .xxLarge up so
                        // the match stays visible.
                        .lineLimit(dynamicTypeSize >= .xxLarge ? nil : 2)
                    }
                }
            }
        }
        .padding(.vertical, Theme.spacingSmall)
        .frame(minHeight: Theme.minTapArea)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Self.accessibilityLabel(
                entryText: entry.activityText,
                categoryNames: categoryNames,
                timeframeText: timeframeText,
                durationText: durationText,
                isInProgress: isInProgress,
                hasNotes: hasNotes,
                excerptText: searchPresentation?.excerpt?.text ?? ""
            )
        )
        .accessibilityIdentifier("EntryRow(\(entry.id))")
    }

    /// The row is a single element whose label folds in the category names
    /// and timing (history-entry-list a11y requirement).
    nonisolated static func accessibilityLabel(
        entryText: String,
        categoryNames: String,
        timeframeText: String,
        durationText: String,
        isInProgress: Bool,
        hasNotes: Bool = false,
        excerptText: String = ""
    ) -> String {
        var parts = [entryText, durationText]
        if !categoryNames.isEmpty { parts.append(categoryNames) }
        parts.append(timeframeText)
        if isInProgress { parts.append(L10n.historyInProgress.text) }
        if hasNotes { parts.append(L10n.historyHasNotes.text) }
        if !excerptText.isEmpty {
            parts.append("\(L10n.historySearchNotesLabel.text) \(excerptText)")
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Entry with categories") {
    EntryRow(
        entry: TimeEntry(
            id: "e1",
            activityText: "Deep work",
            startedAt: Date(timeIntervalSinceNow: -4800),
            endedAt: Date(),
            durationSeconds: 4800
        ),
        icon: "figure.run",
        categoryNames: "Health, Morning",
        timeframeText: "14:00 – 15:20",
        durationText: "1h 20m",
        isInProgress: false
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}

#Preview("Entry without categories") {
    EntryRow(
        entry: TimeEntry(
            id: "e2",
            activityText: "Reading",
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

#Preview("Entry with notes") {
    EntryRow(
        entry: TimeEntry(
            id: "e3",
            activityText: "Deep work",
            startedAt: Date(timeIntervalSinceNow: -4800),
            endedAt: Date(),
            durationSeconds: 4800,
            notes: "remember the HR belt"
        ),
        icon: "figure.run",
        categoryNames: "Health, Morning",
        timeframeText: "14:00 – 15:20",
        durationText: "1h 20m",
        isInProgress: false,
        hasNotes: true
    )
    .padding(.horizontal, Theme.spacingMedium)
    .background(Theme.backgroundPrimary)
}
#endif
