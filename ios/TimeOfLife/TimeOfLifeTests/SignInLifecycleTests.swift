import Testing
import Foundation
@testable import TimeOfLife

/// Seed-before-reveal lifecycle (fix-track-empty-after-reinstall 1.2):
/// `RootView.beginSignIn` reveals only after `prepareAccountStore`
/// (open → commit → seed) succeeds, and activates sync after the
/// cancellation/session guards — the first paint already carries the seed,
/// so Track's first `load()` can never observe an empty category map.
/// These tests pin that seam across the success and failure paths.
@MainActor
@Suite("SignInLifecycle")
struct SignInLifecycleTests {

    // MARK: - Race-window documentation (passes before and after)

    @Test("a Track load racing the seed observes empty categories")
    func unseededLoadObservesEmptyCategories() async {
        // Documents the pre-fix race window: a fresh account file opened but
        // not yet seeded is what Track's first `load()` read when the shell
        // mounted before the seed landed (the reinstall empty-Track paint).
        // Post-fix the gate seeds before reveal, so this interleaving is
        // unreachable through `beginSignIn` — the test pins why the ordering
        // matters, not a reachable state.
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }
        _ = await container.openLocalStore(userID: userID)
        let vm = TrackViewModel(
            service: TimerService(store: container.localStore),
            connectivity: MockConnectivity(connected: true)
        )

        await vm.load()

        #expect(vm.categories.isEmpty, "unseeded file reads an empty category map")
        #expect(vm.recents.isEmpty)
        #expect(vm.errorMessage == nil, "bound-but-empty is not an error, just a race")
    }

    // MARK: - Prepare-before-reveal (slice 2.1, landed in this change)

    @Test("prepare binds and seeds a fresh account before reveal")
    func prepareBindsAndSeedsFreshAccount() async throws {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }

        let ready = await container.prepareAccountStore(userID: userID)

        #expect(ready)
        #expect(container.localStoreOpenError == nil)
        #expect(await container.localStore.boundUserID == userID)
        #expect(try await container.localStore.categoryStartersSeeded())
        #expect(try await container.localStore.categories().count == 7)
    }

    @Test("Track first load after prepare sees starter categories")
    func trackFirstLoadAfterPrepareSeesCategories() async {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }
        _ = await container.prepareAccountStore(userID: userID)
        let vm = TrackViewModel(
            service: TimerService(store: container.localStore),
            connectivity: MockConnectivity(connected: true)
        )

        await vm.load()

        #expect(vm.categories.count == 7, "first paint after prepare carries the seed")
        #expect(vm.errorMessage == nil)
    }

    @Test("prepare reports failure without revealing on invalid user")
    func prepareInvalidUserReportsWithoutRevealing() async {
        let container = makeContainer()

        let ready = await container.prepareAccountStore(userID: "not valid!!")

        #expect(!ready, "no reveal on failed prepare")
        #expect(container.localStoreOpenError != nil)
        #expect(await container.localStore.boundUserID == nil)
    }

    @Test("prepare surfaces seed failure without revealing")
    func prepareSeedFailureSurfacesWithoutRevealing() async {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }

        // Six names instead of seven: the seed throws invalidNameCount.
        let ready = await container.prepareAccountStore(
            userID: userID,
            seedNames: Array(String.starterCategoryNames.prefix(6))
        )

        #expect(!ready, "no reveal when the seed fails")
        #expect(container.localStoreOpenError != nil)
    }

    @Test("prepare never activates sync (activation stays a post-reveal decision)")
    func prepareLeavesSyncInactive() async {
        // Pins that preparation itself never touches sync: open/commit/seed
        // are local-file-only work, so `prepareAccountStore` cannot leave a
        // cycle in flight even if the caller is cancelled mid-prepare. The
        // sign-out-mid-prepare guards are view-layer (`RootView.beginSignIn`)
        // and are not exercised by this unit test.
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }

        _ = await container.prepareAccountStore(userID: userID)

        #expect(container.syncController.status == .inactive)
        #expect(!container.syncController.isCycleLive)
    }

    // MARK: - Helpers (mirroring ComplexitySliceTests)

    private func uniqueUserID() -> String { "sl-" + UUID().uuidString.lowercased() }

    private func removeAccountFile(userID: String) {
        let url = LocalStore.databaseURL(userID: userID)
        try? FileManager.default.removeItem(at: url)
        for ext in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ext))
        }
    }

    private func makeContainer() -> AppContainer {
        let url = URL(string: "https://example.com")!
        let repository = FakeAuthRepository()
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sessionStore = SessionStore()
        let localStore = LocalStore()
        let connectivity = MockConnectivity(connected: true)
        let authService = AuthService(
            repository: repository, keychain: keychain, cache: cache, sessionStore: sessionStore
        )
        return AppContainer(
            baseURL: url,
            apiClient: APIClient(baseURL: url, session: .shared),
            keychain: keychain,
            sessionCache: cache,
            repository: repository,
            sessionStore: sessionStore,
            navigation: AppNavigationStack(),
            connectivity: connectivity,
            authService: authService,
            appleService: AppleSignInService(),
            timerService: TimerService(store: localStore),
            localStore: localStore,
            undoBuffer: UndoBufferStore(store: localStore),
            syncController: SyncController(
                store: localStore,
                remote: MockCatalogRepository(),
                connectivity: connectivity
            ) { nil }
        )
    }
}
