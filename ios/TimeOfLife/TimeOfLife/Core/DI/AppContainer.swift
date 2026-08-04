import Foundation
import SwiftUI

/// Composition root. Builds the real production graph and exposes the
/// objects views/view models need. Everything is injectable for tests.
@MainActor
final class AppContainer: ObservableObject {
    private let baseURL: URL
    private let apiClient: APIClient
    private let keychain: KeychainStoring
    private let sessionCache: SessionCache
    private let repository: AuthRepository
    let sessionStore: SessionStore
    let navigation: AppNavigationStack
    let connectivity: Connectivity
    let authService: AuthService
    let appleService: AppleSignInService
    let timerService: TimerService
    /// Per-account local store for the catalog (GRDB). `nil` until a user
    /// signs in. Views use `localStoreForCatalog` (force-unwrap) after
    /// sign-in.
    private(set) var localStoreForCatalog: LocalStore?
    /// Single synchronization coordinator for the catalog. `nil` until a user
    /// signs in.
    private(set) var syncCoordinator: SyncCoordinator?
    /// Undo service for catalog deletions. `nil` until a user signs in.
    private(set) var undoService: UndoService?
    /// Seeder for default categories. `nil` until a user signs in.
    private(set) var seeder: Seeder?
    /// `true` once the per-account catalog graph is open and ready. Views
    /// observing the container re-render when this flips, so a screen pushed
    /// while the DB is still opening (e.g. Manage Activities) upgrades from
    /// `EmptyView` to the real view without user action.
    @Published private(set) var isCatalogReady = false
    private(set) var activeAccountID: String?
    /// Strong reference to the holder that wires the API client's refresh hook
    /// back to `authService`. If this were not retained, the holder would
    /// deallocate after `production()` returns and token refresh would fail.
    private let clientHolder: APIClientHolder?

    init(
        baseURL: URL,
        apiClient: APIClient,
        keychain: KeychainStoring,
        sessionCache: SessionCache,
        repository: AuthRepository,
        sessionStore: SessionStore,
        navigation: AppNavigationStack,
        connectivity: Connectivity,
        authService: AuthService,
        appleService: AppleSignInService,
        timerService: TimerService,
        clientHolder: APIClientHolder? = nil
    ) {
        self.baseURL = baseURL
        self.apiClient = apiClient
        self.keychain = keychain
        self.sessionCache = sessionCache
        self.repository = repository
        self.sessionStore = sessionStore
        self.navigation = navigation
        self.connectivity = connectivity
        self.authService = authService
        self.appleService = appleService
        self.timerService = timerService
        self.clientHolder = clientHolder
    }

    // MARK: - Account lifecycle (per-user database)

    /// Opens the per-account GRDB database, wires the catalog graph, and
    /// triggers the initial sync + seeding. Called when the session flips to
    /// signed-in (sign-in, cold restore). Replaces any previously open account.
    func openAccount(userID: String) async {
        if activeAccountID == userID {
            return
        }

        // Account switch: close the previous DB and cancel its sync first.
        await closeAccount()

        do {
            let url = try AccountDatabasePath.databaseURL(forUserUUID: userID)
            let store = try LocalStore(databaseURL: url)
            let catalogRepo = RemoteCatalogRepository(client: apiClient)
            let entriesRepo = RemoteEntriesRepository(client: apiClient)
            let (coordinator, seederService) = installCatalogGraph(
                localStore: store,
                catalogRepo: catalogRepo,
                entriesRepo: entriesRepo,
                accountID: userID,
                ready: false)

            // Bootstrap: outbound sync → initial pull → seed → sync seeds.
            await coordinator.sync()
            await seederService.seedIfNeeded()

            // Mark the graph ready only after everything is open — views
            // pushed early (e.g. Manage Activities while the DB opens) flip
            // from EmptyView to the real screen when this publishes.
            isCatalogReady = true
        } catch {
            // If the account database can't be opened, the catalog graph stays
            // nil (views degrade to EmptyView) but auth keeps working.
            await closeAccount()
        }
    }

