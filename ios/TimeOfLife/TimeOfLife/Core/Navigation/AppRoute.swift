import Foundation

/// Routes the auth flow navigates to. Passwordless: sign-up and sign-in
/// collapse into email-entry → OTP-entry → signed-in. Adding a route here is
/// the only change needed to extend navigation; the polyfill
/// (`AppNavigationStack`) binds these to views.
enum AppRoute: Hashable, Sendable {
    case emailEntry
    case otpEntry(email: String)
    case signedIn
}
