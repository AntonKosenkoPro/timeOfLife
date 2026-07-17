import Foundation
import Fluent
import Vapor

/// Orchestrates signup / signin / refresh / logout.
final class AuthService: Sendable {
    let tokens: TokenService
    let emails: EmailVerificationService
    let config: AppConfig
    let app: Application

    init(app: Application, tokens: TokenService, emails: EmailVerificationService, config: AppConfig) {
        self.app = app
        self.tokens = tokens
        self.emails = emails
        self.config = config
    }

    /// Normalize an email: lowercase + trim; max 254. Throws `invalid_body` if empty/too long/malformed.
    static func normalizeEmail(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw AuthError.invalidBody }
        guard trimmed.count <= 254 else { throw AuthError.invalidBody }
        guard trimmed.contains("@"), trimmed.contains(".") else { throw AuthError.invalidBody }
        return trimmed
    }

    /// Sign up: create an UNVERIFIED user, send verification email. NO tokens returned.
    func signUp(email rawEmail: String, password: String, language: EmailLanguage, on db: Database) async throws -> User {
        let email = try Self.normalizeEmail(rawEmail)
        try PasswordValidator.validateOrThrow(password)

        // Check uniqueness (explicit query → uniform `email_taken` error).
        if let _ = try await User.query(on: db).filter(\.$email == email).first() {
            throw AuthError.emailTaken
        }

        let hash = try Bcrypt.hash(password, cost: config.bcryptCost)
        let user = User(email: email, passwordHash: hash, emailVerifiedAt: nil)
        do {
            try await user.save(on: db)
        } catch {
            // Race: unique constraint violation surfaced by DB.
            throw AuthError.emailTaken
        }

        // Send verification email.
        try await emails.sendVerification(user: user, language: language, on: db)
        return user
    }

    /// Sign in: verify password; reject unverified with `email_not_verified`; issue tokens.
    func signIn(
        email rawEmail: String,
        password: String,
        deviceId: String?,
        userAgent: String?,
        on req: Request
    ) async throws -> (access: String, refresh: String, user: User) {
        let email = try Self.normalizeEmail(rawEmail)
        guard let user = try await User.query(on: req.db).filter(\.$email == email).first() else {
            // Generic error — no user enumeration.
            throw AuthError.invalidCredentials
        }
        // Verify password before leaking verification state.
        guard (try? Bcrypt.verify(password, created: user.passwordHash)) == true else {
            throw AuthError.invalidCredentials
        }
        guard user.isEmailVerified else {
            throw AuthError.emailNotVerified
        }
        let access = try await tokens.issueAccessToken(user: user)
        let refresh = try await tokens.issueRefreshToken(
            for: user.id!,
            deviceId: deviceId,
            userAgent: userAgent,
            on: req.db
        )
        return (access, refresh, user)
    }

    /// Refresh: rotate tokens.
    func refresh(rawOld: String, on db: Database) async throws -> (access: String, refresh: String, user: User) {
        try await tokens.rotateRefreshToken(rawOld: rawOld, on: db)
    }

    /// Logout: revoke presented refresh token.
    func logout(raw: String, on db: Database) async throws {
        try await tokens.revokeRefreshToken(raw: raw, on: db)
    }
}