import Foundation

/// Pure validation mirroring the backend rules (so the client rejects before
/// hitting the network, but the server remains the source of truth).
///
/// Rules (per plan):
/// - email: RFC-ish, ≤254, non-empty, lowercased/trimmed before send.
/// - password: min 8, ≥1 letter, ≥1 digit, max 128, not whitespace-only.
enum AuthValidator {
    enum Field: String, Hashable, Sendable {
        case email
        case password
    }

    enum ValidationError: Error, Equatable, Sendable {
        case emailEmpty
        case emailInvalid
        case emailTooLong
        case passwordEmpty
        case passwordTooShort
        case passwordTooLong
        case passwordNoLetter
        case passwordNoDigit
        case passwordWhitespaceOnly
    }

    static let maxEmail = 254
    static let minPassword = 8
    static let maxPassword = 128

    /// Returns per-field errors; empty means valid.
    static func validate(email: String, password: String?) -> [Field: [ValidationError]] {
        var out: [Field: [ValidationError]] = [:]
        out[.email] = validateEmail(email)
        if let password {
            out[.password] = validatePassword(password)
        }
        return out.filter { !$0.value.isEmpty }
    }

    static func validateEmail(_ raw: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty {
            errors.append(.emailEmpty)
            return errors
        }
        if email.count > maxEmail {
            errors.append(.emailTooLong)
        }
        if !isValidEmail(email) {
            errors.append(.emailInvalid)
        }
        return errors
    }

    static func validatePassword(_ raw: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        if raw.isEmpty {
            errors.append(.passwordEmpty)
            return errors
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.passwordWhitespaceOnly)
            return errors
        }
        if raw.count < minPassword {
            errors.append(.passwordTooShort)
        }
        if raw.count > maxPassword {
            errors.append(.passwordTooLong)
        }
        if raw.range(of: "[A-Za-z]", options: .regularExpression) == nil {
            errors.append(.passwordNoLetter)
        }
        if raw.range(of: "[0-9]", options: .regularExpression) == nil {
            errors.append(.passwordNoDigit)
        }
        return errors
    }

    /// Normalizes an email for submission: trimmed + lowercased.
    static func normalize(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Lightweight email shape check (deliberately permissive — the server is
    /// authoritative). Accepts `local@domain.tld` with reasonable characters.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}