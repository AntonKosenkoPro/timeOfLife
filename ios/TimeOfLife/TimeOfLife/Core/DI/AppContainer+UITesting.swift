#if DEBUG
import Foundation
import SwiftUI

/// DEBUG-only composition root for the UI-feedback loop.
///
/// The app is launched with `UITEST_SCREEN=<screen>` (see `TimeOfLifeApp`),
/// which routes here instead of `.production()`. This factory wires a stub
/// backend and seeds `SessionStore` + `AppNavigationStack` so the agent can
/// inspect any screen deterministically — no real network, no email, no OTP.
///
/// Never ships: the whole file is `#if DEBUG`. Release builds call
/// `.production()` only.
extension AppContainer {
    /// Builds the deterministic UI-testing graph and seeds it to `screen`.
    static func uiTesting(screen: String) -> AppContainer {
        let keychain = InMemoryKeychainStore()
        let sessionCache = SessionCache()
        let sessionStore = SessionStore()
        let navigation = AppNavigationStack()
        let connectivity = MockConnectivity(connected: true)
        let entriesRepository = UITestingEntriesRepository()
        let timerService = TimerService(
            store: LocalTimerStore(),
            repository: entriesRepository,
            connectivity: connectivity
        )
        let repository = UITestingAuthRepository()
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: sessionCache,
            sessionStore: sessionStore
        )
        // An `APIClient` is required by the container but is never called in
        // this graph (the stub repository answers everything), so wire it
        // with no token/refresh hooks against the configured base URL.
        let apiClient = APIClient(baseURL: AppConfig.baseURL, session: .shared)
        let appleService = AppleSignInService()

        let catalog = makeUITestingCatalogGraph(connectivity: connectivity)

        let container = AppContainer(
            baseURL: AppConfig.baseURL,
            apiClient: apiClient,
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
            clientHolder: nil
        )

        seed(screen: screen, sessionStore: sessionStore, navigation: navigation)
        return container
    }

    /// Deterministic, offline catalog graph for UI testing: a temp-directory
    /// store/queue + a stub repository so the catalog runs without a network.
    private static func makeUITestingCatalogGraph(connectivity: Connectivity)
    -> (store: CatalogStore, repository: CatalogRepository,
        queue: SyncQueue, undoBuffer: UndoBuffer, service: CatalogService) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TimeOfLifeUITesting", isDirectory: true)
        let store = CatalogStore(directory: tempDir)
        let repository = UITestingCatalogRepository()
        let queue = SyncQueue(url: tempDir)
        let undoBuffer = UndoBuffer()
        let service = CatalogService(
            store: store,
            repository: repository,
            syncQueue: queue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        return (store, repository, queue, undoBuffer, service)
    }

    /// Places the app on a specific screen for inspection.
    private static func seed(
        screen: String,
        sessionStore: SessionStore,
        navigation: AppNavigationStack
    ) {
        switch screen {
        case "emailEntry":
            // Auth flow pushed to the email entry screen.
            sessionStore.setSignedOut()
            navigation.path = [.emailEntry]
        case "otpEntry":
            // Auth flow pushed to the OTP screen.
            sessionStore.setSignedOut()
            navigation.path = [.otpEntry(email: "user@example.com")]
        case "signedIn":
            // `RootView` renders `TimerView` when the session is signed in.
            sessionStore.setSignedIn(CachedSession(
                id: "ui-test", email: "user@example.com", emailVerified: true
            ))
            navigation.path = []
        default:
            // "welcome" (and any unknown value) → auth-flow root.
            sessionStore.setSignedOut()
            navigation.path = []
        }
    }
}

/// Stub `AuthRepository` for the UI-feedback loop. Returns deterministic,
/// canned sessions so the agent can drive the flow (request OTP → enter code
/// → verify) without a network or real email. DEBUG-only; never ships.
///
/// Stateless `Sendable` struct — safe for the `@MainActor` container to hold.
struct UITestingAuthRepository: AuthRepository {
    private static let user = UserDTO(
        id: "ui-test", email: "user@example.com", emailVerified: true
    )

    private static func session(for email: String) -> AuthSession {
        AuthSession(
            accessToken: "at-ui",
            refreshToken: "rt-ui",
            user: UserDTO(id: "ui-test", email: email, emailVerified: true)
        )
    }

    func requestOtp(email: String) async throws {}

    func verifyOtp(email: String, code: String) async throws -> AuthSession {
        Self.session(for: email)
    }

    func appleSignIn(identityToken: String) async throws -> AuthSession {
        Self.session(for: "apple@privaterelay.appleid.com")
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        Self.session(for: "user@example.com")
    }

    func logout() async throws {}

    func me() async throws -> UserDTO { Self.user }
}

/// Stub `CatalogRepository` for the UI-feedback loop. Returns deterministic,
/// empty results so catalog-driven screens render deterministically without a
/// network. DEBUG-only; never ships. Stateless `Sendable` struct.
struct UITestingCatalogRepository: CatalogRepository {
    /// Fixed reference date for deterministic stub responses.
    private static let stubDate = Date(timeIntervalSinceReferenceDate: 0)

    func listActivities(query: String?) async throws -> [Activity] { [] }
    func getActivity(_ id: UUID) async throws -> Activity {
        Activity(id: id, name: "Activity", color: .gray, icon: .clock, notes: nil,
                 lastUsedAt: nil, categoryIds: [],
                 createdAt: Self.stubDate, updatedAt: Self.stubDate)
    }
    func createActivity(_ activity: Activity) async throws -> Activity { activity }
    func updateActivity(_ activity: Activity) async throws -> Activity { activity }
    func deleteActivity(_ id: UUID) async throws {}
    func listCategories() async throws -> [Category] { [] }
    func getCategory(_ id: UUID) async throws -> Category {
        Category(id: id, name: "Category", color: .gray,
                 createdAt: Self.stubDate, updatedAt: Self.stubDate)
    }
    func createCategory(_ category: Category) async throws -> Category { category }
    func updateCategory(_ category: Category) async throws -> Category { category }
    func deleteCategory(_ id: UUID) async throws {}
}

/// Stub `EntriesRepository` for the UI-feedback loop. Returns deterministic,
/// no-op results so the timer screen renders without a network. DEBUG-only;
/// never ships. Stateless `Sendable` struct.
struct UITestingEntriesRepository: EntriesRepository {
    func create(_ entry: TimeEntry) async throws {}
    func stop(id: UUID, endedAt: Date, updatedAt: Date) async throws {}
    func delete(id: UUID) async throws {}
    func get(id: UUID) async throws -> EntryDTO {
        EntryDTO(
            id: id,
            activityId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }
}
#endif
