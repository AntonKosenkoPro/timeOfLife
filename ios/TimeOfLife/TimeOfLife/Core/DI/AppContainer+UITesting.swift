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
        // The UI-testing graph pins a per-user test file (account-bound-store
        // spec shape): `lifio_<userId>.db` under a throwaway temp directory,
        // opened already bound so every screen reads one account's data. A
        // file failure must never crash the loop: fall back to an unbound
        // store (screens render empty) instead of `try!`.
        let localStore = (try? LocalStore(
            url: temporaryStoreURL(userID: "ui-test"),
            userID: "ui-test"
        )) ?? LocalStore()
        let timerService = TimerService(store: localStore)
        let repository = UITestingAuthRepository()
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: sessionCache,
            sessionStore: sessionStore
        )
        // An `APIClient` is required by the container but is never called in
        // this graph (the stub repository answers everything), so wire it
        // with no token/refresh/device-id hooks against the configured base
        // URL — the UI-testing stub never hits the real auth API.
        let apiClient = APIClient(baseURL: AppConfig.baseURL, session: .shared)
        let appleService = AppleSignInService()
        let catalog = RemoteCatalogRepository(client: apiClient)
        let undoBuffer = UndoBufferStore(store: localStore)
        let syncController = SyncController(
            store: localStore,
            remote: catalog,
            connectivity: connectivity
        ) { [weak sessionStore] in
            guard case let .signedIn(session) = sessionStore?.state else { return nil }
            return session.id
        }

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
            localStore: localStore,
            undoBuffer: undoBuffer,
            syncController: syncController,
            clientHolder: nil
        )

        seed(screen: screen, sessionStore: sessionStore, navigation: navigation)
        seedHistoryIfNeeded(screen: screen, localStore: localStore)
        return container
    }

    private static func temporaryStoreURL(userID: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: userID))
    }

    /// Places the app on a specific screen for inspection.
    private static func seed(
        screen: String,
        sessionStore: SessionStore,
        navigation: AppNavigationStack
    ) {
        // The stub graph never resolves the restore before the first frame:
        // clear the flag so `RootView` starts on gated content, not the
        // splash. NOTE: `RootView.task` still runs `restoreSession()`, which
        // re-latches `isRestoring = true` for one actor hop before its defer
        // clears it — a transient splash frame can still appear over stub
        // screens; gate the restore in the stub path if that matters.
        sessionStore.setRestoring(false)
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
            // `RootView` renders the app shell (Track) when the session is signed in.
            sessionStore.setSignedIn(CachedSession(
                id: "ui-test", email: "user@example.com", emailVerified: true
            ))
            navigation.path = []
        case "history":
            // History with committed entries across three day groups (fix-35
            // repro/spike harness): the shell opens on Track and the loop
            // taps the History tab. Entries carry no categories (fallback
            // icon rows) — the headers and totals are what is inspected.
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

    /// Kicks off History entry seeding for the `"history"` screen.
    /// Actor-isolated seeding runs before the first History load (enqueued
    /// at init, ahead of any appear-driven read).
    private static func seedHistoryIfNeeded(screen: String, localStore: LocalStore) {
        guard screen == "history" else { return }
        Task { await seedHistoryEntries(into: localStore) }
    }

    /// Seeds committed entries across three calendar days (today, yesterday,
    /// three days ago) for the History repro/spike harness. Deterministic
    /// relative to `now` so day labels always read Today / Yesterday /
    /// absolute. Failures are ignored: the harness degrades to an empty
    /// History rather than crashing the loop.
    private static func seedHistoryEntries(into store: LocalStore) async {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let dayStarts = [
            calendar.startOfDay(for: now),
            calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!,
            calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now))!,
        ]
        let texts = [
            "Morning run", "Deep work", "Code review", "Lunch break",
            "Design sync", "Inbox zero", "Gym session", "Reading",
            "Side project", "Evening walk",
        ]
        let dayCounts = [10, 6, 4]
        for (dayIndex, dayStart) in dayStarts.enumerated() {
            for i in 0..<dayCounts[dayIndex] {
                let start = calendar.date(
                    byAdding: .minute,
                    value: 8 * 60 + i * 47,
                    to: dayStart
                )!
                let minutes = 25 + (i * 13) % 65
                let entry = TimeEntry(
                    id: "uitest-h-\(dayIndex)-\(i)",
                    activityText: texts[(i + dayIndex * 3) % texts.count],
                    startedAt: start,
                    endedAt: calendar.date(byAdding: .minute, value: minutes, to: start),
                    durationSeconds: minutes * 60
                )
                _ = try? await store.createEntry(entry)
            }
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
#endif
