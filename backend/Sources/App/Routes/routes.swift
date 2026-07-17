import Foundation
import Vapor
import Fluent

/// Wires all `/api/v1` routes.
@discardableResult
func routes(_ app: Application) throws -> RoutesBuilder {
    let v1 = app.grouped("api", "v1")

    guard let services = app.services else {
        preconditionFailure("AppServices must be configured before routes().")
    }

    let authController = AuthController(services)
    let passwordResetController = PasswordResetController(services)
    let rateLimiter = services.rateLimiter

    let auth = v1.grouped("auth")

    // Rate-limited public mutating auth endpoints.
    let rateLimited = auth.grouped(RateLimitMiddleware(limiter: rateLimiter, scope: "auth"))
    rateLimited.post("signup", use: authController.signup)
    rateLimited.post("verify-email", use: authController.verifyEmail)
    rateLimited.post("verify-email", "resend", use: authController.resendVerification)
    rateLimited.post("signin", use: authController.signin)
    rateLimited.post("refresh", use: authController.refresh)

    // Authenticated (Bearer) endpoints.
    let protected = auth.grouped(JWTAuthMiddleware(tokens: services.tokens))
    protected.post("logout", use: authController.logout)
    protected.get("me", use: authController.me)

    // Password reset endpoints (rate-limited).
    let password = v1.grouped("password")
    let passwordRL = password.grouped(RateLimitMiddleware(limiter: rateLimiter, scope: "password"))
    passwordRL.post("reset-request", use: passwordResetController.resetRequest)
    passwordRL.post("reset-confirm", use: passwordResetController.resetConfirm)

    return v1
}