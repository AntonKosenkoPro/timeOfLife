import Foundation

/// `AuthRepository` backed by an `APIClient`. Maps domain calls onto the
/// shared contract's endpoints; does not own tokens — that's `AuthService`.
final class RemoteAuthRepository: AuthRepository {
    private let client: APISending
    private let basePath = "/api/v1"

    init(client: APISending) {
        self.client = client
    }

    func signup(email: String, password: String) async throws -> SignupResponse {
        try await client.send(
            .post(method: .post, path: "\(basePath)/auth/signup",
                  body: SignupRequest(email: email, password: password)),
            as: SignupResponse.self
        )
    }

    func verifyEmail(token: String) async throws -> AuthSession {
        try await client.send(
            .post(method: .post, path: "\(basePath)/auth/verify-email",
                  body: VerifyEmailRequest(token: token)),
            as: AuthSession.self
        )
    }

    func resendVerification(email: String) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/auth/verify-email/resend",
                        body: ResendRequest(email: email))
        )
    }

    func signin(email: String, password: String) async throws -> AuthSession {
        try await client.send(
            APIEndpoint(method: .post, path: "\(basePath)/auth/signin",
                        body: SigninRequest(email: email, password: password)),
            as: AuthSession.self
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await client.send(
            APIEndpoint(method: .post, path: "\(basePath)/auth/refresh",
                        body: RefreshRequest(refreshToken: refreshToken)),
            as: AuthSession.self
        )
    }

    func logout() async throws {
        try await client.sendVoid(
            APIEndpoint.value(method: .post, path: "\(basePath)/auth/logout", requiresAuth: true)
        )
    }

    func me() async throws -> UserDTO {
        try await client.send(
            APIEndpoint.value(method: .get, path: "\(basePath)/auth/me", requiresAuth: true),
            as: UserDTO.self
        )
    }

    func requestPasswordReset(email: String) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/password/reset-request",
                        body: ResetRequestRequest(email: email))
        )
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws {
        try await client.sendVoid(
            APIEndpoint(method: .post, path: "\(basePath)/password/reset-confirm",
                        body: ResetConfirmRequest(token: token, newPassword: newPassword))
        )
    }
}

private extension APIEndpoint {
    /// Convenience to make the call sites above read clearly.
    static func `post`(method: HTTPMethod, path: String, body: Encodable? = nil) -> APIEndpoint {
        APIEndpoint(method: method, path: path, body: body)
    }
}