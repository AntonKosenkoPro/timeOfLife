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
    var localStoreForCatalog: LocalStore?
    /// Single synchronization coordinator for the catalog. `nil` until a user
    /// signs in.
    var syncCoordinator: SyncCoordinator?
    /// Undo service for catalog deletions. `nil` until a user signs in.
    var undoService: UndoService?
    /// Seeder for default categories. `nil` until a user signs in.
    var seeder: Seeder?
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
