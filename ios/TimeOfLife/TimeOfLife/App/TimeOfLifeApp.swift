import SwiftUI

/// Entry point of the Time of Life app.
///
/// Owns the composition root (`AppContainer`) and the deep-link entry point
/// for the `timeoflife://` URL scheme. The magic link is
/// `timeoflife://verify?code=<6-digit>`: it pre-fills the OTP code (via
/// `AppNavigationStack.pendingDeepLinkCode`) and pushes `.otpEntry` using the
/// cached email from the prior `requestOtp`.
@main
struct TimeOfLifeApp: App {
    @StateObject private var container: AppContainer
    @StateObject private var session: SessionStore
    @StateObject private var navigation: AppNavigationStack

    init() {
        let container = AppContainer.production()
        self._container = StateObject(wrappedValue: container)
        self._session = StateObject(wrappedValue: container.sessionStore)
        self._navigation = StateObject(wrappedValue: container.navigation)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(session)
                .environmentObject(navigation)
                .preferredColorScheme(nil) // follow system
                .onOpenURL { url in
                    handle(url: url)
                }
        }
    }

    /// Parses a `timeoflife://verify?code=…` magic link and pushes the OTP
    /// entry route with the code pre-filled. The email is resolved from the
    /// cached email set by the preceding `requestOtp`; if none is cached the
    /// route carries an empty email and the OTP screen waits for the user to
    /// go back and enter one.
    private func handle(url: URL) {
        guard let parsed = DeepLink.parse(url: url) else { return }
        switch parsed {
        case .otpEntry(let email):
            // Stage the code so `OtpEntryView` can pre-fill + auto-submit.
            if let code = DeepLink.code(from: url) {
                navigation.pendingDeepLinkCode = code
            }
            // Resolve the email from the cached email when the link doesn't
            // carry one (it never does — only the code is in the URL). On a
            // warm resume the in-memory `cachedEmail` is set; on a cold launch
            // (app killed by the OS) it is gone, so fall back to the persisted
            // pending email written by the preceding `requestOtp`.
            let resolvedEmail = email.isEmpty ? container.authService.resolveDeepLinkEmail() : email
            // If already on the OTP screen, don't push a duplicate — just
            // let the pending-code side channel update the existing view.
            if case .otpEntry = navigation.path.last {
                return
            }
            navigation.push(.otpEntry(email: resolvedEmail))
        case .signedIn, .emailEntry, .timer:
            break
        }
    }
}

/// Pure parsing of `timeoflife://` deep links, factored out for unit testing.
/// The magic link is `timeoflife://verify?code=<6-digit>`. The backend
/// historically emitted `timeoflife://auth/verify?code=<6-digit>`; both forms
/// are accepted so links already sitting in users' inboxes keep working after
/// the contract was aligned to the shorter form.
enum DeepLink {
    static let scheme = "timeoflife"

    enum Host: String {
        case verify
        case auth
    }

    /// True for both `timeoflife://verify?code=…` and
    /// `timeoflife://auth/verify?code=…`. Guards strictly against over-matching:
    /// `timeoflife://auth?code=…` (no `/verify` path) is rejected.
    static func isVerifyLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host?.lowercased()
        let path = components?.path.lowercased()
        if host == Host.verify.rawValue { return true }
        if host == Host.auth.rawValue, path == "/verify" { return true }
        return false
    }

    /// Returns the route for the URL, or `nil` if it isn't a recognized link.
    /// The verify host returns `.otpEntry(email: "")` — the handler resolves
    /// the email from the cached session state (the URL only carries the code).
    static func parse(url: URL) -> AppRoute? {
        guard isVerifyLink(url) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return nil }
        _ = code // `code(from:)` re-extracts; parse only validates presence.
        return .otpEntry(email: "")
    }

    /// Extracts the 6-digit code from a `timeoflife://verify?code=…` URL.
    static func code(from url: URL) -> String? {
        guard isVerifyLink(url) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "code" }?.value
    }
}
