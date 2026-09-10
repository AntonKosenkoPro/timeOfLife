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
    case timerStart = "timer.start"
    case timerStop = "timer.stop"
    case timerStopHint = "timer.stopHint"
    case timerEmptyActivityError = "timer.emptyActivityError"
    case timerSignOut = "timer.signOut"
    case timerChooseActivity = "timer.chooseActivity"
    case timerChooseActivityPrompt = "timer.chooseActivityPrompt"
    case timerSaved = "timer.saved"
    case timerSaving = "timer.saving"
    case timerRunning = "timer.running"
    case timerReady = "timer.ready"
    case timerChooserRecent = "timer.chooserRecent"
    case timerRecentsEmptyHint = "timer.recentsEmptyHint"
    case timerSelectActivity = "timer.selectActivity"
    case timerSearchPrompt = "timer.searchPrompt"
    case timerSearchEmptyCatalogTitle = "timer.searchEmptyCatalogTitle"
    case timerSearchEmptyCatalogSubtitle = "timer.searchEmptyCatalogSubtitle"
    case timerSearchNoResults = "timer.searchNoResults"
    case timerSearchCreate = "timer.searchCreate"
    case timerSearchRestorePrompt = "timer.searchRestorePrompt"
    case timerSearchRestore = "timer.searchRestore"
    case timerSearchValidationEmpty = "timer.searchValidationEmpty"
    case timerSearchValidationTooLong = "timer.searchValidationTooLong"
    case timerStalePreparationError = "timer.stalePreparationError"
    case activityEditorCreateTitle = "activityEditor.createTitle"
    case activityEditorEditTitle = "activityEditor.editTitle"
    case activityEditorNameLabel = "activityEditor.nameLabel"
    case activityEditorNamePlaceholder = "activityEditor.namePlaceholder"
    case activityEditorNotesLabel = "activityEditor.notesLabel"
    case activityEditorNotesPlaceholder = "activityEditor.notesPlaceholder"
    case activityEditorNotesCounter = "activityEditor.notesCounter"
    case activityEditorNotesTooLong = "activityEditor.notesTooLong"
    case activityEditorTagsLabel = "activityEditor.tagsLabel"
    case activityEditorNoTags = "activityEditor.noTags"
    case activityEditorAddCategory = "activityEditor.addCategory"
    case activityEditorSave = "activityEditor.save"
    case activityEditorCancel = "activityEditor.cancel"
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

    // History day groups (history-entry-list spec)
    case historyDayToday = "history.day.today"
    case historyDayYesterday = "history.day.yesterday"
    case historyInProgress = "history.inProgress"
    case historyTracked = "history.tracked"

    // Entry provenance (entry-provenance spec, activity-detail-sheet)
    case provenanceViaWidget = "provenance.via.widget"
    case provenanceViaSiri = "provenance.via.siri"
    case provenanceViaControl = "provenance.via.control"
    case provenanceViaScreentime = "provenance.via.screentime"
    case provenanceViaGarmin = "provenance.via.garmin"
    case provenanceViaCalendar = "provenance.via.calendar"
    case provenanceViaHealthkit = "provenance.via.healthkit"
    case provenanceNameWidget = "provenance.name.widget"
    case provenanceNameSiri = "provenance.name.siri"
    case provenanceNameControl = "provenance.name.control"
    case provenanceNameScreentime = "provenance.name.screentime"
    case provenanceNameGarmin = "provenance.name.garmin"
    case provenanceNameCalendar = "provenance.name.calendar"
    case provenanceNameHealthkit = "provenance.name.healthkit"

    // Activity detail sheet (activity-detail-sheet)
    case activityDetailEditActivity = "activityDetail.editActivity"
    case activityDetailLogTime = "activityDetail.logTime"
    case activityDetailCategories = "activityDetail.categories"
    case activityDetailNoCategories = "activityDetail.noCategories"
    case activityDetailEntries = "activityDetail.entries"
    case activityDetailTotal = "activityDetail.total"

    // Log Time sheet (manual-entry spec)
    case logTimeTitle = "logTime.title"
    case logTimeAdd = "logTime.add"
    case logTimeCancel = "logTime.cancel"
    case logTimeActivity = "logTime.activity"
    case logTimeChooseActivity = "logTime.chooseActivity"
    case logTimeStarts = "logTime.starts"
    case logTimeEnds = "logTime.ends"
    case logTimeActivityMissing = "logTime.activityMissing"

    // Unified entry form (entry-editor spec: EDIT + LOCKED modes)
    case entryEditTitle = "entry.editTitle"
    case entryLockedTitle = "entry.lockedTitle"
    case entrySave = "entry.save"
    case entryDelete = "entry.delete"
    case entryDeleteTitle = "entry.deleteTitle"
    case entryDeleteMessage = "entry.deleteMessage"
    case entryDeleteConfirm = "entry.deleteConfirm"
    case entryStaleError = "entry.staleError"
    case entryLockedNote = "entry.lockedNote"

    // History manual entry (add-manual-entry)
    case historyLogTime = "history.logTime"

    // Starter categories (category-management spec, seed requirement)
    case categorySeedWork = "category.seed.work"
    case categorySeedHobby = "category.seed.hobby"
    case categorySeedSport = "category.seed.sport"
    case categorySeedEducation = "category.seed.education"
    case categorySeedRelax = "category.seed.relax"
    case categorySeedSleep = "category.seed.sleep"
    case categorySeedEntertainment = "category.seed.entertainment"

    // Undo (category-management D7)
    case undoButton = "undo.button"
    case undoDismiss = "undo.dismiss"
    case undoCategoryDeleted = "undo.categoryDeleted"
    case undoSelected = "undo.selected"
    case undoNotSelected = "undo.notSelected"
    case undoSecondsRemaining = "undo.secondsRemaining"

    // Manage categories (category-management D4)
    case manageCategoriesTitle = "manage.categories.title"
    case manageCategoriesAdd = "manage.categories.add"
    case manageCategoriesEmptyTitle = "manage.categories.emptyTitle"
    case manageCategoriesEmptySubtitle = "manage.categories.emptySubtitle"
    case manageCategoriesRowA11y = "manage.categories.rowA11y"
    case manageCategoriesEditHint = "manage.categories.editHint"
    case manageCategoriesLoading = "manage.categories.loading"
    case deleteCategoryTitle = "delete.category.title"
    case deleteCategoryMessage = "delete.category.message"
    case deleteCategoryConfirm = "delete.category.confirm"
    case deleteCategoryCancel = "delete.category.cancel"
    case errorCategoryExists = "error.categoryExists"
    case errorConflict = "error.conflict"
    case errorLocalPersistence = "error.localPersistence"

    // Category editor (category-management D4)
    case categoryEditorCreateTitle = "categoryEditor.createTitle"
    case categoryEditorEditTitle = "categoryEditor.editTitle"
    case categoryEditorNameLabel = "categoryEditor.nameLabel"
    case categoryEditorNamePlaceholder = "categoryEditor.namePlaceholder"
    case categoryEditorIconLabel = "categoryEditor.iconLabel"
    case categoryEditorIconUnavailable = "categoryEditor.iconUnavailable"
    case categoryEditorSave = "categoryEditor.save"
    case categoryEditorCancel = "categoryEditor.cancel"
    case categoryNameRequired = "category.nameRequired"
    case categoryNameTooLong = "category.nameTooLong"
    case activityEditorInvalidAssociation = "activityEditor.invalidAssociation"

    // Sign out confirmation
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
    /// Localized VoiceOver names for the closed CatalogIcon set. The dynamic
    /// key keeps the enum focused on user-facing copy while still requiring
    /// every supported symbol to have EN/RU accessibility text.
    static func catalogIconName(_ icon: CatalogIcon, in bundle: Bundle = .main) -> String {
        let key = "catalogIcon.\(icon.rawValue)"
        let value = NSLocalizedString(key, bundle: bundle, comment: "")
        return value == key ? icon.rawValue : value
    }

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
