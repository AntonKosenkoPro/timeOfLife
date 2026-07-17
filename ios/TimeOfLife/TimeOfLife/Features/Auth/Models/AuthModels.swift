import Foundation

/// A signed-in user as returned by the API (signup, verify, signin, me).
struct UserDTO: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let emailVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, email
        case emailVerified = "email_verified"
    }
}

/// Response body for `/auth/signup` — no tokens on signup, only the user.
struct SignupResponse: Codable, Equatable, Sendable {
    let user: UserDTO
}

/// Response body for `/auth/verify-email` and `/auth/signin`: tokens + user.
struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

/// Request bodies — keep them tiny and explicit so tests can assert payloads.
struct SignupRequest: Codable, Equatable, Sendable {
    let email: String
    let password: String
}
struct SigninRequest: Codable, Equatable, Sendable {
    let email: String
    let password: String
}
struct VerifyEmailRequest: Codable, Equatable, Sendable {
    let token: String
}
struct ResendRequest: Codable, Equatable, Sendable {
    let email: String
}
struct RefreshRequest: Codable, Equatable, Sendable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}
struct ResetConfirmRequest: Codable, Equatable, Sendable {
    let token: String
    let newPassword: String
    enum CodingKeys: String, CodingKey {
        case token
        case newPassword = "new_password"
    }
}
struct ResetRequestRequest: Codable, Equatable, Sendable {
    let email: String
}

/// User-facing credentials (email only — never the password).
struct Credentials: Equatable, Sendable {
    let email: String
    let emailVerified: Bool
}