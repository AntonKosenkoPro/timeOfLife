import Testing
import Foundation
@testable import TimeOfLife

@Suite("Localization")
struct LocalizationTests {
    /// Every `L10n` case resolves to a non-key-fallback string in both the
    /// en and ru bundles shipped in the app.
    @Test("every L10n key resolves in en + ru bundles")
    func allKeysResolve() throws {
        let main = Bundle.main
        for code in ["en", "ru"] {
            let path = main.path(forResource: code, ofType: "lproj")
            #expect(path != nil, "missing \(code).lproj in main bundle")
            let bundle = Bundle(path: path!)!
            for caseValue in l10nCases {
                let value = NSLocalizedString(caseValue.rawValue, bundle: bundle, comment: "")
                #expect(value != caseValue.rawValue,
                        "unresolved key \(caseValue.rawValue) in \(code)")
                #expect(!value.isEmpty,
                        "empty value for key \(caseValue.rawValue) in \(code)")
            }
        }
    }

    @Test("error codes resolve via ErrorLocalization")
    func errorCodesResolve() throws {
        let codes = [
            "invalid_body", "rate_limited",
            "invalid_otp", "otp_expired", "otp_attempts_exceeded",
            "invalid_refresh", "token_reuse", "token_expired",
        ]
        for code in codes {
            let msg = L10n.text(in: .default, code: code)
            #expect(!msg.isEmpty)
            // Should not fall back to error.unknown text for known codes.
            #expect(msg != NSLocalizedString("error.unknown", comment: ""))
        }
    }

    @Test("offline error maps to offline banner text")
    func offlineMapping() {
        let msg = ErrorLocalization.message(for: .offline)
        #expect(!msg.isEmpty)
    }

    /// Validation fragment keys used to build unified messages (U4) are not
    /// enumerated in `L10n`, so they need their own parity check across en + ru.
    @Test("validation fragment keys resolve in en + ru bundles")
    func validationFragmentKeysResolve() throws {
        let keys = [
            "common.and",
            "validation.emailEmpty",
            "validation.email.prefix",
            "validation.email.rule.invalid",
            "validation.email.rule.tooLong",
            "validation.otpEmpty",
            "validation.otp.prefix",
            "validation.otp.rule.invalid",
        ]
        let main = Bundle.main
        for code in ["en", "ru"] {
            let path = try #require(main.path(forResource: code, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in keys {
                let value = NSLocalizedString(key, bundle: bundle, comment: "")
                #expect(value != key, "unresolved key \(key) in \(code)")
                #expect(!value.isEmpty, "empty value for key \(key) in \(code)")
            }
        }
    }

    /// All L10n cases, enumerated at runtime via the enum.
    private var l10nCases: [L10n] {
        L10n.allCases
    }
}

extension L10n: CaseIterable {
    public static var allCases: [L10n] {
        [
            .appName, .authWelcome, .authSubtitle,
            .emailEntryTitle, .emailEntryEmail, .emailEntrySubmit,
            .otpTitle, .otpSentTo, .otpCode, .otpSubmit, .otpResend, .otpSuccess, .otpResent,
            .signedInTitle, .signedInEmail, .signedInLogout, .signedInPlaceholder,
            .offlineBanner,
            .appleSignInTitle, .appleSignInComingSoon,
        ]
    }
}