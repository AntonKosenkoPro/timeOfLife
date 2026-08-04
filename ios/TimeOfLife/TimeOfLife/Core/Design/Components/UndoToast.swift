import SwiftUI

/// Transient 30-second undo affordance shown after a delete (R3/U6).
/// Purely presentational — the auto-dismiss timer and the 30 s undo window
/// are owned by the parent ViewModel.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
            Button {
                onUndo()
            } label: {
                Text(L10n.undoButton.text)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accentPrimary)
            }
            .accessibilityIdentifier("UndoToastButton")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, Theme.spacingSmall)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
