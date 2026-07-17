import Foundation
import Vapor
import AsyncHTTPClient

/// Holds all wiring of the auth MVP. Stored on `Application.services`.
struct AppServices: Sendable {
    let config: AppConfig
    let tokens: TokenService
    let emails: EmailVerificationService
    let passwordReset: PasswordResetService
    let auth: AuthService
    let emailer: EmailSender
    let rateLimiter: RateLimiter
    let httpClient: HTTPClient?
}

extension Application {
    private struct Key: StorageKey { typealias Value = AppServices }

    var services: AppServices? {
        get { storage[Key.self] }
        set { storage[Key.self] = newValue }
    }
}

extension Request {
    var services: AppServices? { application.services }
}