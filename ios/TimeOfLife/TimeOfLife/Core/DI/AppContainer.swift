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
    let catalogStore: CatalogStore
    let catalogRepository: CatalogRepository
    let syncQueue: SyncQueue
    let undoBuffer: UndoBuffer
    let catalogService: CatalogService
    let catalogSeeder: CatalogSeeder
    let activityEntryCounter: ActivityEntryCounting
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
        catalogStore: CatalogStore,
        catalogRepository: CatalogRepository,
        syncQueue: SyncQueue,
        undoBuffer: UndoBuffer,
        catalogService: CatalogService,
        catalogSeeder: CatalogSeeder,
        activityEntryCounter: ActivityEntryCounting,
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
        self.catalogStore = catalogStore
        self.catalogRepository = catalogRepository
        self.syncQueue = syncQueue
        self.undoBuffer = undoBuffer
        self.catalogService = catalogService
        self.catalogSeeder = catalogSeeder
        self.activityEntryCounter = activityEntryCounter
        self.clientHolder = clientHolder
    }

    static func production() -> AppContainer {
        let baseURL = AppConfig.baseURL
        let keychain = KeychainStore()
        let sessionCache = SessionCache()
        let sessionStore = SessionStore()
        let navigation = AppNavigationStack()
        let connectivity = NetworkMonitor()
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
        let entriesRepository = RemoteEntriesRepository(client: client)
        let timerService = TimerService(
            store: LocalTimerStore(),
            repository: entriesRepository,
            connectivity: connectivity
        )
        let catalog = makeCatalogGraph(client: client, connectivity: connectivity, entryStore: timerService.store, entriesRepository: entriesRepository)
        wireCatalogSync(service: catalog.service, timerService: timerService)
        wireLogoutCancelRetry(authService: authService, timerService: timerService)
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
            catalogStore: catalog.store,
            catalogRepository: catalog.repository,
            syncQueue: catalog.queue,
            undoBuffer: catalog.undoBuffer,
            catalogService: catalog.service,
            catalogSeeder: CatalogSeeder(repository: catalog.repository, service: catalog.service, sessionCache: sessionCache),
            activityEntryCounter: TimerStoreActivityEntryCounter(store: timerService.store),
            clientHolder: clientHolder
        )
    }

    private static func makeCatalogGraph(
        client: APIClient,
        connectivity: Connectivity,
        entryStore: TimerStoring,
        entriesRepository: EntriesRepository
    ) -> (store: CatalogStore, repository: CatalogRepository,
          queue: SyncQueue, undoBuffer: UndoBuffer, service: CatalogService) {
        let store = CatalogStore()
        let repository = RemoteCatalogRepository(client: client)
        let queue = SyncQueue()
        let undoBuffer = UndoBuffer()
        let service = CatalogService(
            store: store,
            repository: repository,
            syncQueue: queue,
            undoBuffer: undoBuffer,
            connectivity: connectivity,
            entryStore: entryStore,
            entriesRepository: entriesRepository
        )
        return (store, repository, queue, undoBuffer, service)
    }

    private static func wireCatalogSync(service: CatalogService, timerService: TimerService) {
        service.onSyncCompleted = {
            try? await timerService.syncUnsyncedEntries()
        }
    }

    /// Cancels TimerService retries on logout so the app stops hammering
    /// the backend without a token.
    private static func wireLogoutCancelRetry(authService: AuthService, timerService: TimerService) {
        authService.onLogout = { [weak timerService] in
            timerService?.cancelRetry()
        }
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
