import Foundation

/// Routes the auth flow navigates to. Adding a route here is the only change
/// needed to extend navigation; the polyfill (`AppNavigationStack`) binds
/// these to views.
enum AppRoute: Hashable, Sendable {
    case signIn
    case signUp
    case forgotPassword
    case resetPassword(token: String)
    case verifyEmail(token: String)
    case signedIn
}