import Foundation

/// Protocol for the auth data source. Production uses `RemoteAuthRepository`
/// over `APIClient`; tests use `FakeAuthRepository` to drive view models and
/// `AuthService` without a network.
protocol AuthRepository: Sendable {
    /// `POST /auth/otp/request` — always 202 (no enumeration). The server
    /// upserts a user and emails a 6-digit code.
    func requestOtp(email: String) async throws
    /// `POST /auth/otp/verify` — returns tokens + user on success.
    func verifyOtp(email: String, code: String) async throws -> AuthSession
    /// `POST /auth/apple` — exchanges Apple's identity token for a session.
    func appleSignIn(identityToken: String) async throws -> AuthSession
    /// `POST /auth/refresh` — rotates tokens.
    func refresh(refreshToken: String) async throws -> AuthSession
    /// `POST /auth/logout` (Bearer) — 204.
    func logout() async throws
    /// `GET /auth/me` (Bearer).
    func me() async throws -> UserDTO
}
