import SwiftUI

/// Transient undo affordance shown after a delete (R3/U6).
///
/// Purely presentational — the auto-dismiss timer and the 30 s undo window
/// are owned by the parent ViewModel (D17).
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button(L10n.undoButton.text) {
                onUndo()
            }
            .tint(Theme.accentPrimary)
            .frame(minWidth: Theme.minTapArea, minHeight: Theme.minTapArea)
            .contentShape(Rectangle())
            .accessibilityIdentifier("UndoToastButton")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.minTapArea, height: Theme.minTapArea)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.toastDismiss.text)
            .accessibilityIdentifier("UndoToastDismiss")
        }
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, Theme.spacingSmall)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .fill(Theme.backgroundSecondary)
                .shadow(color: .black.opacity(Theme.shadowSmall.opacity),
                        radius: Theme.shadowSmall.radius,
                        x: 0, y: Theme.shadowSmall.y)
        )
        .padding(.horizontal, Theme.spacingMedium)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG

private struct UndoToastPreview: View {
    var body: some View {
        VStack {
            Spacer()
            UndoToast(
                message: "Deleted \"Reading\"",
                onUndo: {},
                onDismiss: {}
            )
        }
    }
}

#Preview("EN Light") {
    UndoToastPreview()
}

#Preview("RU Dark") {
    UndoToastPreview()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
