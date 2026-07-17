import Foundation
import Vapor
import Fluent
import FluentSQLiteDriver
import JWTKit
import NIOConcurrencyHelpers
@testable import App

/// Email sender that captures all sent emails in memory for test assertions.
final class CapturingEmailSender: EmailSender, @unchecked Sendable {
    struct SentEmail: Equatable {
        let to: String
        let subjectKey: EmailTemplateKey
        let language: EmailLanguage
        let linkURL: String
    }

    private let lock = NIOLock()
    private var _captured: [SentEmail] = []

    var captured: [SentEmail] {
        lock.withLock { _captured }
    }

    func send(to address: String, subjectKey: EmailTemplateKey, language: EmailLanguage, linkURL: String) async throws {
        lock.withLockVoid {
            _captured.append(SentEmail(to: address, subjectKey: subjectKey, language: language, linkURL: linkURL))
        }
    }

    func reset() {
        lock.withLockVoid { _captured.removeAll() }
    }

    /// Extract the raw token from a `timeoflife://verify?token=...` / `...://reset?token=...` link.
    func rawToken(at index: Int = 0) -> String? {
        let emails = captured
        guard index < emails.count else { return nil }
        let link = emails[index].linkURL
        guard let comps = URLComponents(string: link),
              let token = comps.queryItems?.first(where: { $0.name == "token" })?.value
        else { return nil }
        return token
    }
}

/// Test bootstrap: builds a fresh Application with SQLite in-memory + capturing emailer + bcrypt cost 4.
enum TestApp {
    static let jwtSecret = Array("test-secret-test-secret-test-secret-0123456789".utf8)
    static let bcryptCost = 4

    @discardableResult
    static func make() async throws -> (app: Application, emailer: CapturingEmailSender) {
        let env = Environment.testing
        let app = try await Application.make(env)

        // SQLite in-memory (first registered = default).
        app.databases.use(.sqlite(.memory), as: .sqlite)

        // Migrations.
        app.migrations.add(CreateUsers())
        app.migrations.add(CreateRefreshTokens())
        app.migrations.add(CreatePasswordResetTokens())
        app.migrations.add(CreateEmailVerificationTokens())
        try await app.autoMigrate()

        // JWT HS256 with a known test secret.
        let keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(from: String(decoding: jwtSecret, as: UTF8.self)), digestAlgorithm: .sha256)
        app.jwt.keys = keys

        // Config (tests use SQLite so DATABASE_URL is irrelevant).
        let config = AppConfig(
            databaseURL: "sqlite://memory",
            jwtSecret: jwtSecret,
            jwtIssuer: "timeoflife-test",
            accessTokenTTLSeconds: 900,
            refreshTokenTTLSeconds: 2_592_000,
            bcryptCost: bcryptCost,
            emailBackend: .console,
            mailgun: nil,
            resetLinkBase: "timeoflife://reset",
            verifyLinkBase: "timeoflife://verify"
        )

        let emailer = CapturingEmailSender()
        let tokens = TokenService(app: app, config: config)
        let emails = EmailVerificationService(tokens: tokens, emailer: emailer, config: config)
        let auth = AuthService(app: app, tokens: tokens, emails: emails, config: config)
        let passwordReset = PasswordResetService(tokens: tokens, emailer: emailer, config: config)
        let rateLimiter = RateLimiter(capacity: 100, refillRatePerSecond: 100, retryAfterSeconds: 1)

        app.services = AppServices(
            config: config,
            tokens: tokens,
            emails: emails,
            passwordReset: passwordReset,
            auth: auth,
            emailer: emailer,
            rateLimiter: rateLimiter,
            httpClient: nil
        )

        try routes(app)
        return (app, emailer)
    }
}