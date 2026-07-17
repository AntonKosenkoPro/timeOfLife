import Foundation
import Fluent
import Vapor

/// Issues / confirms password-reset tokens. Confirming revokes ALL refresh tokens.
final class PasswordResetService: Sendable {
    let tokens: TokenService
    let emailer: EmailSender
    let config: AppConfig

    static let ttlSeconds: TimeInterval = 60 * 60 // +1h

    init(tokens: TokenService, emailer: EmailSender, config: AppConfig) {
        self.tokens = tokens
        self.emailer = emailer
        self.config = config
    }

    /// Request a reset. Always 202 (no user enumeration). Invalidates prior unused tokens.
    /// Returns true if an email was actually sent (for tests); false if no such user.
    @discardableResult
    func requestReset(email rawEmail: String, language: EmailLanguage, on db: Database) async throws -> Bool {
        let normalized: String
        do { normalized = try AuthService.normalizeEmail(rawEmail) }
        catch { return false } // malformed email → still 202, no email sent.

        guard let user = try await User.query(on: db).filter(\.$email == normalized).first() else {
            return false
        }

        // Invalidate prior unused tokens for this user.
        let prior = try await PasswordResetToken.query(on: db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$used == false)
            .all()
        for token in prior {
            token.used = true
            try await token.save(on: db)
        }

        // Issue a new token.
        let raw = TokenService.generateOpaqueToken()
        let hash = TokenService.sha256Hex(raw)
        let record = PasswordResetToken(
            userID: user.id!,
            tokenHash: hash,
            expiresAt: Date().addingTimeInterval(Self.ttlSeconds),
            used: false
        )
        try await record.create(on: db)

        let link = "\(config.resetLinkBase)?token=\(raw)"
        try await emailer.send(
            to: user.email,
            subjectKey: .passwordReset,
            language: language,
            linkURL: link
        )
        return true
    }

    /// Confirm a reset: validate token, set new password (validated), mark used, revoke all refresh tokens.
    func confirmReset(rawToken: String, newPassword: String, on db: Database) async throws {
        do {
            try PasswordValidator.validateOrThrow(newPassword)
        } catch AuthError.weakPassword(let rules) {
            throw ResetError.weakPassword(rules: rules)
        }

        let hash = TokenService.sha256Hex(rawToken)
        guard let record = try await PasswordResetToken.query(on: db)
            .filter(\.$tokenHash == hash)
            .first()
        else {
            throw ResetError.tokenInvalid
        }
        if record.used {
            throw ResetError.tokenUsed
        }
        if record.expiresAt <= Date() {
            throw ResetError.tokenExpired
        }

        guard let user = try await User.find(record.$user.id, on: db) else {
            throw ResetError.tokenInvalid
        }

        // Update password + mark token used.
        user.passwordHash = try Bcrypt.hash(newPassword, cost: config.bcryptCost)
        try await user.save(on: db)
        record.used = true
        try await record.save(on: db)

        // Revoke all refresh tokens (password change invalidates sessions).
        try await tokens.revokeAllForUser(user.id!, on: db)
    }
}