import Foundation

/// Compile-time-safe localization keys. Each case maps to a key in
/// `Localizable.strings` (en + ru). The single test in `LocalizationTests`
/// asserts every case resolves in both bundles.
enum L10n: String, CaseIterable {
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
    case otpResend = "otp.resend"
    case otpResendCountdown = "otp.resendCountdown"

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
    case timerStopHint = "timer.stopHint"
    case timerOfflineHint = "timer.offlineHint"
    case timerEmptyActivityError = "timer.emptyActivityError"
    case timerSignOut = "timer.signOut"
    case timerChooseActivity = "timer.chooseActivity"
    case timerChooseActivityPrompt = "timer.chooseActivityPrompt"
    case timerSaved = "timer.saved"
    case timerSaving = "timer.saving"
    case timerRunning = "timer.running"
    case timerReady = "timer.ready"
    case timerSavedDuration = "timer.savedDuration"
    case timerChooserTitle = "timer.chooserTitle"
    case timerChooserSearchPrompt = "timer.chooserSearchPrompt"
    case timerChooserCreate = "timer.chooserCreate"
    case timerChooserRecent = "timer.chooserRecent"
    case timerChooserActivities = "timer.chooserActivities"
    case timerChooserEmptyTitle = "timer.chooserEmptyTitle"
    case timerChooserEmptySubtitle = "timer.chooserEmptySubtitle"
    case timerChooserCreateFirst = "timer.chooserCreateFirst"
    case timerManageActivities = "timer.manageActivities"
    case timerCompactStop = "timer.compactStop"
    case timerCompactReturnHint = "timer.compactReturnHint"
    case timerCompactRunning = "timer.compactRunning"

    // App shell
    case tabTrack = "tab.track"
    case tabHistory = "tab.history"
    case tabInsights = "tab.insights"
    case profileTitle = "profile.title"
    case profileDone = "profile.done"
    case profileAccount = "profile.account"
    case profileEnableSync = "profile.enableSync"
    case profileEnableSyncSubtitle = "profile.enableSyncSubtitle"
    case profileSyncNow = "profile.syncNow"
    case profileSyncing = "profile.syncing"
    case profileLastSynced = "profile.lastSynced"
    case profileSyncError = "profile.syncError"
    case profileLibrary = "profile.library"
    case profileActivities = "profile.activities"
    case profileCategories = "profile.categories"
    case profileConnections = "profile.connections"
    case profileIntegrations = "profile.integrations"
    case profileExport = "profile.export"
    case profileApp = "profile.app"
    case profileAppearance = "profile.appearance"
    case profileDataAndPrivacy = "profile.dataAndPrivacy"
    case profileEraseLocalData = "profile.eraseLocalData"
    case profileEraseLocalDataConfirmTitle = "profile.eraseLocalDataConfirmTitle"
    case profileEraseLocalDataConfirmMessage = "profile.eraseLocalDataConfirmMessage"
    case profileEraseConfirm = "profile.eraseConfirm"
    case profileEraseCancel = "profile.eraseCancel"

    // Destination empty states
    case historyEmptyTitle = "history.emptyTitle"
    case historyEmptySubtitle = "history.emptySubtitle"
    case insightsEmptyTitle = "insights.emptyTitle"
    case insightsEmptySubtitle = "insights.emptySubtitle"

    // Sign out confirmation
    case signOutConfirmationTitle = "signOut.confirmationTitle"
    case signOutConfirmationMessage = "signOut.confirmationMessage"
    case signOutConfirm = "signOut.confirm"
    case signOutCancel = "signOut.cancel"

    /// Resolves the key via `NSLocalizedString` against `Localizable.strings`.
    var text: String {
        NSLocalizedString(rawValue, comment: "")
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
