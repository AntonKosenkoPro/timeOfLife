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

    @Test("requestOtp posts to /auth/otp/request with body")
    func requestOtpEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendVoidHandler = { _ in }
        try await repo.requestOtp(email: "a@b.com")
        let r = mock.received.first
        #expect(r?.method == .post)
        #expect(r?.path == "/api/v1/auth/otp/request")
        #expect(r?.requiresAuth == false)
        let body = r?.body
        #expect(body != nil)
        let decoded = try JSONDecoder().decode(OtpRequestRequest.self, from: body!)
        #expect(decoded.email == "a@b.com")
    }

    @Test("verifyOtp posts to /auth/otp/verify with body")
    func verifyOtpEndpoint() async throws {
        let (repo, mock) = makeRepo()
        mock.sendHandler = { _, _ in
            AuthSession(accessToken: "at", refreshToken: "rt",
                        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
        }
        _ = try await repo.verifyOtp(email: "a@b.com", code: "123456")
        let r = mock.received.first
        #expect(r?.method == .post)
        #expect(r?.path == "/api/v1/auth/otp/verify")
        #expect(r?.requiresAuth == false)
        let body = r?.body
        #expect(body != nil)
        let decoded = try JSONDecoder().decode(OtpVerifyRequest.self, from: body!)
        #expect(decoded.email == "a@b.com")
        #expect(decoded.code == "123456")
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
            throw APIError.server(code: "invalid_otp", message: "bad")
        }
        do {
            _ = try await repo.verifyOtp(email: "a@b.com", code: "123456")
            Issue.record("expected throw")
        } catch let error as APIError {
            #expect(error.code == "invalid_otp")
        }
    }
}