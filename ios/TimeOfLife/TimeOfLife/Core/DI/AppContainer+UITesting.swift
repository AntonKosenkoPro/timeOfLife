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
        // The UI graph is local-only. Keeping it offline prevents the empty
        // fake server from reconciling seeded/local records away after a save.
        let connectivity = MockConnectivity(connected: false)
        let timerService = TimerService(
            repository: StubTimerRepository(),
            connectivity: connectivity,
            legacyStore: LocalTimerStore()
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
            clientHolder: nil
        )

        if screen == "signedIn",
           let store = try? LocalStore(inMemory: true, seed: uiTestingSeed()) {
            _ = container.installCatalogGraph(
                localStore: store,
                catalogRepo: UITestingCatalogRepository(),
                entriesRepo: UITestingEntriesRepository(),
                accountID: "ui-test",
                ready: true)
        }

        seed(screen: screen, sessionStore: sessionStore, navigation: navigation)
        return container
    }

    /// Builds deterministic catalog data before SwiftUI renders the UI.
    private static func uiTestingSeed() -> LocalStoreSeed {
        let now = Date()
        let category = Category(
            id: "uitest-cat-1", name: "Work", icon: "briefcase",
            createdAt: now, updatedAt: now, sync: .adoptedClean())
        let activities = ["Reading", "Coding", "Designing"].enumerated().map { index, name in
            Activity(
                id: "uitest-act-\(index + 1)",
                name: name,
                notes: index == 0 ? "A sample activity" : nil,
                lastUsedAt: now.addingTimeInterval(TimeInterval(-index * 3600)),
                createdAt: now,
                updatedAt: now,
                categoryIds: index == 0 ? ["uitest-cat-1"] : [],
                sync: .adoptedClean())
        }
        let entry = Entry(
            id: "uitest-ent-1", activityId: "uitest-act-1",
            startedAt: now.addingTimeInterval(-1800),
            endedAt: now.addingTimeInterval(-1200),
            durationSeconds: 600,
            createdAt: now, updatedAt: now, sync: .adoptedClean())
        return LocalStoreSeed(
            categories: [category],
            activities: activities,
            entries: [entry])
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

/// No-network catalog remote used by the DEBUG UI graph. Local catalog data is
/// the source of truth for rendered smoke tests.
struct UITestingCatalogRepository: CatalogRemoteSending {
    func listCategories() async throws -> [CategoryDTO] { [] }

    func createCategory(_ request: CategoryCreateRequest) async throws -> CategoryDTO {
        CategoryDTO(
            id: request.id,
            name: request.name,
            icon: request.icon,
            createdAt: Date(),
            updatedAt: Date())
    }

    func updateCategory(id: String, request: CategoryUpdateRequest) async throws -> CategoryDTO {
        CategoryDTO(
            id: id,
            name: request.name ?? "Category",
            icon: request.icon ?? "tag",
            createdAt: Date(),
            updatedAt: request.updatedAt)
    }

    func deleteCategory(id: String) async throws {}

    func getCategory(id: String) async throws -> CategoryDTO {
        CatalogTestDTO.category(id: id)
    }

    func listActivities() async throws -> [ActivityDTO] { [] }

    func createActivity(_ request: ActivityCreateRequest) async throws -> ActivityDTO {
        ActivityDTO(
            id: request.id,
            name: request.name,
            notes: request.notes,
            lastUsedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            categories: [])
    }

    func updateActivity(id: String, request: ActivityUpdateRequest) async throws -> ActivityDTO {
        ActivityDTO(
            id: id,
            name: request.name ?? "Activity",
            notes: request.notes,
            lastUsedAt: nil,
            createdAt: Date(),
            updatedAt: request.updatedAt,
            categories: [])
    }

    func deleteActivity(id: String) async throws {}

    func getActivity(id: String) async throws -> ActivityDTO {
        ActivityDTO(
            id: id,
            name: "Activity",
            notes: nil,
            lastUsedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            categories: [])
    }
}

/// No-network entries remote used by the DEBUG UI graph.
struct UITestingEntriesRepository: EntriesRemoteSending {
    func listEntries(cursor: String?, limit: Int) async throws -> EntryListResponseDTO {
        EntryListResponseDTO(items: [], nextCursor: nil)
    }

    func listAllEntries() async throws -> [EntryDTO] { [] }

    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        EntryDTO(
            id: request.id,
            activityId: request.activityId,
            activityName: "Activity",
            startedAt: request.startedAt,
            endedAt: request.endedAt,
            durationSeconds: request.endedAt.map {
                $0.timeIntervalSince(request.startedAt)
            },
            createdAt: Date(),
            updatedAt: Date(),
            categories: [])
    }

    func updateEntry(id: String, request: EntryUpdateRequest) async throws -> EntryDTO {
        EntryDTO(
            id: id,
            activityId: "activity",
            activityName: "Activity",
            startedAt: request.startedAt ?? Date(),
            endedAt: request.endedAt,
            durationSeconds: nil,
            createdAt: Date(),
            updatedAt: request.updatedAt,
            categories: [])
    }

    func deleteEntry(id: String) async throws {}

    func getEntry(id: String) async throws -> EntryDTO {
        EntryDTO(
            id: id,
            activityId: "activity",
            activityName: "Activity",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            createdAt: Date(),
            updatedAt: Date(),
            categories: [])
    }
}

private enum CatalogTestDTO {
    static func category(id: String) -> CategoryDTO {
        CategoryDTO(
            id: id,
            name: "Category",
            icon: "tag",
            createdAt: Date(),
            updatedAt: Date())
    }
}
#endif
