import Foundation
import Vapor
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import JWTKit
import JWT
import AsyncHTTPClient

/// Configure the application. `useSQLite` allows tests to run without Postgres/Docker.
func configure(_ app: Application) async throws {
    try await configure(app, useSQLite: false)
}

func configure(_ app: Application, useSQLite: Bool) async throws {
    let config = AppConfig.resolve(from: app.environment)

    // 1) Databases. The first `use(...)` becomes the default (nil-id) database.
    if useSQLite {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        if let url = Environment.get("DATABASE_URL"), !url.isEmpty {
            let parsed = URL(string: url) ?? URL(string: "postgresql://localhost:5432/tol")!
            app.databases.use(try .postgres(url: parsed), as: .psql)
        } else {
            let host = Environment.get("DB_HOST") ?? "localhost"
            let port = Int(Environment.get("DB_PORT") ?? "5432") ?? 5432
            let user = Environment.get("DB_USER") ?? "tol"
            let pass = Environment.get("DB_PASSWORD") ?? "tol"
            let name = Environment.get("DB_NAME") ?? "tol"
            app.databases.use(.postgres(hostname: host, port: port, username: user, password: pass, database: name), as: .psql)
        }
    }

    // 2) Migrations (shared between both drivers).
    app.migrations.add(CreateUsers())
    app.migrations.add(CreateRefreshTokens())
    app.migrations.add(CreatePasswordResetTokens())
    app.migrations.add(CreateEmailVerificationTokens())
    try await app.autoMigrate()

    // 3) JWT signing (HS256) with the configured secret.
    let keys = JWTKeyCollection()
    let secretString = String(decoding: config.jwtSecret, as: UTF8.self)
    await keys.add(hmac: HMACKey(from: secretString), digestAlgorithm: .sha256)
    app.jwt.keys = keys

    // 4) Email sender.
    var httpClient: HTTPClient? = nil
    let emailer: EmailSender
    switch config.emailBackend {
    case .console:
        emailer = ConsoleEmailSender(logger: app.logger)
    case .mailgun:
        guard let mg = config.mailgun else {
            fatalError("EMAIL_BACKEND=mailgun requires Mailgun config.")
        }
        let client = HTTPClient(eventLoopGroupProvider: .shared(app.eventLoopGroup))
        httpClient = client
        emailer = MailgunEmailSender(httpClient: client, config: mg)
    }

    // 5) Services.
    let tokens = TokenService(app: app, config: config)
    let emails = EmailVerificationService(tokens: tokens, emailer: emailer, config: config)
    let auth = AuthService(app: app, tokens: tokens, emails: emails, config: config)
    let passwordReset = PasswordResetService(tokens: tokens, emailer: emailer, config: config)
    let rateLimiter = RateLimiter()

    app.services = AppServices(
        config: config,
        tokens: tokens,
        emails: emails,
        passwordReset: passwordReset,
        auth: auth,
        emailer: emailer,
        rateLimiter: rateLimiter,
        httpClient: httpClient
    )

    // 6) Routes.
    try routes(app)
}