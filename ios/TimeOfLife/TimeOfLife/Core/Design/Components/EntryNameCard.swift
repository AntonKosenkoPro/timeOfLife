import SwiftUI

/// The shared Name entry card (manual-entry name grammar, day-planner
/// 16.3): a full-card push row (caption + chevron over the value or the
/// placeholder) opening the shared `NamePicker` on the caller's
/// `NavigationStack` — the system Back is the cancel path (the local picker
/// draft is discarded, the caller untouched), row tap and keyboard Done are
/// the only completions, both caller-owned. Consumed by the Log Time form
/// and the planner task editor sheet alike — one component, never a copy —
/// so both surfaces share Name entry behavior, card chrome, and completion
/// semantics; order, validation, and the save gate stay caller-owned (the
/// sheet omits Start/End).
struct EntryNameCard: View {
    /// The caller's current name draft (displayed verbatim, or the
    /// placeholder when empty).
    let value: String
    /// The placeholder shown when the draft is empty.
    let placeholder: String
    /// Caller recents for the picker, newest-first (already capped or full
    /// — the picker reads only).
    let recents: [ExactName]
    /// The id→Category map for picker row icons.
    let categories: [String: Category]
    /// Hint shown when there are no recents and nothing is typed.
    let emptyHint: String
    /// The card's accessibility identifier (per-surface contract).
    let accessibilityID: String
    /// Row-tap completion (exact text + ordered categories).
    let onCompleteSuggestion: (ExactName) -> Void
    /// Done-with-text completion (typed text).
    let onCompleteText: (String) -> Void

    var body: some View {
        // Full-card push: the link owns the padded chrome (mirrors
        // FormCard) so caption, chevron, value, blank, and padding
        // all push. No tap-away here — it would consume those taps.
        // No resign (issue #67): focus transfers to the picker with
        // no keyboard flicker.
        NavigationLink {
            NamePicker(
                initialText: value,
                recents: recents,
                categories: categories,
                placeholder: placeholder,
                emptyHint: emptyHint,
                onCompleteSuggestion: onCompleteSuggestion,
                onCompleteText: onCompleteText
            )
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                HStack(spacing: Theme.spacingSmall) {
                    Text(L10n.entryNameLabel.text)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(value.isEmpty ? placeholder : value)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(value.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Theme.minTapArea)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMedium)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.entryNameLabel.text)
        .accessibilityValue(value)
        .accessibilityIdentifier(accessibilityID)
    }
}
