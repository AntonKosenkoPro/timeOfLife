import Testing
import Foundation
@testable import TimeOfLife

@Suite("Localization")
struct LocalizationTests {

    /// All L10n cases enumerated at runtime.
    private var l10nCases: [L10n] {
        L10n.allCases
    }

    /// Plural-*root* keys — `delete.activity.message` and `delete.activity.entire`
    /// — have no single form in `Localizable.strings`; only `<root>.<form>`
    /// variants exist (one/few/many/other). The singular root value points to
    /// nothing in either bundle, so it must be excluded from the plain-string
    /// parity loops below. The variants themselves are checked in
    /// `pluralFormKeysExist`, and resolution via `L10n.text(Int)` is exercised
    /// in `pluralKeysResolve`.
    private static let pluralKeys: Set<String> = [
        L10n.deleteActivityMessage.rawValue,
        L10n.deleteActivityEntire.rawValue,
    ]

    // MARK: - Key resolution

    @Test("all L10n keys resolve to non-empty strings in en.lproj")
    func allKeysResolveEN() throws {
        let main = Bundle.main
        let path = try #require(main.path(forResource: "en", ofType: "lproj"),
                                "Missing en.lproj in main bundle")
        let bundle = try #require(Bundle(path: path))

        for caseValue in l10nCases where !Self.pluralKeys.contains(caseValue.rawValue) {
            let value = NSLocalizedString(caseValue.rawValue, bundle: bundle, comment: "")
            #expect(value != caseValue.rawValue,
                    "Unresolved key \(caseValue.rawValue) in en")
            #expect(!value.isEmpty,
                    "Empty value for key \(caseValue.rawValue) in en")
        }
    }

    @Test("all L10n keys resolve to non-empty strings in ru.lproj")
    func allKeysResolveRU() throws {
        let main = Bundle.main
        let path = try #require(main.path(forResource: "ru", ofType: "lproj"),
                                "Missing ru.lproj in main bundle")
        let bundle = try #require(Bundle(path: path))

        for caseValue in l10nCases where !Self.pluralKeys.contains(caseValue.rawValue) {
            let value = NSLocalizedString(caseValue.rawValue, bundle: bundle, comment: "")
            #expect(value != caseValue.rawValue,
                    "Unresolved key \(caseValue.rawValue) in ru")
            #expect(!value.isEmpty,
                    "Empty value for key \(caseValue.rawValue) in ru")
        }
    }

    @Test("both locales have the same set of keys")
    func keyParity() throws {
        let main = Bundle.main
        let enPath = try #require(main.path(forResource: "en", ofType: "lproj"))
        let ruPath = try #require(main.path(forResource: "ru", ofType: "lproj"))
        let enBundle = try #require(Bundle(path: enPath))
        let ruBundle = try #require(Bundle(path: ruPath))

        for caseValue in l10nCases where !Self.pluralKeys.contains(caseValue.rawValue) {
            let enValue = NSLocalizedString(caseValue.rawValue, bundle: enBundle, comment: "")
            let ruValue = NSLocalizedString(caseValue.rawValue, bundle: ruBundle, comment: "")

            #expect(enValue != caseValue.rawValue,
                    "Key \(caseValue.rawValue) missing in en")
            #expect(ruValue != caseValue.rawValue,
                    "Key \(caseValue.rawValue) missing in ru")
        }
    }

    @Test("plural-root keys resolve via the Swift-side plural dispatcher")
    func pluralKeysResolve() {
        for count in [0, 1, 2, 5, 11, 21, 22, 25, 100] {
            let m = L10n.deleteActivityMessage.text(count)
            let e = L10n.deleteActivityEntire.text(count)
            #expect(!m.isEmpty,
                    "delete.activity.message empty for count \(count)")
            #expect(m != L10n.deleteActivityMessage.rawValue,
                    "delete.activity.message unresolved for count \(count)")
            #expect(!e.isEmpty,
                    "delete.activity.entire empty for count \(count)")
            #expect(e != L10n.deleteActivityEntire.rawValue,
                    "delete.activity.entire unresolved for count \(count)")
        }
    }

    @Test("per-form plural keys resolve to non-empty strings in en + ru bundles")
    func pluralFormKeysExist() throws {
        let main = Bundle.main
        let enPath = try #require(main.path(forResource: "en", ofType: "lproj"),
                                  "Missing en.lproj in main bundle")
        let ruPath = try #require(main.path(forResource: "ru", ofType: "lproj"),
                                  "Missing ru.lproj in main bundle")
        let enBundle = try #require(Bundle(path: enPath))
        let ruBundle = try #require(Bundle(path: ruPath))

        let roots: [String] = [
            L10n.deleteActivityMessage.rawValue,
            L10n.deleteActivityEntire.rawValue,
        ]
        let pairs: [(String, Bundle, [String])] = [
            ("en", enBundle, ["one", "other"]),
            ("ru", ruBundle, ["one", "few", "many"]),
        ]
        for (locale, bundle, forms) in pairs {
            for root in roots {
                for form in forms {
                    let key = "\(root).\(form)"
                    let value = NSLocalizedString(key, bundle: bundle, comment: "")
                    #expect(value != key,
                            "Unresolved key \(key) in \(locale)")
                    #expect(!value.isEmpty,
                            "Empty value for key \(key) in \(locale)")
                }
            }
        }
    }

    // MARK: - Error codes

    @Test("known error codes resolve via ErrorLocalization without falling back to unknown")
    func errorCodesResolve() throws {
        let codes = [
            "invalid_body", "rate_limited",
            "invalid_otp", "otp_expired", "otp_attempts_exceeded",
            "invalid_refresh", "token_reuse", "token_expired",
            // Catalog (Epic 1)
            "conflict", "activity_exists", "category_exists",
            "validation_error", "not_found",
        ]
        let unknownText = NSLocalizedString("error.unknown", comment: "")

        for code in codes {
            let msg = L10n.text(in: .default, code: code)
            #expect(!msg.isEmpty)
            #expect(msg != unknownText,
                    "Code \(code) fell back to error.unknown")
        }
    }

    @Test("offline error maps to offline banner text")
    func offlineMapping() {
        // Qualified because `CatalogError.offline` also exists (catalog Epic 1).
        let msg = ErrorLocalization.message(for: APIError.offline)
        #expect(!msg.isEmpty)
    }

    // MARK: - Validation fragment keys

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
                #expect(value != key, "Unresolved key \(key) in \(code)")
                #expect(!value.isEmpty, "Empty value for key \(key) in \(code)")
            }
        }
    }

    // MARK: - L10n enum allCases matches strings files

    @Test("L10n enum allCases count matches keys in en.lproj")
    func allCasesCount() throws {
        let main = Bundle.main
        let enPath = try #require(main.path(forResource: "en", ofType: "lproj"),
                                  "Missing en.lproj in main bundle")
        let enBundle = try #require(Bundle(path: enPath))
        let stringsPath = try #require(enBundle.path(forResource: "Localizable", ofType: "strings"),
                                       "Missing Localizable.strings in en.lproj")
        // .strings files are UTF-16 property lists; read via PropertyListSerialization.
        let stringsData = try Data(contentsOf: URL(fileURLWithPath: stringsPath))
        let plist = try PropertyListSerialization.propertyList(from: stringsData, format: nil)
        guard let dict = plist as? [String: String] else {
            Issue.record("Failed to load Localizable.strings")
            return
        }
        let keysInFile = Set(dict.keys)
        let pluralRoots = [
            L10n.deleteActivityMessage.rawValue,
            L10n.deleteActivityEntire.rawValue,
        ]
        let enumKeys = Set(l10nCases.map(\.rawValue))
        let missingKeys = enumKeys.filter { key in
            if pluralRoots.contains(key) {
                return false
            }
            return !keysInFile.contains(key)
        }
        #expect(missingKeys.isEmpty,
                "Missing L10n keys in en.lproj: \(missingKeys.sorted())")
    }
}
