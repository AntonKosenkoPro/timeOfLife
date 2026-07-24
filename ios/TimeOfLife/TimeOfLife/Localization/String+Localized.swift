import Foundation

/// Compile-time-safe localization keys. Each case maps to a key in
/// `Localizable.strings` (en + ru). The single test in `LocalizationTests`
/// asserts every case resolves in both bundles.
enum L10n: String {
    // App
    case appName = "app.name"

    // Welcome
    case welcomeTagline = "welcome.tagline"
    case welcomeContinueWithEmail = "welcome.continueWithEmail"

    // Email entry (passwordless)
    case emailEntryTitle = "emailEntry.title"
    case emailEntryEmail = "emailEntry.email"
    case emailEntrySubtitle = "emailEntry.subtitle"
    case emailEntrySubmit = "emailEntry.submit"

    // OTP entry
    case otpTitle = "otp.title"
    case otpSentTo = "otp.sentTo"
    case otpCode = "otp.code"
    case otpSubmit = "otp.submit"
    case otpResend = "otp.resend"
    case otpResendCountdown = "otp.resendCountdown"
    case otpResent = "otp.resent"

    // Offline
    case offlineBanner = "offline.banner"

    // Apple
    case appleSignInTitle = "appleSignIn.title"
    case appleSignInError = "appleSignIn.error"

    // Timer
    case timerTitle = "timer.title"
    case timerActivityPlaceholder = "timer.activityPlaceholder"
    case timerStart = "timer.start"
    case timerStop = "timer.stop"
    case timerOfflineHint = "timer.offlineHint"
    case timerEmptyActivityError = "timer.emptyActivityError"
    case timerSignOut = "timer.signOut"

    // Sign out confirmation
    case signOutConfirmationTitle = "signOut.confirmationTitle"
    case signOutConfirmationMessage = "signOut.confirmationMessage"
    case signOutConfirm = "signOut.confirm"
    case signOutCancel = "signOut.cancel"

    /// Resolves the key via `NSLocalizedString` against `Localizable.strings`.
    var text: String {
        NSLocalizedString(rawValue, comment: "")
    }

    /// Resolves the key, falling back to `key` when missing. Used by the
    /// localization test to detect missing entries per-bundle.
    func text(in bundle: Bundle, localeIdentifier: String) -> String {
        let langCode = localeIdentifier.lowercased()
        let path = bundle.path(forResource: langCode, ofType: "lproj")
            ?? bundle.path(forResource: String(langCode.prefix(2)), ofType: "lproj")
            ?? bundle.path(forResource: "Base", ofType: "lproj")
            ?? bundle.bundlePath
        let locBundle = Bundle(path: path) ?? bundle
        return NSLocalizedString(rawValue, tableName: "Localizable", bundle: locBundle, comment: "")
    }
}

extension String {
    /// Convenience for ad-hoc keys not enumerated in `L10n` (e.g. server error
    /// codes). Falls back to the key itself if missing.
    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

/// Maps an `APIError` to a localized user-facing string via its error `code`.
enum ErrorLocalization {
    static func message(for error: APIError) -> String {
        switch error {
        case .offline: return L10n.text(in: .default, code: "error.offline")
        case let .server(code, _, _): return L10n.text(in: .default, code: "error.\(code)")
        case .unauthorized: return L10n.text(in: .default, code: "error.unauthorized")
        default: return L10n.text(in: .default, code: "error.unknown")
        }
    }
}

extension L10n {
    /// Looks up a server-error-style key (`error.<code>`) with fallback to
    /// `error.unknown`. Shared by view models and tests.
    static func text(in bundle: BundleProvider, code: String) -> String {
        let key = "error.\(code)"
        let value = NSLocalizedString(key, bundle: bundle.bundle, comment: "")
        return value == key ? NSLocalizedString("error.unknown", bundle: bundle.bundle, comment: "") : value
    }
}

/// Indirection over `Bundle` so tests can swap bundles for the localization
/// parity check.
struct BundleProvider {
    let bundle: Bundle
    static var `default`: BundleProvider { BundleProvider(bundle: .main) }
}
