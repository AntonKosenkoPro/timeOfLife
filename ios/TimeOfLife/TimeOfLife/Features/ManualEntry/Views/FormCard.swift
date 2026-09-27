import SwiftUI

/// Shared card chrome for the entry-form cards (entry-editor spec): rounded
/// secondary-background card with tap-away keyboard dismissal.
///
/// The tap-away is a *simultaneous* tap — never a blocking gesture (the
/// all-native-gestures rule forbids disabling/blocking system gestures, not
/// observing taps alongside them): child `Button`s (TagSelector chips,
/// date/time pills) still receive their taps; the simultaneous tap fires
/// alongside so toggling a chip also resigns focus instead of leaving the
/// keyboard open. A plain card-level `.onTapGesture` cannot do this — the
/// child button consumes the tap and the card handler never fires.
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
        .simultaneousGesture(TapGesture().onEnded { resignFocus() })
    }

    private var chrome: some View {
        content()
            .padding(Theme.spacingMedium)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
