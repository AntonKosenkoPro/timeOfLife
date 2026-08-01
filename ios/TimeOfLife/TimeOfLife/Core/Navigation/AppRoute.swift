import Foundation

/// Routes the auth flow navigates to. Passwordless auth: the welcome screen
/// leads with Sign in with Apple; email/OTP is secondary. Time tracking is the
/// signed-in landing screen, reached via `SessionStore` + `RootView` (not a
/// route). Adding a route here is the only change needed to extend navigation;
/// the polyfill (`AppNavigationStack`) binds these to views.
enum AppRoute: Hashable, Sendable {
    case emailEntry
    case otpEntry(email: String)
    /// Navigates to the Manage Activities screen (Epic 1, story 1-4).
    case manageActivities
    /// Navigates to the category catalog (Epic 1, story 1-5).
    case manageCategories
}
