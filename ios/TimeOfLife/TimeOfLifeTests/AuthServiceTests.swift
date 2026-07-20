import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("AuthService")
struct AuthServiceTests {

    private func makeService(
        initialTokens: [KeychainKey: String] = [:],
        cached: CachedSession? = nil
    ) -> (AuthService, FakeAuthRepository, InMemoryKeychainStore, SessionCache, SessionStore) {
        let repo = FakeAuthRepository()
        let keychain = InMemoryKeychainStore(initial: initialTokens)
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if let cached { cache.save(cached) }
        let store = SessionStore()
        let service = AuthService(
            repository: repo,
            keychain: keychain,
            cache: cache,
            sessionStore: store
        )
        return (service, repo, keychain, cache, store)
    }

    // MARK: - requestOTP

    @Test("requestOTP normalizes email, caches it, and writes no tokens on success")
    func requestOtpSuccess() async throws {
        let (service, repo, keychain, _, store) = makeService()

        try await service.requestOtp(email: "  Foo@Bar.com ")

        #expect(repo.calls == [.requestOtp(email: "foo@bar.com")])
        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(await keychain.string(for: .refreshToken) == nil)
        #expect(store.cachedEmail == "foo@bar.com")
    }

    @Test("requestOTP propagates network failure")
    func requestOtpNetworkFailure() async throws {
        let (service, repo, _, _, _) = makeService()
        repo.otpRequestError = APIError.offline

        do {
            try await service.requestOtp(email: "a@b.com")
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error == .offline)
        }
    }

    // MARK: - verifyOTP

    @Test("verifyOTP persists tokens and caches session on success")
    func verifyOtpSuccess() async throws {
        let (service, repo, keychain, cache, store) = makeService()

        try await service.verifyOtp(email: "a@b.com", code: "123456")

        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(await keychain.string(for: .accessToken) == "at")
        #expect(await keychain.string(for: .refreshToken) == "rt")
        #expect(cache.load()?.email == "a@b.com")
        #expect(
            store.state == .signedIn(
                CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
            )
        )
    }

    @Test("verifyOTP propagates invalid code error")
    func verifyOtpInvalidCode() async throws {
        let (service, repo, _, _, _) = makeService()
        repo.otpVerifyError = APIError.server(code: "invalid_otp", message: "Incorrect code. Try again.")

        do {
            try await service.verifyOtp(email: "a@b.com", code: "000000")
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "invalid_otp")
        }
    }

    @Test("verifyOTP propagates expired code error")
    func verifyOtpExpiredCode() async throws {
        let (service, repo, _, _, _) = makeService()
        repo.otpVerifyError = APIError.server(
            code: "otp_expired",
            message: "This code has expired. Request a new one."
        )

        do {
            try await service.verifyOtp(email: "a@b.com", code: "123456")
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "otp_expired")
        }
    }

    @Test("verifyOTP propagates attempts exceeded error")
    func verifyOtpAttemptsExceeded() async throws {
        let (service, repo, _, _, _) = makeService()
        repo.otpVerifyError = APIError.server(
            code: "otp_attempts_exceeded",
            message: "Too many attempts. Request a new code."
        )

        do {
            try await service.verifyOtp(email: "a@b.com", code: "123456")
            Issue.record("Expected error to be thrown")
        } catch let error as APIError {
            #expect(error.code == "otp_attempts_exceeded")
        }
    }

    // MARK: - logout

    @Test("logout clears local state even if server call fails")
    func logoutClearsLocal() async throws {
        let (service, repo, keychain, cache, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        )
        repo.logoutError = APIError.offline

        await service.logout()

        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(await keychain.string(for: .refreshToken) == nil)
        #expect(cache.load() == nil)
        #expect(store.state == .signedOut)
    }

    @Test("logout resets state to unauthenticated")
    func logoutResetsState() async throws {
        let (service, _, keychain, cache, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        )

        await service.logout()

        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(await keychain.string(for: .refreshToken) == nil)
        #expect(cache.load() == nil)
        #expect(store.state == .signedOut)
    }

    // MARK: - restoreSession

    @Test("restoreSession restores authenticated state when tokens are valid")
    func restoreSessionAuthenticated() async throws {
        let cached = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        let (service, repo, _, cache, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: cached
        )
        // me() succeeds by default

        await service.restoreSession()

        // Optimistically signed-in from cache, then /me confirms
        #expect(store.state == .signedIn(cached))
        #expect(cache.load() == cached)
        #expect(repo.calls.contains(.me))
    }

    @Test("restoreSession stays unauthenticated when no tokens exist")
    func restoreSessionNoTokens() async throws {
        let (service, _, _, _, store) = makeService()

        await service.restoreSession()

        #expect(store.state == .signedOut)
    }

    @Test("restoreSession keeps cached session on offline /me failure")
    func restoreOfflineKeepsCached() async throws {
        let cached = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        let (service, repo, _, cache, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: cached
        )
        repo.meError = APIError.offline

        await service.restoreSession()

        #expect(store.state == .signedIn(cached))
        #expect(cache.load() == cached)
    }

    @Test("restoreSession refreshes on 401 from /me")
    func restoreRefreshesOn401() async throws {
        let cached = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        let (service, repo, keychain, _, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: cached
        )
        repo.meError = APIError.unauthorized

        await service.restoreSession()

        // refreshResult rotates tokens to at2/rt2
        #expect(await keychain.string(for: .accessToken) == "at2")
        #expect(await keychain.string(for: .refreshToken) == "rt2")
        if case .signedIn(let s) = store.state {
            #expect(s.id == "u1")
        } else {
            Issue.record("Expected signed in state")
        }
    }

    @Test("restoreSession signs out when refresh also fails")
    func restoreSignsOutOnDoubleFailure() async throws {
        let cached = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        let (service, repo, keychain, _, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: cached
        )
        repo.meError = APIError.unauthorized
        repo.refreshError = APIError.server(code: "invalid_refresh", message: "expired")

        await service.restoreSession()

        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(store.state == .signedOut)
    }

    // MARK: - performRefresh

    @Test("performRefresh rotates tokens and returns new access token")
    func performRefresh() async throws {
        let (service, repo, keychain, _, _) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"]
        )

        let new = try await service.performRefresh()

        #expect(new == "at2")
        #expect(await keychain.string(for: .refreshToken) == "rt2")
        #expect(repo.calls == [.refresh(refreshToken: "rt")])
    }

    @Test("performRefresh throws unauthorized when no refresh token")
    func performRefreshNoToken() async throws {
        let (service, _, _, _, _) = makeService()

        do {
            _ = try await service.performRefresh()
            Issue.record("Expected unauthorized error")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
    }

    // MARK: - handleDeepLink (via verifyOtp with stored email)

    @Test("verifyOtp uses the email passed from deep link handler")
    func verifyOtpWithStoredEmail() async throws {
        let (service, repo, keychain, cache, store) = makeService()

        // Simulate: requestOtp was called first, caching the email
        try await service.requestOtp(email: "  User@Example.com ")
        #expect(store.cachedEmail == "user@example.com")

        // Then deep link triggers verifyOtp with the cached email
        try await service.verifyOtp(email: "user@example.com", code: "123456")

        #expect(repo.calls == [
            .requestOtp(email: "user@example.com"),
            .verifyOtp(email: "user@example.com", code: "123456"),
        ])
        #expect(await keychain.string(for: .accessToken) == "at")
        #expect(await keychain.string(for: .refreshToken) == "rt")
        #expect(cache.load()?.email == "user@example.com")
        #expect(
            store.state == .signedIn(
                CachedSession(id: "u1", email: "user@example.com", emailVerified: true)
            )
        )
    }
}
