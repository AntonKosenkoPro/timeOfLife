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

    // Timer (plain-text capture, remove-activities-layer)
    case timerStart = "timer.start"
    case timerStop = "timer.stop"
    case timerStopHint = "timer.stopHint"
    case timerSignOut = "timer.signOut"
    case timerIdlePrompt = "timer.idlePrompt"
    case timerNamePlaceholder = "timer.namePlaceholder"
    case timerSaved = "timer.saved"
    case timerSaving = "timer.saving"
    case timerRunning = "timer.running"
    case timerReady = "timer.ready"
    case timerChooserRecent = "timer.chooserRecent"
    case timerRecentsEmptyHint = "timer.recentsEmptyHint"
    case timerSelectActivity = "timer.selectActivity"
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
    case syncCancel = "sync.cancel"
    case profileSyncing = "profile.syncing"
    case profileLastSynced = "profile.lastSynced"
    case profileSyncError = "profile.syncError"
    case profileLibrary = "profile.library"
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

    // Insights breakdown (insights-breakdown)
    case insightsPeriodToday = "insights.period.today"
    case insightsPeriodWeek = "insights.period.week"
    case insightsPeriodAll = "insights.period.all"
    case insightsLensCategory = "insights.lens.category"
    case insightsLensActivity = "insights.lens.activity"
    case insightsNoCategory = "insights.noCategory"
    case insightsFootnote = "insights.footnote"
    case insightsEmptyToday = "insights.empty.today"
    case insightsEmptyWeek = "insights.empty.week"

    // Entry provenance (entry-provenance spec)
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

    // Log Time sheet (manual-entry spec)
    case logTimeTitle = "logTime.title"
    case logTimeAdd = "logTime.add"
    case logTimeCancel = "logTime.cancel"
    case logTimeStarts = "logTime.starts"
    case logTimeEnds = "logTime.ends"

    // Unified entry form (entry-editor spec: CREATE + EDIT + LOCKED modes)
    case entryEditTitle = "entry.editTitle"
    case entryLockedTitle = "entry.lockedTitle"
    case entrySave = "entry.save"
    case entryDelete = "entry.delete"
    case entryDeleteTitle = "entry.deleteTitle"
    case entryDeleteMessage = "entry.deleteMessage"
    case entryDeleteConfirm = "entry.deleteConfirm"
    case entryStaleError = "entry.staleError"
    case entryLockedNote = "entry.lockedNote"
    case entryNameLabel = "entry.nameLabel"
    case entryNamePlaceholder = "entry.namePlaceholder"
    case entryCategoriesLabel = "entry.categoriesLabel"
    case entryNotesLabel = "entry.notesLabel"
    case entryNotesPlaceholder = "entry.notesPlaceholder"

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

    // Undo (chip selection accessibility; the category UndoToast is gone —
    // deletions undo through the system Undo confirmation instead)
    case undoSelected = "undo.selected"
    case undoNotSelected = "undo.notSelected"

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
    case categoryEditorDelete = "categoryEditor.delete"
    case categoryNameRequired = "category.nameRequired"
    case categoryNameTooLong = "category.nameTooLong"

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

    /// The seven localized starter category names in creation order (the
    /// single source for seeding; used by `RootView` and `TrackViewModel`).
    static var starterCategoryNames: [String] {
        [
            L10n.categorySeedWork.text,
            L10n.categorySeedHobby.text,
            L10n.categorySeedSport.text,
            L10n.categorySeedEducation.text,
            L10n.categorySeedRelax.text,
            L10n.categorySeedSleep.text,
            L10n.categorySeedEntertainment.text,
        ]
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
