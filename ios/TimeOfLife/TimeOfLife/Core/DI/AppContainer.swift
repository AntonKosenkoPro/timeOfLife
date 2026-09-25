import Foundation
import SwiftUI

/// Composition root. Builds the real production graph and exposes the
/// objects views/view models need. Everything is injectable for tests.
///
/// The local store is account-bound (account-bound-store spec): it starts
/// UNBOUND and binds to the signed-in account's `lifio_<userId>.db` file.
/// `TimerService`, `UndoBufferStore`, and `SyncController` all hold the same
/// `LocalStore` actor instance, so every view/feature resolves the ACTIVE
/// account's data through `container.localStore` — the accessor shape is
/// stable across account changes (no service-graph rebuild needed).
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
    /// The active account's local store. UNBOUND until `openLocalStore()`
    /// runs on sign-in/restored session; before that every tracker operation
    /// fails with `LocalStore.LocalStoreError.notBound`.
    let localStore: LocalStore
    let undoBuffer: UndoBufferStore
    let syncController: SyncController
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
        localStore: LocalStore,
        undoBuffer: UndoBufferStore,
        syncController: SyncController,
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
        self.localStore = localStore
        self.undoBuffer = undoBuffer
        self.syncController = syncController
        self.clientHolder = clientHolder
    }

    /// Default production graph wired against `AppConfig.baseURL`. The local
    /// store is built unbound; call `openLocalStore(userID:)` once the
    /// session resolves (restore on launch, verify/apple on login) and
    /// `closeLocalStore()` on sign-out — account-bound-store spec.
    static func production() -> AppContainer {
        let baseURL = AppConfig.baseURL
        let keychain = KeychainStore()
        let sessionCache = SessionCache()
        let sessionStore = SessionStore()
        let navigation = AppNavigationStack()
        let connectivity = NetworkMonitor()
        let localStore = LocalStore()
        let timerService = TimerService(store: localStore)

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
        let catalog = RemoteCatalogRepository(client: client)
        let undoBuffer = UndoBufferStore(store: localStore)
        let syncController = SyncController(
            store: localStore,
            remote: catalog,
            connectivity: connectivity
        ) { [weak sessionStore] in
            // The same-account guard reads the session user at guard time:
            // the session's `userId` must match the account `activate()`
            // bound, or the cycle is refused/aborted (sync-client spec).
            guard case let .signedIn(session) = sessionStore?.state else { return nil }
            return session.id
        }

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
            localStore: localStore,
            undoBuffer: undoBuffer,
            syncController: syncController,
            clientHolder: clientHolder
        )
    }

    // MARK: - Account-bound store lifecycle (account-bound-store spec)

    /// Binds the local store to the signed-in account: opens (creating if
    /// needed) `lifio_<userId>.db` in the App Group. Called by the signed-in
    /// path in `RootView` — restore-on-launch and both sign-in flows — and
    /// awaited before any store operation (undo commitAll, seeding, first
    /// sync cycle) touches the file.
    func openLocalStore(userID: String) async {
        do {
            try await localStore.openAccount(userID: userID)
        } catch {
            // Binding failure (invalid id, cross-account file mismatch)
            // is an integrity failure — fail fast rather than silently
            // operating on the wrong file.
            fatalError("LocalStore account binding failed: \(error)")
        }
    }

    /// Closes the active account file and keeps it on disk (logout keeps all
    /// files: dirty outbox + running timer draft stay in the dormant file).
    /// Called on the signed-out path in `RootView`.
    func closeLocalStore() async {
        await localStore.closeAccount()
    }

    /// Deletes ONLY the active account's database file (explicit per-account
    /// Erase in Profile; never a side effect of logout/switch/revoke). The
    /// store ends unbound; the caller clears the session artifacts.
    func eraseLocalData() async {
        await localStore.eraseAll()
    }

    /// Builds the API client and the back-reference holder used to break the
    /// auth-service / API-client initialization cycle. Kept separate so the
    /// production factory stays within the linter's function-body limit.
    private static func makeAuthClient(
        baseURL: URL,
        keychain: KeychainStoring
    ) -> (APIClient, APIClientHolder) {
        let clientHolder = APIClientHolder()
        let deviceIdentity = DeviceIdentityStore(keychain: keychain)
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
            },
            // Every session-carrying auth request must carry `X-Device-Id`
            // (device-sessions spec); the backend rejects requests without it.
            deviceIdProvider: { [deviceIdentity] () async -> String in
                await deviceIdentity.current()
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
