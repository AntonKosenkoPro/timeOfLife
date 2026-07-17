import Foundation

/// Pure validation mirroring the backend rules (so the client rejects before
/// hitting the network, but the server remains the source of truth).
///
/// Passwordless model (Requirements F1/U1): the only inputs are
/// - email: non-empty, valid shape, ≤254, lowercased/trimmed before send.
/// - OTP code: exactly 6 digits.
enum AuthValidator {
    enum Field: String, Hashable, Sendable {
        case email
        case otp
    }

    enum ValidationError: Error, Equatable, Sendable {
        case emailEmpty
        case emailInvalid
        case emailTooLong
        case otpEmpty
        case otpInvalid
    }

    static let maxEmail = 254
    static let otpLength = 6

    /// Returns per-field errors; empty means valid. `code` is optional so the
    /// email screen can validate email alone.
    static func validate(email: String, code: String?) -> [Field: [ValidationError]] {
        var out: [Field: [ValidationError]] = [:]
        out[.email] = validateEmail(email)
        if let code {
            out[.otp] = validateOtpCode(code)
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

    /// Validates an OTP code: exactly 6 digits (after trimming whitespace).
    static func validateOtpCode(_ raw: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            errors.append(.otpEmpty)
            return errors
        }
        if code.count != otpLength || !code.allSatisfy({ $0.isNumber }) {
            errors.append(.otpInvalid)
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

    // MARK: - Unified messages (Requirements U4)

    /// A single, merged message for the email field, or `nil` when valid.
    /// Multiple simultaneous email problems are folded into one sentence
    /// rather than listed separately.
    static func unifiedEmailMessage(_ errors: [ValidationError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.contains(.emailEmpty) {
            return NSLocalizedString("validation.emailEmpty", comment: "")
        }
        var fragments: [String] = []
        if errors.contains(.emailInvalid) {
            fragments.append(NSLocalizedString("validation.email.rule.invalid", comment: ""))
        }
        if errors.contains(.emailTooLong) {
            fragments.append(NSLocalizedString("validation.email.rule.tooLong", comment: ""))
        }
        guard !fragments.isEmpty else { return nil }
        return NSLocalizedString("validation.email.prefix", comment: "") + " "
            + joinFragments(fragments) + "."
    }

    /// A single, merged message for the OTP field, or `nil` when valid.
    static func unifiedOtpMessage(_ errors: [ValidationError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.contains(.otpEmpty) {
            return NSLocalizedString("validation.otpEmpty", comment: "")
        }
        // .otpInvalid only.
        return NSLocalizedString("validation.otp.prefix", comment: "") + " "
            + NSLocalizedString("validation.otp.rule.invalid", comment: "") + "."
    }

    /// Joins fragments with a localized "and" before the last item:
    /// `["A"]` → "A"; `["A","B"]` → "A and B"; `["A","B","C"]` → "A, B and C".
    static func joinFragments(_ fragments: [String]) -> String {
        guard fragments.count > 1 else { return fragments.first ?? "" }
        let and = NSLocalizedString("common.and", comment: "")
        let head = fragments.dropLast().joined(separator: ", ")
        return "\(head) \(and) \(fragments.last!)"
    }
}
