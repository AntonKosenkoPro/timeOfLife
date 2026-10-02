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
///
/// One-shot resign suppress (issue #67): the entry-form Notes `×` lives
/// inside this card, so its tap would fire both the button action (clear)
/// and this simultaneous tap (resign) — dismissing the keyboard the clear
/// must keep open (FURPS Timetracking F13: clear field only). The notes
/// `×` call-site — and only that site — arms `suppressNextResign`; the
/// gesture below skips exactly one resign for it and resets, so chip taps
/// (which never arm the flag) resign exactly as today.
///
/// Ordering (measured on-device): the card gesture's `onEnded` can run
/// before the button action for the same touch-up, so arming the flag in
/// the clear action is too late — the notes `×` arms it on touch-down
/// (a zero-distance drag alongside the button tap) instead, which always
/// precedes every touch-up handler. A cancelled tap (press the `×`,
/// slide off, release elsewhere) arms a stale suppress, but it is
/// consumed — one skipped resign, then normal behavior — on the very next
/// card-gesture fire, so the window self-heals on the next tap.
struct FormCard<Content: View>: View {
    private let accessibilityID: String?
    private let resignFocus: () -> Void
    private let suppressNextResign: Binding<Bool>
    private let content: () -> Content

    /// - Parameter resignFocus: Autoclosure (not a closure literal) so call
    ///   sites keep single-trailing-closure form per
    ///   `multiple_closures_with_trailing_closure`, e.g.
    ///   `resignFocus: focusedField = nil`.
    /// - Parameter suppressNextResign: One-shot skip for the next tap-gesture
    ///   resign (issue #67, notes `×` only). Defaults to off; consumed on
    ///   the very next gesture fire regardless.
    init(
        accessibilityID: String? = nil,
        resignFocus: @autoclosure @escaping () -> Void,
        suppressNextResign: Binding<Bool> = .constant(false),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accessibilityID = accessibilityID
        self.resignFocus = resignFocus
        self.suppressNextResign = suppressNextResign
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
        .simultaneousGesture(TapGesture().onEnded {
            if suppressNextResign.wrappedValue {
                suppressNextResign.wrappedValue = false
            } else {
                resignFocus()
            }
        })
    }

    private var chrome: some View {
        content()
            .padding(Theme.spacingMedium)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
