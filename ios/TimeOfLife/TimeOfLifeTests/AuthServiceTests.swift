import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("AuthService")
struct AuthServiceTests {
    private func makeService(initialTokens: [KeychainKey: String] = [:],
                              cached: CachedSession? = nil) -> (AuthService, FakeAuthRepository, InMemoryKeychainStore, SessionCache, SessionStore) {
        let repo = FakeAuthRepository()
        let keychain = InMemoryKeychainStore(initial: initialTokens)
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if let cached { cache.save(cached) }
        let store = SessionStore()
        let service = AuthService(repository: repo, keychain: keychain, cache: cache, sessionStore: store)
        return (service, repo, keychain, cache, store)
    }

    @Test("signUp caches email and writes no tokens")
    func signUp() async throws {
        let (service, repo, keychain, _, store) = makeService()
        try await service.signUp(email: "  Foo@Bar.com ", password: "abcd1234")
        #expect(repo.calls == [.signup(email: "foo@bar.com", password: "abcd1234")])
        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(await keychain.string(for: .refreshToken) == nil)
        #expect(store.cachedEmail == "foo@bar.com")
    }

    @Test("signIn writes access+refresh tokens and caches session")
    func signIn() async throws {
        let (service, _, keychain, cache, store) = makeService()
        try await service.signIn(email: "a@b.com", password: "abcd1234")
        #expect(await keychain.string(for: .accessToken) == "at")
        #expect(await keychain.string(for: .refreshToken) == "rt")
        #expect(cache.load()?.email == "a@b.com")
        #expect(store.state == .signedIn(CachedSession(id: "u1", email: "a@b.com", emailVerified: true)))
    }

    @Test("verifyEmail persists session")
    func verifyEmail() async throws {
        let (service, _, keychain, _, store) = makeService()
        try await service.verifyEmail(token: "tok")
        #expect(await keychain.string(for: .accessToken) == "at")
        #expect(await keychain.string(for: .refreshToken) == "rt")
        if case .signedIn(let s) = store.state {
            #expect(s.emailVerified == true)
        } else {
            Issue.record("expected signed in")
        }
    }

    @Test("logout clears local state even if server call fails")
    func logoutClearsLocal() async throws {
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

    @Test("restoreSession keeps cached session on offline /me failure")
    func restoreOfflineKeepsCached() async throws {
        let cached = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        let (service, repo, _, cache, store) = makeService(
            initialTokens: [.accessToken: "at", .refreshToken: "rt"],
            cached: cached
        )
        repo.meError = APIError.offline
        await service.restoreSession()
        // Optimistically signed-in from cache.
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
        // refreshResult rotates tokens to at2/rt2.
        #expect(await keychain.string(for: .accessToken) == "at2")
        #expect(await keychain.string(for: .refreshToken) == "rt2")
        if case .signedIn(let s) = store.state {
            #expect(s.id == "u1")
        } else {
            Issue.record("expected signed in")
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
        repo.refreshError = APIError.invalidRefreshAsServer()
        await service.restoreSession()
        #expect(await keychain.string(for: .accessToken) == nil)
        #expect(store.state == .signedOut)
    }

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
}

private extension APIError {
    static func invalidRefreshAsServer() -> APIError {
        .server(code: "invalid_refresh", message: "expired")
    }
}