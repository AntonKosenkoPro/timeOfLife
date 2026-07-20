import Foundation
import SwiftUI

/// Composition root. Builds the real production graph and exposes the
/// objects views/view models need. Everything is injectable for tests.
@MainActor
final class AppContainer: ObservableObject {
    let baseURL: URL
    let apiClient: APIClient
    let keychain: KeychainStoring
    let sessionCache: SessionCache
    let repository: AuthRepository
    let sessionStore: SessionStore
    let navigation: AppNavigationStack
    let connectivity: Connectivity
    let themeManager: ThemeManager
    let authService: AuthService
    let timerService: TimerService

    init(
        baseURL: URL,
        apiClient: APIClient,
        keychain: KeychainStoring,
        sessionCache: SessionCache,
        repository: AuthRepository,
        sessionStore: SessionStore,
        navigation: AppNavigationStack,
        connectivity: Connectivity,
        themeManager: ThemeManager,
        authService: AuthService,
        timerService: TimerService
    ) {
        self.baseURL = baseURL
        self.apiClient = apiClient
        self.keychain = keychain
        self.sessionCache = sessionCache
        self.repository = repository
        self.sessionStore = sessionStore
        self.navigation = navigation
        self.connectivity = connectivity
        self.themeManager = themeManager
        self.authService = authService
        self.timerService = timerService
    }

    /// Default production graph wired against `AppConfig.baseURL`.
    static func production() -> AppContainer {
        let baseURL = AppConfig.baseURL
        let keychain = KeychainStore()
        let sessionCache = SessionCache()
        let sessionStore = SessionStore()
        let navigation = AppNavigationStack()
        let connectivity = NetworkMonitor()
        let themeManager = ThemeManager()
        let timerService = TimerService(
            store: LocalTimerStore(),
            repository: StubTimerRepository(),
            connectivity: connectivity
        )

        // The auth service must exist before the API client's refresh hook can
        // reference it. We create a placeholder client and rewire via a
        // closure that captures the service by the time it's called.
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

        let repository = RemoteAuthRepository(client: client)
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: sessionCache,
            sessionStore: sessionStore
        )
        clientHolder.service = authService

        return AppContainer(
            baseURL: baseURL,
            apiClient: client,
            keychain: keychain,
            sessionCache: sessionCache,
            repository: repository,
            sessionStore: sessionStore,
            navigation: navigation,
            connectivity: connectivity,
            themeManager: themeManager,
            authService: authService,
            timerService: timerService
        )
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
