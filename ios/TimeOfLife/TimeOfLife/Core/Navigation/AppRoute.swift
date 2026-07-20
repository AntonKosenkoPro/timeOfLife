import Foundation

/// Routes the app navigates to. Passwordless auth: sign-up and sign-in collapse
/// into email-entry → OTP-entry. Time tracking is the signed-in landing screen.
/// Adding a route here is the only change needed to extend navigation; the
/// polyfill (`AppNavigationStack`) binds these to views.
enum AppRoute: Hashable, Sendable {
    case emailEntry
    case otpEntry(email: String)
    case signedIn
    case timer
}
