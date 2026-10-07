import SwiftUI

/// The shared Notes editor page (entry-editor + timer-capture-experience):
/// a dedicated page for free-text notes, pushed on the caller's
/// `NavigationStack` from the entry-form presenter or the running Track
/// notes button.
///
/// Copy-on-open commit semantics: the page edits a local `@State` copy —
/// keystrokes never touch caller state. X discards the copy, ✓ writes it
/// back through `onSave` (form draft notes or running-draft snapshot) and
/// pops. There is no keyboard Done key: Return inserts a newline and the
/// system Back button is hidden, so dismissal is X/✓ plus swipe-back
/// (which pops and discards, like X).
///
/// Placeholder reuses `L10n.entryNotesPlaceholder` (`TextEditor` has no
/// native placeholder); `Theme` semantic colors only.
struct NotesEditorPage: View {
    /// Write-back on ✓ (form draft or running draft, caller-owned).
    let onSave: (String) -> Void
    /// Local draft: the caller sees exactly one update, on save.
    @State private var draft: String
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss)
    private var dismiss

    init(initialText: String, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        TextEditor(text: $draft)
            .focused($fieldFocused)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Theme.transparent)
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(L10n.entryNotesPlaceholder.text)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, DynamicTypeMetrics.editorTextOriginInsets.top)
                        .padding(.leading, DynamicTypeMetrics.editorTextOriginInsets.leading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.spacingMedium)
            .navigationTitle(L10n.entryNotesLabel.text)
            .navigationBarTitleDisplayMode(.inline)
            // No system Back: X is the sole cancel path, so the bar reads
            // X · title · ✓. Swipe-back still pops (and discards, like X).
            .navigationBarBackButtonHidden(true)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                EditorToolbar(
                    showsDismiss: true,
                    dismissAccessibilityLabel: L10n.entryDismissLabel.text,
                    dismissAccessibilityId: "NotesEditorDismissButton",
                    isDismissDisabled: false,
                    onDismiss: dismiss(),
                    showsConfirm: true,
                    confirmAccessibilityLabel: L10n.entryConfirmSaveLabel.text,
                    confirmAccessibilityId: "NotesEditorSaveButton",
                    isConfirmDisabled: false
                ) {
                    onSave(draft)
                    dismiss()
                }
            }
            .accessibilityIdentifier("NotesEditorPage")
            .task {
                // Autofocus waits out the push transition (the NamePicker
                // precedent): focusing instantly fires the keyboard
                // mid-push and the keyboard-driven relayout jumps.
                // Cancelled automatically on pop.
                guard await FocusDelay.settle() else { return }
                fieldFocused = true
            }
    }
}