    /// Installs a catalog graph without performing network bootstrap. The
    /// deterministic DEBUG UI graph uses this with in-memory storage and
    /// no-op remote repositories.
    @discardableResult
    func installCatalogGraph(
        localStore: LocalStore,
        catalogRepo: CatalogRemoteSending,
        entriesRepo: EntriesRemoteSending,
        accountID: String,
        ready: Bool
    ) -> (SyncCoordinator, Seeder) {
        let coordinator = SyncCoordinator(
            localStore: localStore,
            catalogRepo: catalogRepo,
            entriesRepo: entriesRepo,
            connectivity: connectivity)
        let undo = UndoService(
            localStore: localStore,
            syncCoordinator: coordinator)
        let seederService = Seeder(
            localStore: localStore,
            syncCoordinator: coordinator)

        localStoreForCatalog = localStore
        syncCoordinator = coordinator
        undoService = undo
        seeder = seederService
        activeAccountID = accountID
        timerService.attachCatalog(
            localStore: localStore,
            syncCoordinator: coordinator)
        isCatalogReady = ready
        return (coordinator, seederService)
    }

    /// Closes the per-account database and cancels its sync. Called on logout
    /// and before opening another account's database.
    func closeAccount() async {
        let coordinator = syncCoordinator
        await coordinator?.cancelSync()
        let store = localStoreForCatalog
        isCatalogReady = false
        activeAccountID = nil
        localStoreForCatalog = nil
        undoService = nil
        seeder = nil
        timerService.detachCatalog()
        // Explicitly close the connection so a same-user re-login cannot run
        // two queues on the same file. After close, the store is unusable and
        // must be dropped — it is replaced by the next openAccount.
        await store?.close()
    }

    /// Opens the account database for the current cached session, if any.
    /// Called from `RootView.task` after `restoreSession()`.
    func openAccountForCurrentSession() async {
        guard let session = sessionStore.currentSession else { return }
        await openAccount(userID: session.id)
    }

    /// Default production graph wired against `AppConfig.baseURL`.
    static func production() -> AppContainer {
        let baseURL = AppConfig.baseURL
        let keychain = KeychainStore()
        let sessionCache = SessionCache()
        let sessionStore = SessionStore()
        let navigation = AppNavigationStack()
        let connectivity = NetworkMonitor()
        let timerService = TimerService(
            repository: StubTimerRepository(),
            connectivity: connectivity,
            legacyStore: LocalTimerStore()
        )

        let (client, clientHolder) = makeAuthClient(baseURL: baseURL, keychain: keychain)
        let repository = RemoteAuthRepository(client: client)
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: sessionCache,
            sessionStore: sessionStore
        )
        clientHolder.service = authService

        let appleService = AppleSignInService()

        return AppContainer(
            baseURL: baseURL,
            apiClient: client,
            keychain: keychain,
            sessionCache: sessionCache,
            repository: repository,
            sessionStore: sessionStore,
            navigation: navigation,
            connectivity: connectivity,
            authService: authService,
            appleService: appleService,
            timerService: timerService,
            clientHolder: clientHolder
        )
    }

    /// Builds the API client and the back-reference holder used to break the
    /// auth-service / API-client initialization cycle. Kept separate so the
    /// production factory stays within the linter's function-body limit.
    private static func makeAuthClient(
        baseURL: URL,
        keychain: KeychainStoring
    ) -> (APIClient, APIClientHolder) {
        let clientHolder = APIClientHolder()
        let client = APIClient(
            baseURL: baseURL,
            session: URLSession.shared,
            accessTokenProvider: { [weak keychain] () async -> String? in
                await keychain?.string(for: .accessToken)
            },
            refreshHandler: { [weak clientHolder] () async throws -> String in
                guard let service = await clientHolder?.service else {
                    throw APIError.unauthorized
                }
                return try await service.performRefresh()
            }
        )
        clientHolder.client = client
        return (client, clientHolder)
    }
}

/// Holds a back-reference so the `APIClient`'s refresh closure can reach the
/// `AuthService` once it's constructed (breaks the init cycle).
@MainActor
final class APIClientHolder {
    weak var service: AuthService?
    var client: APIClient?
    init() {}
}
