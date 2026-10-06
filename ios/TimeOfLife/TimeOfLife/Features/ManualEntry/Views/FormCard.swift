import SwiftUI

/// Shared card chrome for the entry-form cards (entry-editor spec): rounded
/// secondary-background card with tap-away keyboard dismissal.
///
/// The tap-away is a *plain* tap — never a blocking gesture: it fires only
/// for taps no child consumes (labels, padding, background). Taps on child
/// `Button`s (TagSelector chips, date/time pills, the name-row link) are
/// consumed by those controls and never reach this handler, so every control
/// that must dismiss the keyboard resigns explicitly in its own action
/// (issue #67: the Notes `×` deliberately does NOT resign — it clears only,
/// so no flicker and no race is possible).
///
/// Field cards (name/notes) use this too: tapping the `TextField` itself
/// keeps working — the field's focus claim is applied after the tap
/// gesture's resign, so the field still wins focus, while taps anywhere else
/// on the card (label, padding) dismiss the keyboard.
struct FormCard<Content: View>: View {
    private let accessibilityID: String?
    private let resignFocus: () -> Void
    private let content: () -> Content

    /// - Parameter resignFocus: Autoclosure (not a closure literal) so call
    ///   sites keep single-trailing-closure form per
    ///   `multiple_closures_with_trailing_closure`, e.g.
    ///   `resignFocus: focusedField = nil`.
    init(
        accessibilityID: String? = nil,
        resignFocus: @autoclosure @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accessibilityID = accessibilityID
        self.resignFocus = resignFocus
        self.content = content
    }

    var body: some View {
        Group {
            if let accessibilityID {
                chrome.accessibilityIdentifier(accessibilityID)
            } else {
                chrome
            }
        }
        .onTapGesture {
            resignFocus()
        }
    }

    private var chrome: some View {
        content()
            .padding(Theme.spacingMedium)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
