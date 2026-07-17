import Testing
import Foundation
@testable import TimeOfLife

@Suite("RemoteAuthRepository")
struct RemoteAuthRepositoryTests {
    private func makeRepo() -> (RemoteAuthRepository, MockAPIClient) {
        let mock = MockAPIClient()
        let repo = RemoteAuthRepository(client: mock)
        return (repo, mock)
    }

    @Test("signup posts to /auth/signup with body")
    func signupEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            SignupResponse(user: UserDTO(id: "u1", email: "a@b.com", emailVerified: false))
        }
        let resp = try await repo.signup(email: "a@b.com", password: "abcd1234")
        #expect(resp.user.emailVerified == false)
        let r = mock.received.first
        #expect(r?.method == .post)
        #expect(r?.path == "/api/v1/auth/signup")
        #expect(r?.requiresAuth == false)
        let body = r?.body
        #expect(body != nil)
        let decoded = try JSONDecoder().decode(SignupRequest.self, from: body!)
        #expect(decoded.email == "a@b.com")
        #expect(decoded.password == "abcd1234")
    }

    @Test("signin posts to /auth/signin")
    func signinEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            AuthSession(accessToken: "at", refreshToken: "rt",
                        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
        }
        _ = try await repo.signin(email: "a@b.com", password: "abcd1234")
        #expect(mock.received.first?.path == "/api/v1/auth/signin")
    }

    @Test("verifyEmail posts to /auth/verify-email")
    func verifyEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            AuthSession(accessToken: "at", refreshToken: "rt",
                        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
        }
        _ = try await repo.verifyEmail(token: "tok")
        #expect(mock.received.first?.path == "/api/v1/auth/verify-email")
        let body = mock.received.first?.body
        let decoded = try JSONDecoder().decode(VerifyEmailRequest.self, from: body!)
        #expect(decoded.token == "tok")
    }

    @Test("me is GET with auth")
    func meEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in UserDTO(id: "u1", email: "a@b.com", emailVerified: true) }
        _ = try await repo.me()
        let r = mock.received.first
        #expect(r?.method == .get)
        #expect(r?.path == "/api/v1/auth/me")
        #expect(r?.requiresAuth == true)
    }

    @Test("logout posts with auth")
    func logoutEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        try await repo.logout()
        let r = mock.received.first
        #expect(r?.method == .post)
        #expect(r?.path == "/api/v1/auth/logout")
        #expect(r?.requiresAuth == true)
    }

    @Test("password reset-request posts to /password/reset-request")
    func resetRequestEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        try await repo.requestPasswordReset(email: "a@b.com")
        #expect(mock.received.first?.path == "/api/v1/password/reset-request")
    }

    @Test("password reset-confirm posts to /password/reset-confirm")
    func resetConfirmEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        try await repo.confirmPasswordReset(token: "t", newPassword: "abcd1234")
        let r = mock.received.first
        #expect(r?.path == "/api/v1/password/reset-confirm")
        let decoded = try JSONDecoder().decode(ResetConfirmRequest.self, from: r!.body!)
        #expect(decoded.token == "t")
        #expect(decoded.newPassword == "abcd1234")
    }

    @Test("refresh posts to /auth/refresh")
    func refreshEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            AuthSession(accessToken: "at2", refreshToken: "rt2",
                        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
        }
        _ = try await repo.refresh(refreshToken: "rt")
        let r = mock.received.first
        #expect(r?.path == "/api/v1/auth/refresh")
        let decoded = try JSONDecoder().decode(RefreshRequest.self, from: r!.body!)
        #expect(decoded.refreshToken == "rt")
    }

    @Test("server errors propagate from mock")
    func errorPropagation() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            throw APIError.server(code: "invalid_credentials", message: "bad")
        }
        do {
            _ = try await repo.signin(email: "a@b.com", password: "abcd1234")
            Issue.record("expected throw")
        } catch let error as APIError {
            #expect(error.code == "invalid_credentials")
        }
    }
}