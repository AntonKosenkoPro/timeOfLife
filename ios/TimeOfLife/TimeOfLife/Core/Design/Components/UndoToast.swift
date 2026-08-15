import SwiftUI

/// Transient 30-second undo affordance shown after a delete (R3/U6,
/// Design/COMPONENTS.md `UndoToast`). Purely presentational — the
/// wall-clock countdown and the 30 s undo window are owned by the parent
/// ViewModel (category-management D7). Undo restores from the client-side
/// undo buffer before the deletion is committed.
struct UndoToast: View {
    let message: String
    let remainingSeconds: Int
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(String(format: L10n.undoSecondsRemaining.text, remainingSeconds))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.spacingSmall)
            Button(L10n.undoButton.text, action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityIdentifier("UndoToastButton")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel(L10n.undoDismiss.text)
        }
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, Theme.spacingSmall)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
        .shadow(color: Theme.shadowSmall, radius: 4, y: 2)
        .padding(.horizontal, Theme.spacingMedium)
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
