import Testing
import Foundation
@testable import TimeOfLife

@Suite("Localization")
struct LocalizationTests {

    /// All L10n cases enumerated at runtime.
    private var l10nCases: [L10n] {
        L10n.allCases
    }

    /// Every shipped locale, derived from the app bundle so a newly added
    /// `.lproj` is covered automatically. Pinned by `shippedLocales` below
    /// so a dropped locale fails loudly instead of passing vacuously.
    private static let expectedLocales = ["en", "es-419", "pt-BR", "ru", "zh-Hans"]

    private static var allLocales: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted()
    }

    @Test("shipped locales match the expected set")
    func shippedLocales() {
        #expect(Self.allLocales == Self.expectedLocales, "Shipped locales changed")
    }

    private func bundle(for locale: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: locale, ofType: "lproj"),
                                "Missing \(locale).lproj in main bundle")
        return try #require(Bundle(path: path))
    }

    // MARK: - Key resolution

    @Test("all L10n keys resolve to non-empty strings in every locale")
    func allKeysResolve() throws {
        for locale in Self.allLocales {
            let bundle = try bundle(for: locale)
            for caseValue in l10nCases {
                let value = NSLocalizedString(caseValue.rawValue, bundle: bundle, comment: "")
                #expect(value != caseValue.rawValue,
                        "Unresolved key \(caseValue.rawValue) in \(locale)")
                #expect(!value.isEmpty,
                        "Empty value for key \(caseValue.rawValue) in \(locale)")
            }
        }
    }

    @Test("every catalog icon has a localized accessibility name")
    func catalogIconNamesResolve() throws {
        for locale in Self.allLocales {
            let bundle = try bundle(for: locale)
            for icon in CatalogIcon.allCases {
                let value = L10n.catalogIconName(icon, in: bundle)
                #expect(value != icon.rawValue, "Missing icon name for \(icon.rawValue) in \(locale)")
                #expect(!value.isEmpty)
            }
        }
    }

    /// The Live Activity copy is read from the extension's own bundle, so the
    /// appex must ship the same locales as the app.
    @Test("LifioLiveActivities appex ships every locale")
    func appexShipsAllLocales() throws {
        let appexPath = URL(fileURLWithPath: try #require(Bundle.main.builtInPlugInsPath), isDirectory: true)
            .appendingPathComponent("LifioLiveActivities.appex", isDirectory: true).path
        let appex = try #require(Bundle(path: appexPath), "Missing appex at \(appexPath)")
        let shipped = Set(appex.localizations.filter { $0 != "Base" })
        #expect(shipped == Set(Self.expectedLocales), "Appex locales changed: \(shipped.sorted())")
    }

    /// Format specifiers must match `en` in every locale: a dropped or
    /// duplicated `%@`/`%d` only shows up as garbage text at runtime.
    @Test("format specifiers match en in every locale")
    func formatSpecifiersMatchEN() throws {
        let keys = l10nCases.map(\.rawValue)
            + CatalogIcon.allCases.map { "catalogIcon.\($0.rawValue)" }
        let enBundle = try bundle(for: "en")
        for locale in Self.allLocales where locale != "en" {
            let bundle = try bundle(for: locale)
            for key in keys {
                let enValue = NSLocalizedString(key, bundle: enBundle, comment: "")
                let value = NSLocalizedString(key, bundle: bundle, comment: "")
                #expect(
                    try Self.formatSpecifiers(in: value) == Self.formatSpecifiers(in: enValue),
                    "Specifier drift for key \(key) in \(locale)"
                )
            }
        }
    }

    private static func formatSpecifiers(in text: String) throws -> [String] {
        // `%@`, `%d`, `%s`, positional `%1$@` — normalized so a legitimate
        // positional translation compares equal to plain en markers (order
        // still matters: translators must preserve en order). `%ds` first
        // so the countdown suffix isn't mistaken for a second specifier;
        // the trailing "s" is translator-owned literal text, not a marker.
        let pattern = "%ds|%(?:\\d+\\$)?[@dfsu]"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return try regex.matches(in: text, range: range).map { match -> String in
            guard let range = Range(match.range, in: text) else {
                throw CocoaError(.coderInvalidValue)
            }
            var specifier = String(text[range])
            if specifier == "%ds" {
                return "%d"
            }
            if let dollar = specifier.firstIndex(of: "$") {
                specifier = "%" + specifier[specifier.index(after: dollar)...]
            }
            return specifier
        }
    }

    // MARK: - Notes placeholders

    /// Collapsed presenters keep "Optional notes" while the expanded editor
    /// page uses its own "Dear diary..." prompt (change-expanded-notes-placeholder).
    @Test("collapsed and expanded notes placeholders are exact and distinct")
    func notesPlaceholders() throws {
        let en = try bundle(for: "en")
        let ru = try bundle(for: "ru")

        #expect(NSLocalizedString("entry.notesPlaceholder", bundle: en, comment: "") == "Optional notes")
        #expect(NSLocalizedString("entry.notesPlaceholder", bundle: ru, comment: "") == "Необязательные заметки")
        #expect(NSLocalizedString("notes.editorPlaceholder", bundle: en, comment: "") == "Dear diary...")
        #expect(NSLocalizedString("notes.editorPlaceholder", bundle: ru, comment: "") == "Дорогой дневник...")
    }

    // MARK: - Error codes

    @Test("known error codes resolve via ErrorLocalization without falling back to unknown")
    func errorCodesResolve() throws {
        let codes = [
            "invalid_body", "internal_error", "rate_limited",
            "invalid_otp", "otp_expired", "otp_attempts_exceeded",
            "invalid_refresh", "token_reuse", "refresh_expired",
            "refresh_attempt_completed", "refresh_attempt_conflict",
        ]
        let unknownText = NSLocalizedString("error.unknown", comment: "")

        for code in codes {
            let msg = L10n.text(in: .default, code: code)
            #expect(!msg.isEmpty)
            #expect(msg != unknownText,
                    "Code \(code) fell back to error.unknown")
        }
    }

    @Test("offline error maps to offline error text")
    func offlineMapping() {
        let msg = ErrorLocalization.message(for: .offline)
        #expect(!msg.isEmpty)
    }

    @Test("refresh recovery codes resolve in every locale bundle")
    func refreshRecoveryCodesResolve() throws {
        try resolveKeys([
            "error.refresh_attempt_completed",
            "error.refresh_attempt_conflict",
        ])
    }

    // MARK: - Validation fragment keys

    @Test("validation fragment keys resolve in every locale bundle")
    func validationFragmentKeysResolve() throws {
        try resolveKeys([
            "common.and",
            "validation.emailEmpty",
            "validation.email.prefix",
            "validation.email.rule.invalid",
            "validation.email.rule.tooLong",
            "validation.otpEmpty",
            "validation.otp.prefix",
            "validation.otp.rule.invalid",
        ])
    }

    private func resolveKeys(_ keys: [String]) throws {
        for code in Self.allLocales {
            let bundle = try bundle(for: code)
            for key in keys {
                let value = NSLocalizedString(key, bundle: bundle, comment: "")
                #expect(value != key, "Unresolved key \(key) in \(code)")
                #expect(!value.isEmpty, "Empty value for key \(key) in \(code)")
            }
        }
    }

    // MARK: - L10n enum allCases matches strings files

    /// Sorted-keys snapshot of the `L10n` contract: adding, removing, or
    /// renaming a key fails here with an exact diff (the former
    /// `allCasesCount == 148` only caught count drift and went stale on
    /// every copy change). Update the snapshot deliberately when copy
    /// changes land; the en+ru resolution tests above pin the values.
    @Test("L10n sorted-keys snapshot matches the recorded contract")
    func sortedKeysSnapshot() {
        #expect(l10nCases.map(\.rawValue).sorted() == Self.expectedKeys)
    }

    private static let expectedKeys: [String] = [
        "account.cleanupRetryConfirm",
        "account.cleanupRetryMessage",
        "account.cleanupRetryTitle",
        "account.deleteConfirm",
        "account.deleteError",
        "account.deleteFailedTitle",
        "account.deleteLocalData",
        "account.deleteMessage",
        "account.deleteOffline",
        "account.deleteOfflineTitle",
        "account.deleteTitle",
        "account.deletingProgress",
        "account.identityFooter",
        "account.identitySection",
        "account.pendingAppleUnlink",
        "account.permanentFooter",
        "account.permanentSection",
        "account.signOutConfirmMessage",
        "account.signOutConfirmTitle",
        "account.stillExists",
        "account.stillExistsTitle",
        "account.thisDeviceFooter",
        "account.thisDeviceSection",
        "account.title",
        "activity.savedWithDuration",
        "app.name",
        "appleSignIn.error",
        "appleSignIn.title",
        "authGate.title",
        "category.nameRequired",
        "category.nameTooLong",
        "category.seed.education",
        "category.seed.entertainment",
        "category.seed.hobby",
        "category.seed.relax",
        "category.seed.sleep",
        "category.seed.sport",
        "category.seed.work",
        "categoryEditor.cancel",
        "categoryEditor.confirmSaveLabel",
        "categoryEditor.createTitle",
        "categoryEditor.delete",
        "categoryEditor.dismissLabel",
        "categoryEditor.editTitle",
        "categoryEditor.iconLabel",
        "categoryEditor.iconUnavailable",
        "categoryEditor.nameLabel",
        "categoryEditor.namePlaceholder",
        "categoryEditor.save",
        "common.and",
        "common.ok",
        "delete.category.confirm",
        "delete.category.message",
        "delete.category.title",
        "emailEntry.email",
        "emailEntry.submit",
        "emailEntry.subtitle",
        "emailEntry.title",
        "entry.categoriesLabel",
        "entry.confirmAddLabel",
        "entry.confirmSaveLabel",
        "entry.delete",
        "entry.deleteConfirm",
        "entry.deleteMessage",
        "entry.deleteTitle",
        "entry.dismissLabel",
        "entry.duration",
        "entry.editTitle",
        "entry.invalidInterval",
        "entry.lockedNote",
        "entry.lockedTitle",
        "entry.nameLabel",
        "entry.namePlaceholder",
        "entry.notesLabel",
        "entry.notesPlaceholder",
        "entry.staleError",
        "error.categoryExists",
        "error.conflict",
        "error.localPersistence",
        "history.day.today",
        "history.day.yesterday",
        "history.emptySubtitle",
        "history.emptyTitle",
        "history.hasNotes",
        "history.inProgress",
        "history.logTime",
        "history.pull.offline",
        "history.syncError.title",
        "history.tracked",
        "insights.empty.today",
        "insights.empty.week",
        "insights.emptySubtitle",
        "insights.emptyTitle",
        "insights.footnote",
        "insights.lens.activity",
        "insights.lens.category",
        "insights.noCategory",
        "insights.period.all",
        "insights.period.today",
        "insights.period.week",
        "logTime.cancel",
        "logTime.ends",
        "logTime.starts",
        "logTime.title",
        "manage.categories.add",
        "manage.categories.editHint",
        "manage.categories.emptySubtitle",
        "manage.categories.emptyTitle",
        "manage.categories.loading",
        "manage.categories.rowA11y",
        "manage.categories.title",
        "name.clear",
        "name.pickerNoMatchHint",
        "name.pickerTitle",
        "notes.editorCounter",
        "notes.editorPlaceholder",
        "notes.editorSubtitle",
        "otp.codeHint",
        "otp.codeLabel",
        "otp.resend",
        "otp.resendCountdown",
        "otp.sentTo",
        "otp.title",
        "profile.account",
        "profile.categories",
        "profile.eraseCancel",
        "profile.eraseConfirm",
        "profile.eraseLocalData",
        "profile.eraseLocalDataConfirmMessage",
        "profile.eraseLocalDataConfirmTitle",
        "profile.lastSynced.ago",
        "profile.lastSynced.justNow",
        "profile.onDevice",
        "profile.onDeviceFooter",
        "profile.signOut",
        "profile.syncError",
        "profile.syncNow",
        "profile.syncedSuccessfully",
        "profile.syncing",
        "profile.title",
        "profile.versionDebugSuffix",
        "provenance.name.calendar",
        "provenance.name.control",
        "provenance.name.garmin",
        "provenance.name.healthkit",
        "provenance.name.screentime",
        "provenance.name.siri",
        "provenance.name.widget",
        "provenance.via.calendar",
        "provenance.via.control",
        "provenance.via.garmin",
        "provenance.via.healthkit",
        "provenance.via.screentime",
        "provenance.via.siri",
        "provenance.via.widget",
        "signOut.cancel",
        "tab.history",
        "tab.insights",
        "tab.track",
        "timer.chooserRecent",
        "timer.compactReturnHint",
        "timer.compactRunning",
        "timer.compactStop",
        "timer.idlePrompt",
        "timer.namePlaceholder",
        "timer.ready",
        "timer.recentsEmptyHint",
        "timer.running",
        "timer.saved",
        "timer.saving",
        "timer.selectActivity",
        "timer.start",
        "timer.startConfirm",
        "timer.startEditorTitle",
        "timer.startForward15",
        "timer.startForward30",
        "timer.startToday",
        "timer.startYesterday",
        "timer.startedAt",
        "timer.startedYesterday",
        "timer.stop",
        "timer.stopHint",
        "undo.notSelected",
        "undo.selected",
        "undo.selectedPosition",
        "validation.email.prefix",
        "validation.email.rule.invalid",
        "validation.email.rule.tooLong",
        "validation.emailEmpty",
        "validation.otp.prefix",
        "validation.otp.rule.invalid",
        "validation.otpEmpty",
        "welcome.continueWithEmail",
        "welcome.tagline",
    ]
}
