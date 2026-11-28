import SwiftUI
import UIKit

/// The Today composer field (day-planner spec 7.1): a UIKit-backed inline
/// field that submits on Return while DECLINING the default resign, so the
/// field never leaves first responder across a submit — no dismiss/reopen
/// cycle of any duration. SwiftUI `onSubmit` offers no resign suppression
/// (the 6.1 next-tick re-assertion still flashed, because Return resigns
/// first at dispatch); `textFieldShouldReturn` returning `false` runs the
/// custom submit without resigning.
///
/// The same field instance survives draft-clear, chips-line mount/unmount,
/// and snapshot reload (stable representable identity — never re-created
/// with `.id()`), so UIKit never drops first responder. Styling,
/// placeholder, sentences autocapitalization, autocorrection,
/// VoiceOver behavior, the chip fill path, and the
/// invalid-submit-keeps-draft rule all match the SwiftUI field this
/// replaces; focus intent still flows through the caller's `FocusState`.
struct PlannerComposerField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Focus intent (issue #82 precedent: the binding belongs on the field
    /// itself — never on a wrapper container).
    let focused: FocusState<Bool>.Binding
    let accessibilityIdentifier: String
    /// Fired on Return INSTEAD of the default resign (the view submits the
    /// composer draft, as the old `onSubmit` did).
    let onReturn: () -> Void
    /// UIKit editing-state mirror (day-planner 11.1): the `focused`
    /// binding above only issues focus requests — it never observes
    /// UIKit-side focus back, so reading it for visibility stays stale.
    /// The delegate is ground truth for "while editing".
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// Whether the Return key may take its default resign instead of
    /// submitting (day-planner 18.3, sole dismiss path since 21.1): an
    /// empty (or whitespace-only) draft
    /// is invalid for submit, so Return dismisses the keyboard — the only
    /// submit-path resign allowed. Any submittable text declines the
    /// resign and runs `onReturn` instead (day-planner 7.1, pinned by the
    /// focus-lifetime suite). Pinned here because the dispatch verdict is
    /// unit-testable while the resign itself is UIKit default behavior.
    static func shouldResignOnReturn(text: String) -> Bool {
        ActivityName.normalized(text).isEmpty
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Theme.textPrimary)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .yes
        field.returnKeyType = .done
        field.text = text
        field.placeholder = placeholder
        field.accessibilityIdentifier = accessibilityIdentifier
        // Single-line geometry: without required vertical priorities
        // SwiftUI stretches the representable to fill the available area
        // (observed 322 pt tall), swallowing taps below the composer.
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        if focused.wrappedValue {
            // Not in a window yet: defer until the runloop mounts the view.
            DispatchQueue.main.async { [weak field] in
                _ = field?.becomeFirstResponder()
            }
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // External writes only (submit clears the draft, a chip fills
        // it): never echo the in-flight keystroke back, so the cursor stays
        // put while typing.
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
        uiView.accessibilityIdentifier = accessibilityIdentifier
        // Become-only, mirroring SwiftUI `.focused`: the binding asserts
        // focus (initial entry, chip tap) and the begin-echo keeps it
        // truthful — but the binding is an async focus-engine request, so
        // a resign-triggered update storm can read a still-true intent.
        // The end-echo gate (day-planner 24.1) blocks re-acquire after ANY
        // genuine resign — empty Return, drag dismiss, system — until a
        // genuine begin unlatches it. The §22 dispatch clear stays as
        // defense in depth; the gate alone carries the device.
        if focused.wrappedValue, !uiView.isFirstResponder, !context.coordinator.observedResign {
            _ = uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: PlannerComposerField
        /// End-echo (day-planner 24.1): the last delegate-observed
        /// first-responder state — ground truth. A `FocusState` write is a
        /// focus-engine request, not a synchronous store set: the §22
        /// dispatch write may not have flushed when the resign-triggered
        /// update storm runs `updateUIView`, which then reads the
        /// still-true intent and re-grabs — the keyboard never dismisses
        /// (the Hold dismiss probe reproduced this on sim AND device with
        /// the real keyboard path; hosted unit tests stay green either way
        /// because no software keyboard presents in a unit host). A genuine
        /// resign latches this; only a genuine begin unlatches it; update
        /// passes never re-acquire while latched — every resign sticks,
        /// whatever the flush timing. Harmless when spuriously latched
        /// (e.g. a steal while focused): `becomeFirstResponder` is only
        /// ever attempted while NOT first responder, and any real begin
        /// clears the latch.
        private(set) var observedResign = false

        init(_ parent: PlannerComposerField) {
            self.parent = parent
        }

        @objc
        func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        /// Return dispatch (day-planner 18.3, sole dismiss path since
        /// 21.1): an empty draft DISMISSES the keyboard — the only
        /// submit-path resign allowed. Anything else submits WITHOUT
        /// resigning, so the keyboard never animates away regardless of
        /// round-trip latency. The verdict reads the field itself (ground
        /// truth at dispatch), not the binding (which the in-flight
        /// keystroke may not have echoed yet). The resign is EXPLICIT
        /// (day-planner 24.1 fix): UITextField performs NO default resign
        /// on Return — a `true` verdict alone leaves the keyboard up, which
        /// is exactly what the Hold dismiss probe caught on sim and device
        /// (the §18/§22 hosted tests masked it by resigning manually after
        /// the verdict). So the empty branch resigns the field itself and
        /// returns `false` (handled — there is no default to suppress).
        /// The resign branch also clears the focus intent synchronously
        /// (§22 write, kept as defense in depth); what keeps the dismissal
        /// stuck is the end-echo gate latched by `textFieldDidEndEditing`
        /// (day-planner 24.1). The valid-submit branch leaves the intent
        /// set and never resigns (no-resign).
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if PlannerComposerField.shouldResignOnReturn(text: textField.text ?? "") {
                parent.focused.wrappedValue = false
                textField.resignFirstResponder()
                return false
            }
            parent.onReturn()
            return false
        }

        /// Echoes focus INTO the binding only: the binding asserts focus
        /// (initial entry, chip tap, steal recovery) but never
        /// relinquishes it — resigns arrive solely from the system. The
        /// unlatch here is the other half of the end-echo (day-planner
        /// 24.1): a genuine begin is the ONLY thing that re-arms
        /// re-acquire after a genuine resign — the user refocusing is what
        /// releases the gate, never an update pass. The UIKit editing
        /// state itself is reported separately through `onEditingChanged`
        /// (the binding never observes UIKit-side focus back, so it cannot
        /// drive visibility).
        func textFieldDidBeginEditing(_ textField: UITextField) {
            observedResign = false
            parent.focused.wrappedValue = true
            parent.onEditingChanged(true)
        }

        /// End-echo, latching half (day-planner 24.1): mirrors the
        /// UIKit-side resign into the editing state (visibility) AND latches
        /// the observed resign, so the next update pass cannot re-acquire
        /// (see `updateUIView`). The `focused` binding is deliberately left
        /// for the §22 dispatch write / SwiftUI reconcile — the gate alone
        /// decides re-acquire.
        func textFieldDidEndEditing(_ textField: UITextField) {
            observedResign = true
            parent.onEditingChanged(false)
        }
    }
}
