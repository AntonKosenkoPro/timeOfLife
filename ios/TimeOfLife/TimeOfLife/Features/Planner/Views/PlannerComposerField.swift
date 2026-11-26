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
        // truthful, so any update while unfocused re-asserts. Resigns arrive
        // solely from the system — nothing here ever resigns.
        if focused.wrappedValue, !uiView.isFirstResponder {
            _ = uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: PlannerComposerField

        init(_ parent: PlannerComposerField) {
            self.parent = parent
        }

        @objc
        func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        /// Suppresses the Return default: submits WITHOUT resigning, so the
        /// keyboard never animates away regardless of round-trip latency.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }

        /// Echoes focus INTO the binding only: the binding asserts focus
        /// (initial entry, chip tap, steal recovery) but never
        /// relinquishes it — resigns arrive solely from the system, and the
        /// next update re-asserts (see `updateUIView`). No end-echo: writing
        /// `false` here would disarm that recovery and strand the field
        /// unfocused after any steal.
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focused.wrappedValue = true
        }
    }
}
