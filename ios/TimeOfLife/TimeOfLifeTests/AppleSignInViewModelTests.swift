import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("EmailEntryViewModel — Sign in with Apple")
struct AppleSignInViewModelTests {

    private func makeService(
        repo: FakeAuthRepository = FakeAuthRepository()
    ) -> (AuthService, FakeAuthRepository, Connectivity, SessionStore) {
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = SessionStore()
        let service = AuthService(
            repository: repo,
            keychain: keychain,
            cache: cache,
            sessionStore: store
        )
        return (service, repo, Connectivity(), store)
    }

    private func makeAppleVM(
        service: AuthService,
        conn: Connectivity,
        provider: FakeAppleAuthorizationProvider = FakeAppleAuthorizationProvider()
    ) -> (EmailEntryViewModel, FakeAppleAuthorizationProvider) {
        let appleService = AppleSignInService(provider: provider)
        let vm = EmailEntryViewModel(service: service, connectivity: conn, appleService: appleService)
        return (vm, provider)
    }

    @Test("Apple sign-in success exchanges token and signs in")
    func appleSignInSuccess() async throws {
        let (service, repo, conn, store) = makeService()
        let (vm, _) = makeAppleVM(service: service, conn: conn)

        await vm.signInWithApple()

        #expect(repo.calls == [.appleSignIn(identityToken: "id-token")])
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
        if case .signedIn(let session) = store.state {
            #expect(session.email == "apple@privaterelay.appleid.com")
        } else {
            Issue.record("expected signed-in state after Apple sign-in")
        }
    }

    @Test("Apple sign-in offline shows error and does not call backend")
    func appleSignInOffline() async throws {
        let (service, repo, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let (vm, _) = makeAppleVM(service: service, conn: conn)

        await vm.signInWithApple()

        #expect(repo.calls.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("Apple sign-in canceled is silent")
    func appleSignInCanceled() async throws {
        let (service, repo, conn, _) = makeService()
        let provider = FakeAppleAuthorizationProvider()
        provider.error = AppleSignInError.canceled
        let (vm, _) = makeAppleVM(service: service, conn: conn, provider: provider)

        await vm.signInWithApple()

        #expect(repo.calls.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("Apple provider failure shows apple error")
    func appleSignInProviderFailed() async throws {
        let (service, repo, conn, _) = makeService()
        let provider = FakeAppleAuthorizationProvider()
        provider.error = AppleSignInError.failed("boom")
        let (vm, _) = makeAppleVM(service: service, conn: conn, provider: provider)

        await vm.signInWithApple()

        #expect(repo.calls.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("Apple backend error shows API error message")
    func appleSignInBackendError() async throws {
        let repo = FakeAuthRepository()
        repo.appleSignInError = APIError.server(code: "invalid_apple_token", message: "Invalid Apple identity token")
        let (service, _, conn, _) = makeService(repo: repo)
        let (vm, _) = makeAppleVM(service: service, conn: conn)

        await vm.signInWithApple()

        #expect(vm.errorMessage != nil)
    }
}
