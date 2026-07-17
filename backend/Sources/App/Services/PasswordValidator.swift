import Foundation

/// Pure password strength validator. No I/O.
enum PasswordValidator {
    /// Password rules. Codes returned when violated.
    enum Rule: String, Sendable {
        case minLength = "min_8"
        case atLeastOneLetter = "one_letter"
        case atLeastOneDigit = "one_digit"
        case maxLength = "max_128"
        case noWhitespaceOnly = "no_whitespace_only"
    }

    static let maxLength = 128
    static let minLength = 8

    /// Validate the password, returning violated rule codes (empty if valid).
    static func violations(_ password: String) -> [String] {
        var failed: [String] = []

        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            failed.append(Rule.noWhitespaceOnly.rawValue)
            return failed
        }

        if password.count < minLength {
            failed.append(Rule.minLength.rawValue)
        }
        if password.count > maxLength {
            failed.append(Rule.maxLength.rawValue)
        }

        let hasLetter = password.contains { $0.isLetter }
        if !hasLetter {
            failed.append(Rule.atLeastOneLetter.rawValue)
        }
        let hasDigit = password.contains { $0.isNumber }
        if !hasDigit {
            failed.append(Rule.atLeastOneDigit.rawValue)
        }

        return failed
    }

    /// Throws `AuthError.weakPassword(rules:)` when invalid.
    static func validateOrThrow(_ password: String) throws {
        let v = violations(password)
        guard v.isEmpty else {
            throw AuthError.weakPassword(rules: v)
        }
    }
}