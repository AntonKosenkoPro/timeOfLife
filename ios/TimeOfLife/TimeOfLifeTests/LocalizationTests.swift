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
            "email_taken", "weak_password", "invalid_body", "rate_limited",
            "verify_token_invalid", "verify_token_expired", "verify_token_used",
            "invalid_credentials", "email_not_verified",
            "invalid_refresh", "token_reuse", "token_expired",
            "reset_token_invalid", "reset_token_expired", "reset_token_used",
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

    /// All L10n cases, enumerated at runtime via the enum.
    private var l10nCases: [L10n] {
        // L10n has no CaseIterable conformance by default; add it lazily.
        L10n.allCases
    }
}

extension L10n: CaseIterable {
    public static var allCases: [L10n] {
        [
            .appName, .authWelcome, .authSubtitle,
            .signinTitle, .signinEmail, .signinPassword, .signinSubmit,
            .signinForgotPassword, .signinNoAccount, .signinSignUp, .signinSuccess,
            .signupTitle, .signupEmail, .signupPassword, .signupSubmit,
            .signupHaveAccount, .signupSignin, .signupSuccess,
            .forgotTitle, .forgotEmail, .forgotSubmit, .forgotSuccess, .forgotBack,
            .resetTitle, .resetPassword, .resetSubmit, .resetSuccess,
            .verifyTitle, .verifyToken, .verifySubmit, .verifySuccess, .verifyResend, .verifyResent,
            .signedInTitle, .signedInEmail, .signedInLogout, .signedInPlaceholder,
            .offlineBanner,
            .appleSignInTitle, .appleSignInComingSoon,
        ]
    }
}