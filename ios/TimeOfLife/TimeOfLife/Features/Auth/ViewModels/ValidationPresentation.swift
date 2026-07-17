import Foundation

/// Maps `AuthValidator.ValidationError` to localized strings.
extension AuthValidator.ValidationError {
    var l10nKey: String {
        switch self {
        case .emailEmpty: return "validation.emailEmpty"
        case .emailInvalid: return "validation.emailInvalid"
        case .emailTooLong: return "validation.emailTooLong"
        case .passwordEmpty: return "validation.passwordEmpty"
        case .passwordTooShort: return "validation.passwordTooShort"
        case .passwordTooLong: return "validation.passwordTooLong"
        case .passwordNoLetter: return "validation.passwordNoLetter"
        case .passwordNoDigit: return "validation.passwordNoDigit"
        case .passwordWhitespaceOnly: return "validation.passwordWhitespaceOnly"
        }
    }

    var text: String { NSLocalizedString(l10nKey, comment: "") }

    /// Stable identifier for tests that want to assert without localizing.
    var id: String { l10nKey }
}

/// Per-field error presentation surfaced to views.
struct FieldErrors: Equatable {
    var email: [String]
    var password: [String]

    static let empty = FieldErrors(email: [], password: [])
    var isEmpty: Bool { email.isEmpty && password.isEmpty }
}