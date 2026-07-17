import Foundation

/// Protocol for the auth data source. Production uses `RemoteAuthRepository`
/// over `APIClient`; tests use `FakeAuthRepository` to drive view models and
/// `AuthService` without a network.
protocol AuthRepository: Sendable {
    func signup(email: String, password: String) async throws -> SignupResponse
    func verifyEmail(token: String) async throws -> AuthSession
    func resendVerification(email: String) async throws
    func signin(email: String, password: String) async throws -> AuthSession
    func refresh(refreshToken: String) async throws -> AuthSession
    func logout() async throws
    func me() async throws -> UserDTO
    func requestPasswordReset(email: String) async throws
    func confirmPasswordReset(token: String, newPassword: String) async throws
}