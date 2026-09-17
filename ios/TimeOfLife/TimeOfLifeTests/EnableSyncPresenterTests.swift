import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("EnableSyncPresenter")
struct EnableSyncPresenterTests {

    private func makePresenter(
        initialTokens: [KeychainKey: String] = [:],
        cached: CachedSession? = nil
    ) -> (EnableSyncPresenter, SessionStore) {
        let repository = FakeAuthRepository()
        let keychain = InMemoryKeychainStore(initial: initialTokens)
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if let cached { cache.save(cached) }
        let store = SessionStore()
        let service = AuthService(
            repository: repository,
            keychain: keychain,
            cache: cache,
            sessionStore: store
        )
        return (EnableSyncPresenter(authService: service, sessionStore: store), store)
    }

    // MARK: - Enable Sync branching (1.2)

    @Test("restore-signs-in presents no sheet")
    func restoreSuccessNoSheet() async {
        let (presenter, store) = makePresenter(
            initialTokens: [
                .refreshToken: "rt",
                .accessToken: "at"
            ]
        )

        await presenter.enableSync()

        #expect(store.state != .signedOut)
        #expect(!presenter.isSheetPresented)
        #expect(!presenter.isRestoring)
    }

    @Test("restore-noop presents the sheet")
    func restoreNoopPresentsSheet() async {
        let (presenter, store) = makePresenter()

        await presenter.enableSync()

        #expect(store.state == .signedOut)
        #expect(presenter.isSheetPresented)
        #expect(!presenter.isRestoring)
    }

    @Test("already signed in is a no-op")
    func alreadySignedInNoOp() async {
        let (presenter, store) = makePresenter()
        store.setSignedIn(CachedSession(id: "u1", email: "a@b.com", emailVerified: true))

        await presenter.enableSync()

        #expect(store.state != .signedOut)
        #expect(!presenter.isSheetPresented)
    }

    // MARK: - Dismissal (2.2)

    @Test("sign-in flip clears a presented sheet")
    func signInFlipDismisses() async {
        let (presenter, store) = makePresenter()

        await presenter.enableSync()
        #expect(presenter.isSheetPresented)

        store.setSignedIn(CachedSession(id: "u1", email: "a@b.com", emailVerified: true))
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isSheetPresented)
    }

    @Test("cancel leaves the session untouched")
    func cancelLeavesSessionUntouched() async {
        let (presenter, store) = makePresenter()

        await presenter.enableSync()
        #expect(presenter.isSheetPresented)

        presenter.dismiss()

        #expect(!presenter.isSheetPresented)
        #expect(store.state == .signedOut)
    }
}
