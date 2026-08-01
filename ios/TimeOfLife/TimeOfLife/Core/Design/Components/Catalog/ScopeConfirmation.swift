import SwiftUI

/// Destructive two-option confirmation for deleting an activity
/// that has past entries (F10/U5).
///
/// The user must choose between deleting the entire activity (and all its
/// entries) or only the current entry. `entryCount` must be > 0 (D18).
struct ScopeConfirmation: View {
    @Binding var isPresented: Bool
    let entryCount: Int
    let onDeleteAll: () -> Void
    let onDeleteEntryOnly: () -> Void
    let onCancel: () -> Void
    @State private var selectedAction = false

    var body: some View {
        Text("")
            .confirmationDialog(
                L10n.deleteActivityTitle.text,
                isPresented: $isPresented
            ) {
                Button(L10n.deleteActivityEntire.text(entryCount),
                       role: .destructive) {
                    selectedAction = true
                    isPresented = false
                    onDeleteAll()
                }

                Button(L10n.deleteActivityEntryOnly.text,
                       role: .destructive) {
                    selectedAction = true
                    isPresented = false
                    onDeleteEntryOnly()
                }

                Button(L10n.deleteActivityCancel.text,
                       role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(L10n.deleteActivityMessage.text(entryCount))
            }
            .onChange(of: isPresented) { newValue in
                if !newValue, !selectedAction {
                    dismiss()
                }
                selectedAction = false
            }
    }

    private func dismiss() {
        isPresented = false
        onCancel()
    }
}

#if DEBUG

private struct ScopeConfirmationPreview: View {
    @State private var showDialog = false

    var body: some View {
        VStack {
            Button("Show Dialog") { showDialog = true }
        }
        .scopeConfirmation(
            isPresented: $showDialog,
            entryCount: 5,
            onDeleteAll: {},
            onDeleteEntryOnly: {},
            onCancel: {}
        )
    }
}

fileprivate extension View {
    /// Convenience modifier wrapping `ScopeConfirmation` in a `.background` layer
    /// so it can be triggered from any view.
    func scopeConfirmation(
        isPresented: Binding<Bool>,
        entryCount: Int,
        onDeleteAll: @escaping () -> Void,
        onDeleteEntryOnly: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        background(
            ScopeConfirmation(
                isPresented: isPresented,
                entryCount: entryCount,
                onDeleteAll: onDeleteAll,
                onDeleteEntryOnly: onDeleteEntryOnly,
                onCancel: onCancel
            )
        )
    }
}

#Preview("EN Light") {
    ScopeConfirmationPreview()
}

#Preview("RU Dark") {
    ScopeConfirmationPreview()
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}

#endif
