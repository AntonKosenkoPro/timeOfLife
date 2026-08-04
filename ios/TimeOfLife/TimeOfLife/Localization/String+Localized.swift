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
    case timerOfflineHint = "timer.offlineHint"
    case timerEmptyActivityError = "timer.emptyActivityError"
    case timerSignOut = "timer.signOut"
    case timerSuggestionsHeader = "timer.suggestionsHeader"
    case timerQuickAdd = "timer.quickAdd"
    case timerManageActivities = "timer.manageActivities"

    // Sign out confirmation
    case signOutConfirmationTitle = "signOut.confirmationTitle"
    case signOutConfirmationMessage = "signOut.confirmationMessage"
    case signOutConfirm = "signOut.confirm"
    case signOutCancel = "signOut.cancel"

    // Seeded categories (F6)
    case categorySeedWork = "category.seed.work"
    case categorySeedHobby = "category.seed.hobby"
    case categorySeedSport = "category.seed.sport"
    case categorySeedEducation = "category.seed.education"
    case categorySeedRelax = "category.seed.relax"
    case categorySeedSleep = "category.seed.sleep"
    case categorySeedEntertainment = "category.seed.entertainment"

    // Manage activities
    case manageActivitiesTitle = "manage.activities.title"
    case manageActivitiesEmptyTitle = "manage.activities.emptyTitle"
    case manageActivitiesEmptySubtitle = "manage.activities.emptySubtitle"
    case manageActivitiesCategories = "manage.activities.categories"

    // Delete activity
    case deleteActivityTitle = "delete.activity.title"
    case deleteActivityMessage = "delete.activity.message"
    case deleteActivityEntire = "delete.activity.entire"
    case deleteActivityEntryOnly = "delete.activity.entryOnly"
    case deleteActivityCancel = "delete.activity.cancel"

    // Undo
    case undoActivityDeleted = "undo.activityDeleted"
    case undoEntriesDeleted = "undo.entriesDeleted"
    case undoCategoryDeleted = "undo.categoryDeleted"
    case undoButton = "undo.button"

    // Manage categories
    case manageCategoriesTitle = "manage.categories.title"
    case manageCategoriesEmptyTitle = "manage.categories.emptyTitle"
    case manageCategoriesEmptySubtitle = "manage.categories.emptySubtitle"

    // Category delete confirmation
    case deleteCategoryTitle = "delete.category.title"
    case deleteCategoryMessage = "delete.category.message"
    case deleteCategoryConfirm = "delete.category.confirm"
    case deleteCategoryCancel = "delete.category.cancel"

    // Activity editor
    case activityEditorCreateTitle = "activityEditor.createTitle"
    case activityEditorEditTitle = "activityEditor.editTitle"
    case activityEditorNameLabel = "activityEditor.nameLabel"
    case activityEditorNamePlaceholder = "activityEditor.namePlaceholder"
    case activityEditorNotesLabel = "activityEditor.notesLabel"
    case activityEditorNotesPlaceholder = "activityEditor.notesPlaceholder"
    case activityEditorNotesCounter = "activityEditor.notesCounter"
    case activityEditorTagsLabel = "activityEditor.tagsLabel"
    case activityEditorNoTags = "activityEditor.noTags"
    case activityEditorAddCategory = "activityEditor.addCategory"
    case activityEditorSave = "activityEditor.save"
    case activityEditorCancel = "activityEditor.cancel"

    // Category editor
    case categoryEditorCreateTitle = "categoryEditor.createTitle"
    case categoryEditorEditTitle = "categoryEditor.editTitle"
    case categoryEditorNameLabel = "categoryEditor.nameLabel"
    case categoryEditorNamePlaceholder = "categoryEditor.namePlaceholder"
    case categoryEditorIconLabel = "categoryEditor.iconLabel"
    case categoryEditorSave = "categoryEditor.save"
    case categoryEditorCancel = "categoryEditor.cancel"

    // Validation
    case validationNameEmpty = "validation.nameEmpty"
    case validationNameTooLong = "validation.nameTooLong"
    case validationNotesTooLong = "validation.notesTooLong"

    // Catalog errors
    case errorConflict = "error.conflict"
    case errorActivityExists = "error.activityExists"
    case errorCategoryExists = "error.categoryExists"

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
