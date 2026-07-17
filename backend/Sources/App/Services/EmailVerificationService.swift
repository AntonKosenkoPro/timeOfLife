import Foundation
import Fluent
import Vapor

/// Issues / verifies / resends email verification tokens. Verifying an email issues tokens too.
final class EmailVerificationService: Sendable {
    let tokens: TokenService
    let emailer: EmailSender
    let config: AppConfig

    static let ttlSeconds: TimeInterval = 24 * 60 * 60 // +24h

    init(tokens: TokenService, emailer: EmailSender, config: AppConfig) {
        self.tokens = tokens
        self.emailer = emailer
        self.config = config
    }

    /// Create a verification token + send the email. Idempotent over multiple sends.
    func sendVerification(user: User, language: EmailLanguage, on db: Database) async throws {
        let raw = TokenService.generateOpaqueToken()
        let hash = TokenService.sha256Hex(raw)
        let record = EmailVerificationToken(
            userID: user.id!,
            tokenHash: hash,
            expiresAt: Date().addingTimeInterval(Self.ttlSeconds),
            used: false
        )
        try await record.create(on: db)

        let link = "\(config.verifyLinkBase)?token=\(raw)"
        try await emailer.send(
            to: user.email,
            subjectKey: .verifyEmail,
            language: language,
            linkURL: link
        )
    }

    /// Verify a token: mark the user verified, invalidate the token, issue session tokens.
    func verify(rawToken: String, on db: Database) async throws -> (user: User, access: String, refresh: String) {
        let hash = TokenService.sha256Hex(rawToken)
        guard let record = try await EmailVerificationToken.query(on: db)
            .filter(\.$tokenHash == hash)
            .first()
        else {
            throw VerifyError.tokenInvalid
        }
        if record.used {
            throw VerifyError.tokenUsed
        }
        if record.expiresAt <= Date() {
            throw VerifyError.tokenExpired
        }

        guard let user = try await User.find(record.$user.id, on: db) else {
            throw VerifyError.tokenInvalid
        }

        // Mark user verified + token used (best-effort: keep other sessions intact per plan).
        user.emailVerifiedAt = Date()
        try await user.save(on: db)
        record.used = true
        try await record.save(on: db)

        let access = try await tokens.issueAccessToken(user: user)
        let refresh = try await tokens.issueRefreshToken(for: user.id!, on: db)
        return (user, access, refresh)
    }

    /// Resend verification to an email address. Always returns success (no enumeration).
    /// Returns true if a new email was actually sent (for tests); false if user not found / already verified.
    @discardableResult
    func resend(email rawEmail: String, language: EmailLanguage, on db: Database) async throws -> Bool {
        let normalized: String
        do { normalized = try AuthService.normalizeEmail(rawEmail) }
        catch { return false }
        guard let user = try await User.query(on: db).filter(\.$email == normalized).first(),
              !user.isEmailVerified
        else {
            return false
        }
        try await sendVerification(user: user, language: language, on: db)
        return true
    }
}