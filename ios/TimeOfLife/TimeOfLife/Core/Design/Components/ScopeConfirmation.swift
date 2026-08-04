import SwiftUI

/// Destructive two-option confirmation for deleting an activity that has
/// past entries (F10/U5). The user chooses between deleting the entire
/// activity (and all its entries) or only the latest entry.
///
/// On iOS 16+, uses `ConfirmationDialog`. On iOS 15, falls back to
/// `.confirmationDialog` (available iOS 15+) or an `.alert` with buttons.
struct ScopeConfirmation: View {
    @Binding var isPresented: Bool
    let entryCount: Int
    let onDeleteAll: () -> Void
    let onDeleteEntryOnly: () -> Void
    let onCancel: () -> Void

    var body: some View {
        EmptyView()
            .confirmationDialog(
                L10n.deleteActivityTitle.text,
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button(
                    String(format: L10n.deleteActivityEntire.text, entryCount),
                    role: .destructive
                ) {
                    onDeleteAll()
                }
                Button(L10n.deleteActivityEntryOnly.text, role: .destructive) {
                    onDeleteEntryOnly()
                }
                Button(L10n.deleteActivityCancel.text, role: .cancel) {
                    onCancel()
                }
            } message: {
                Text(String(format: L10n.deleteActivityMessage.text, entryCount))
            }
    }
}
