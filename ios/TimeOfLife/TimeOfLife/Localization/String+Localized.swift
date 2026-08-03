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
    case timerManageActivities = "timer.manageActivities"

    // Sign out confirmation
    case signOutConfirmationTitle = "signOut.confirmationTitle"
    case signOutConfirmationMessage = "signOut.confirmationMessage"
    case signOutConfirm = "signOut.confirm"
    case signOutCancel = "signOut.cancel"

    // Catalog (Epic 1)
    case tagsEmptyHint = "tags.emptyHint"
    case undoButton = "undo.button"
    case toastDismiss = "toast.dismiss"
    case accessibilityCategory = "accessibility.category"
    case accessibilityIcon = "accessibility.icon"
    case accessibilitySuggestion = "accessibility.suggestion"
    case accessibilitySuggestionHint = "accessibility.suggestionHint"
    case accessibilitySelected = "accessibility.selected"
    case accessibilityTagsCount = "accessibility.tagsCount"
    case deleteActivityTitle = "delete.activity.title"
    case deleteButton = "delete.button"
    case deleteActivityMessage = "delete.activity.message"
    case deleteActivityEntire = "delete.activity.entire"
    case deleteActivityEntryOnly = "delete.activity.entryOnly"
    case deleteActivityCancel = "delete.activity.cancel"
    case activityLastUsed = "activity.lastUsed"

    // Manage activities
    case manageActivitiesTitle = "manage.activities.title"
    case manageActivitiesEmptyTitle = "manage.activities.emptyTitle"
    case manageActivitiesEmptySubtitle = "manage.activities.emptySubtitle"
    case manageActivitiesCategories = "manage.activities.categories"
    case undoActivityDeleted = "undo.activityDeleted"
    case undoEntryDeleted = "undo.entryDeleted"
    case errorActivityExists = "error.activityExists"
    case errorConflict = "error.conflict"
    case errorUndoFailed = "error.undoFailed"

    // Manage categories
    case manageCategoriesTitle = "manage.categories.title"
    case manageCategoriesEmptyTitle = "manage.categories.emptyTitle"
    case manageCategoriesEmptySubtitle = "manage.categories.emptySubtitle"
    case deleteCategoryTitle = "delete.category.title"
    case deleteCategoryMessage = "delete.category.message"
    case deleteCategoryConfirm = "delete.category.confirm"
    case deleteCategoryCancel = "delete.category.cancel"
    case undoCategoryDeleted = "undo.categoryDeleted"
    case errorCategoryExists = "error.categoryExists"
    case categoryEditorCreateTitle = "categoryEditor.createTitle"
    case categoryEditorEditTitle = "categoryEditor.editTitle"
    case categoryEditorNameLabel = "categoryEditor.nameLabel"
    case categoryEditorNamePlaceholder = "categoryEditor.namePlaceholder"
    case categoryEditorIconLabel = "categoryEditor.iconLabel"
    case categoryEditorSave = "categoryEditor.save"
    case categoryEditorCancel = "categoryEditor.cancel"
    case categorySeedWork = "category.seed.work"
    case categorySeedHobby = "category.seed.hobby"
    case categorySeedSport = "category.seed.sport"
    case categorySeedEducation = "category.seed.education"
    case categorySeedRelax = "category.seed.relax"
    case categorySeedSleep = "category.seed.sleep"
    case categorySeedEntertainment = "category.seed.entertainment"
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
    case activityValidationNameEmpty = "validation.nameEmpty"
    case activityValidationNameTooLong = "validation.nameTooLong"
    case validationNamePrefix = "validation.name.prefix"
    case validationNameRuleTooLong = "validation.name.rule.tooLong"
    case activityValidationNotesTooLong = "validation.notesTooLong"
    case validationCatalogIconInvalid = "validation.catalog.iconInvalid"

    /// Resolves the key via `NSLocalizedString` against `Localizable.strings`.
    var text: String {
        NSLocalizedString(rawValue, comment: "")
    }

    /// Resolves the key with format arguments (e.g. `"%d entries"`).
    func text(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(rawValue, comment: ""), arguments: args)
    }

    /// Plural-aware resolution for a single integer argument. The stringsdict
    /// path was removed because Foundation's strings lookup crashes when a key
    /// has a plist-dict value on the current SDK; instead the plural-suffixed
    /// keys (`<root>.<form>` in `Localizable.strings`) are selected in Swift
    /// via `PluralForm.form(for:)`, then `String(format:)` substitutes `%d`.
    /// For keys without a plural root the same call back to a single template
    /// is preserved (so misc `Int` args still work).
    func text(_ arg: Int) -> String {
        let template = NSLocalizedString(templateKey(for: arg), comment: "")
        return String(format: template, arg)
    }

    /// Returns the `.strings` key to look up for a count-aware `text(Int:)`
    /// call. Keys declared with a `pluralRoot` replace their `<root>` with
    /// `<root>.<form>`; every other key keeps its single form.
    private func templateKey(for count: Int) -> String {
        guard let root = pluralRoot else { return rawValue }
        return "\(root).\(PluralForm.form(for: count).rawValue)"
    }

    /// For plural-rendered keys (`delete.activity.{message,entire}`), the
    /// rawValue identifies the *root* key (e.g. `delete.activity.message`).
    /// Per-form variants are stored as `<root>.<form>` in `Localizable.strings`.
    private var pluralRoot: String? {
        switch self {
        case .deleteActivityMessage: return "delete.activity.message"
        case .deleteActivityEntire: return "delete.activity.entire"
        default: return nil
        }
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

/// Per-language plural-form selector. Replaces the `Localizable.stringsdict`
/// machinery that crashes Foundation on the current SDK (see `L10n.text(_:)`).
/// Only English (`one`/`other`) and Russian (`one`/`few`/`many`) pluantity are
/// supported — both locales the app currently ships (Requirements U4).
enum PluralForm: String {
    case one
    case few
    case many
    case other

    /// Selects the plural form for `count` according to the selected UI
    /// localization. The localization is read from the bundle's preferred
    /// localizations so it stays consistent with whichever `Localizable.strings`
    /// table `NSLocalizedString` will consult.
    static func form(for count: Int) -> PluralForm {
        let lang = Localization.preferredLanguageCode
        switch lang {
        case "ru":
            let mod10 = count % 10
            let mod100 = count % 100
            if mod10 == 1, mod100 != 11 { return .one }
            if mod10 >= 2, mod10 <= 4, !(mod100 >= 12 && mod100 <= 14) { return .few }
            return .many
        default:
            return count == 1 ? .one : .other
        }
    }
}

/// Shared helpers for the localization layer.
enum Localization {
    /// Two-letter ISO code of the UI's preferred localization, falling back to
    /// English when nothing is known. Uses `Bundle.main.preferredLocalizations`
    /// first (matches whatever `NSLocalizedString` will resolve), then
    /// `Locale.current` via iOS-16-guarded API.
    static var preferredLanguageCode: String {
        if let pref = Bundle.main.preferredLocalizations.first {
            return String(pref.prefix(2))
        }
        if #available(iOS 16, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }
}
