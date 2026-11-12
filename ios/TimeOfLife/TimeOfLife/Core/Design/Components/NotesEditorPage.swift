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
/// The nav-bar subtitle pairs the entry name with a live notes counter
/// (`<name> • <count>/2000`, name omitted when empty), counting every rune
/// against the relay bound. Past the bound the counter renders red while ✓
/// stays enabled; an over-limit save attempt shakes the subtitle, plays the
/// error haptic, and saves nothing without popping (shake suppressed under
/// Reduce Motion; the haptic still fires).
///
/// Placeholder uses `L10n.notesEditorPlaceholder` ("Dear diary..."),
/// distinct from the collapsed presenters' `L10n.entryNotesPlaceholder`
/// (`TextEditor` has no native placeholder); `Theme` semantic colors only.
struct NotesEditorPage: View {
    /// Entry name shown in the counter subtitle (static open-time snapshot —
    /// neither caller retexts underneath the page).
    let entryName: String
    /// Write-back on ✓ (form draft or running draft, caller-owned). Unused
    /// on review surfaces, where `confirmReview` owns ✓.
    let onSave: (String) -> Void
    /// Live text reports (every keystroke): set only by the running-notes
    /// caller so it can detect unconfirmed changes (History/Log Time keep
    /// pure copy-on-open semantics with nil here).
    let onTextChange: ((String) -> Void)?
    /// Disables the field and the ✓ while set (stop flight or review write):
    /// the decision text is locked, but X stays live so abandoning is always
    /// available.
    let isInputDisabled: Bool
    /// Async review confirm (preserve-running-notes-on-live-stop): when set,
    /// ✓ awaits its result and pops only on `true`, so a failed notes write
    /// keeps the page (and its text) open for correction/retry. Nil keeps
    /// the immediate onSave-then-pop contract for History/Log Time and the
    /// running draft.
    let confirmReview: ((String) async -> Bool)?
    /// Local draft: the caller sees exactly one update, on save.
    @State private var draft: String
    /// Failed over-limit save attempts; keys the shake animation.
    @State private var shakeAttempts = 0
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Sync form (History/Log Time/running draft): ✓ calls `onSave` and pops
    /// immediately. The trailing closure binds `onSave` (the only closure).
    init(initialText: String, entryName: String, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: initialText)
        self.entryName = entryName
        self.onSave = onSave
        self.onTextChange = nil
        self.isInputDisabled = false
        self.confirmReview = nil
    }

    /// Review form (preserve-running-notes-on-live-stop): ✓ awaits
    /// `confirmReview` and pops only on `true`. All plumbing is explicit
    /// (no defaults) so each call site states its contract; the non-closure
    /// `isInputDisabled` stays last (the `CategoryEditorForm` precedent) so
    /// no trailing-closure rewrite applies.
    init(
        initialText: String,
        entryName: String,
        onTextChange: ((String) -> Void)?,
        confirmReview: @escaping ((String) async -> Bool),
        isInputDisabled: Bool
    ) {
        _draft = State(initialValue: initialText)
        self.entryName = entryName
        // Unused here: `confirmReview` owns ✓ on review surfaces.
        self.onSave = { _ in }
        self.onTextChange = onTextChange
        self.isInputDisabled = isInputDisabled
        self.confirmReview = confirmReview
    }

    /// Scalar count of the draft (every keystroke counts).
    private var count: Int { NotesCounter.count(draft) }

    /// Whether the draft exceeds the relay bound.
    private var isOverLimit: Bool { NotesCounter.isOverLimit(draft) }

    var body: some View {
        TextEditor(text: $draft)
            .focused($fieldFocused)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Theme.transparent)
            .disabled(isInputDisabled)
            .onChange(of: draft) { _, newValue in onTextChange?(newValue) }
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(L10n.notesEditorPlaceholder.text)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, DynamicTypeMetrics.editorTextOriginInsets.top)
                        .padding(.leading, DynamicTypeMetrics.editorTextOriginInsets.leading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.spacingMedium)
            .navigationBarTitleDisplayMode(.inline)
            // No system Back: X is the sole cancel path, so the bar reads
            // X · title · ✓. Swipe-back still pops (and discards, like X).
            .navigationBarBackButtonHidden(true)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Principal subtitle (LogTime `titleSubtitle` precedent):
                // the page title plus the live counter footnote. The stack
                // carries the over-limit shake: a horizontal-offset keyframe
                // track keyed on the failed-attempt counter (keyframeAnimator,
                // iOS 17+ API), so the counter line itself shakes, not the
                // editor text.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(L10n.entryNotesLabel.text)
                            .font(.headline)
                            .lineLimit(1)
                        Text(counterText)
                            .font(.footnote)
                            .foregroundStyle(isOverLimit ? Theme.danger : Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeAttempts) { content, value in
                        content.offset(x: value)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(12, duration: 0.06)
                            CubicKeyframe(-9, duration: 0.06)
                            CubicKeyframe(6, duration: 0.06)
                            CubicKeyframe(-3, duration: 0.06)
                            CubicKeyframe(0, duration: 0.06)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("NotesEditorCounter")
                }
                EditorToolbar(
                    showsDismiss: true,
                    dismissAccessibilityLabel: L10n.entryDismissLabel.text,
                    dismissAccessibilityId: "NotesEditorDismissButton",
                    isDismissDisabled: false,
                    onDismiss: dismiss(),
                    showsConfirm: true,
                    confirmAccessibilityLabel: L10n.entryConfirmSaveLabel.text,
                    confirmAccessibilityId: "NotesEditorSaveButton",
                    isConfirmDisabled: isInputDisabled
                ) {
                    confirm()
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

    /// `<name> • <count>/2000`, name omitted when empty.
    private var counterText: String {
        if entryName.isEmpty {
            String(format: L10n.notesEditorCounter.text, locale: .current, count)
        } else {
            String(format: L10n.notesEditorSubtitle.text, locale: .current, entryName, count)
        }
    }

    /// ✓ always commits within the bound; an over-limit attempt shakes the
    /// subtitle, plays the error haptic, and stays (no save, no pop). The
    /// haptic fires even under Reduce Motion — it is the non-motion channel
    /// when the shake is suppressed. With `confirmReview` set (the post-stop
    /// review surface), ✓ awaits the async write and pops only on success,
    /// so a failed write keeps the page open for correction/retry.
    private func confirm() {
        if isOverLimit {
            Haptics.error()
            if !reduceMotion {
                shakeAttempts += 1
            }
            return
        }
        if let confirmReview {
            Task { @MainActor in
                if await confirmReview(draft) { dismiss() }
            }
            return
        }
        onSave(draft)
        dismiss()
    }
}
