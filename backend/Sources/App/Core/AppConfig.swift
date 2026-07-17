import Foundation
import Vapor

/// Centralized, environment-driven application configuration.
/// Resolved once at boot time. Fail-fast if security-critical values are missing/invalid.
struct AppConfig {
    let databaseURL: String
    let jwtSecret: [UInt8]
    let jwtIssuer: String
    let accessTokenTTLSeconds: Int64
    let refreshTokenTTLSeconds: Int64
    let bcryptCost: Int
    let emailBackend: EmailBackend
    let mailgun: MailgunConfig?
    let resetLinkBase: String
    let verifyLinkBase: String

    enum EmailBackend: String {
        case console = "console"
        case mailgun = "mailgun"
    }

    struct MailgunConfig {
        let apiKey: String
        let domain: String
        let from: String
        let apiBaseURL: String
    }

    /// Pull config from `Environment` + `Application`. Throws on missing/invalid secrets.
    static func resolve(from env: Environment) -> AppConfig {
        func get(_ key: String, file: String = #file, line: UInt = #line) -> String? {
            Environment.get(key)
        }

        // JWT_SECRET — required, >= 32 bytes
        let jwtSecretString: String
        if let raw = get("JWT_SECRET"), !raw.isEmpty {
            jwtSecretString = raw
        } else {
            fatalError("FATAL: JWT_SECRET environment variable is missing. Required for HS256 signing (>=32 bytes).")
        }
        let secretBytes = Array(jwtSecretString.utf8)
        guard secretBytes.count >= 32 else {
            fatalError("FATAL: JWT_SECRET must be at least 32 bytes (got \(secretBytes.count)).")
        }

        // DATABASE_URL — required for the server. Tests bypass via configure(::, useSQLite:).
        let databaseURL = get("DATABASE_URL") ?? "postgresql://localhost:5432/tol"

        // BCRYPT_COST — default 12, tests use 4
        let bcryptCost = Int(get("BCRYPT_COST") ?? "12") ?? 12
        precondition(bcryptCost >= 4 && bcryptCost <= 31, "BCRYPT_COST must be 4...31")

        // EMAIL_BACKEND
        let emailBackendRaw = (get("EMAIL_BACKEND") ?? "console").lowercased()
        let emailBackend = EmailBackend(rawValue: emailBackendRaw) ?? .console

        // Mailgun config (optional; required only when backend=mailgun)
        let mailgun: MailgunConfig?
        if emailBackend == .mailgun {
            guard let key = get("MAILGUN_API_KEY"), !key.isEmpty,
                  let domain = get("MAILGUN_DOMAIN"), !domain.isEmpty,
                  let from = get("MAILGUN_FROM"), !from.isEmpty
            else {
                fatalError("FATAL: EMAIL_BACKEND=mailgun requires MAILGUN_API_KEY, MAILGUN_DOMAIN, MAILGUN_FROM.")
            }
            let base = get("MAILGUN_API_BASE_URL") ?? "https://api.mailgun.net"
            mailgun = MailgunConfig(apiKey: key, domain: domain, from: from, apiBaseURL: base)
        } else {
            mailgun = nil
        }

        let jwtIssuer = get("JWT_ISSUER") ?? "timeoflife"
        let accessTTL = Int64(get("ACCESS_TOKEN_TTL") ?? "900") ?? 900
        let refreshTTL = Int64(get("REFRESH_TOKEN_TTL") ?? "2592000") ?? 2_592_000
        let resetLink = get("RESET_LINK_BASE") ?? "timeoflife://reset"
        let verifyLink = get("VERIFY_LINK_BASE") ?? "timeoflife://verify"

        return AppConfig(
            databaseURL: databaseURL,
            jwtSecret: secretBytes,
            jwtIssuer: jwtIssuer,
            accessTokenTTLSeconds: accessTTL,
            refreshTokenTTLSeconds: refreshTTL,
            bcryptCost: bcryptCost,
            emailBackend: emailBackend,
            mailgun: mailgun,
            resetLinkBase: resetLink,
            verifyLinkBase: verifyLink
        )
    }
}