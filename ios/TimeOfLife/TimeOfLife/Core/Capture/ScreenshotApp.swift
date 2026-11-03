#if SCREENSHOT_CAPTURE
@preconcurrency import ActivityKit
import Foundation

import LifioLiveActivityCore

/// Capture-only composition root (screenshot-capture design §1–§4).
///
/// Strict isolation: ephemeral in-memory credentials, an isolated session
/// directory (never the production App Group), sync NEVER activated, no
/// network/auth/sync calls, crash reporting inert (empty DSN in the
/// Screenshot xcconfig). Fixture writes go through `LocalStore` only.
/// Absent from shipping builds.
@MainActor
enum ScreenshotApp {
    /// Fictional capture identity (review 2.3.9: never real-person data).
    static let fixtureEmail = "screenshot-pilot@lifio.example"

    static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ScreenshotRequestError(code: "session-unavailable", detail: "No documents directory.")
        }
        return url
    }

    /// Applies the request locale to this process BEFORE any view model reads
    /// `Locale.current`.
    ///
    /// `UserDefaults` alone cannot move already-running chrome: `Bundle.main`
    /// localization and `Locale.current` are resolved at launch, so a
    /// post-launch write leaves the current run on the previous run's
    /// language (a `ru` request rendered English chrome, `zh-Hans` Russian).
    /// The `ScreenshotLocale` override below resolves chrome from the
    /// request's `.lproj` in-process, in the same launch; the defaults writes
    /// stay for ambient readers and the next launch's defaults.
    ///
    /// The prior defaults are snapshotted first (see
    /// `ScreenshotCleanup.recordPriorDefaultsIfNeeded`): the Screenshot
    /// build shares its standard domain across launches on one simulator,
    /// and without a restore the container keeps the last capture locale
    /// after the run.
    static func applyProcessLocale(_ request: ScreenshotCaptureRequest) {
        ScreenshotCleanup.recordPriorDefaultsIfNeeded()
        UserDefaults.standard.set([request.localeIdentifier], forKey: "AppleLanguages")
        UserDefaults.standard.set(request.appleLocaleIdentifier, forKey: "AppleLocale")
        setenv("TZ", request.timeZone.identifier, 1)
        ScreenshotLocale.apply(request: request)
    }

    /// Builds the isolated container. Sync is constructed but never
    /// activated; the dead API client (unroutable Screenshot base URL) fails
    /// closed if anything ever calls it.
    static func makeContainer(
        store: LocalStore,
        sessionDirectory: URL,
        liveActivities: LiveActivityControlling
    ) -> AppContainer {
        let keychain = InMemoryKeychainStore()
        let suite = captureSuite()
        let sessionCache = SessionCache(
            defaults: suite,
            sessionFileURL: sessionDirectory.appendingPathComponent(ActiveAccountFileResolver.sessionFileName)
        )
        let sessionStore = SessionStore()
        sessionStore.setRestoring(false)
        sessionStore.setSignedIn(CachedSession(
            id: ScreenshotPreparation.fixtureUserID,
            email: fixtureEmail,
            emailVerified: true
        ))
        let navigation = AppNavigationStack()
        let connectivity = MockConnectivity(connected: true)
        let timerService = TimerService(store: store, liveActivities: liveActivities)
        let apiClient = APIClient(baseURL: AppConfig.baseURL, session: .shared)
        let repository = RemoteAuthRepository(client: apiClient)
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: sessionCache,
            sessionStore: sessionStore
        )
        let undoBuffer = UndoBufferStore(store: store)
        return AppContainer(
            baseURL: AppConfig.baseURL,
            apiClient: apiClient,
            keychain: keychain,
            sessionCache: sessionCache,
            repository: repository,
            sessionStore: sessionStore,
            navigation: navigation,
            connectivity: connectivity,
            authService: authService,
            appleService: AppleSignInService(),
            timerService: timerService,
            localStore: store,
            undoBuffer: undoBuffer,
            syncController: makeSyncController(store: store, client: apiClient, connectivity: connectivity, sessionStore: sessionStore),
            clientHolder: nil
        )
    }

    /// Capture preferences suite (never `.standard` by preference — the app
    /// prefs file is production state and capture must not touch it).
    /// Shared with the cleanup path so reset removes exactly this domain.
    /// Never crashes: suite creation can transiently fail (observed: nil on
    /// a first-launch test-host), so fall back through per-launch domains.
    /// This is safe, not a silent data fallback: `SessionCache.save` has NO
    /// capture call site (the session is set directly on `SessionStore`),
    /// so the object is never written — its identity is irrelevant, only
    /// that it is never the production domain by choice.
    static let captureSuiteName = "com.antonkosenko.timeoflifeapp.screenshots"

    static func captureSuite() -> UserDefaults {
        let candidates = [
            captureSuiteName,
            "\(captureSuiteName).\(ProcessInfo.processInfo.globallyUniqueString)",
        ]
        for name in candidates {
            if let suite = UserDefaults(suiteName: name) {
                return suite
            }
        }
        // Unreachable in practice (domain machinery verified on-device);
        // last resort that still never crashes launch. Never written by
        // capture (no save call sites above).
        return UserDefaults.standard
    }

    /// Sync is constructed (the container requires it) but the capture flow
    /// never activates it — verified at runtime after this returns.
    private static func makeSyncController(
        store: LocalStore,
        client: APIClient,
        connectivity: Connectivity,
        sessionStore: SessionStore
    ) -> SyncController {
        SyncController(
            store: store,
            remote: RemoteCatalogRepository(client: client),
            connectivity: connectivity
        ) { [weak sessionStore] in
            guard case let .signedIn(session) = sessionStore?.state else { return nil }
            return session.id
        }
    }

    /// Inert placeholder for Screenshot builds launched WITHOUT a request:
    /// touches no production state (unbound store, signed-out session, sync
    /// never activated) and renders an explanatory message.
    static func makePlaceholderContainer() -> AppContainer {
        let keychain = InMemoryKeychainStore()
        let suite = captureSuite()
        let sessionStore = SessionStore()
        sessionStore.setRestoring(false)
        sessionStore.setSignedOut()
        let navigation = AppNavigationStack()
        let connectivity = MockConnectivity(connected: true)
        let store = LocalStore()
        let timerService = TimerService(store: store, liveActivities: NoopLiveActivityController())
        let apiClient = APIClient(baseURL: AppConfig.baseURL, session: .shared)
        let repository = RemoteAuthRepository(client: apiClient)
        let authService = AuthService(
            repository: repository,
            keychain: keychain,
            cache: SessionCache(defaults: suite),
            sessionStore: sessionStore
        )
        let undoBuffer = UndoBufferStore(store: store)
        return AppContainer(
            baseURL: AppConfig.baseURL,
            apiClient: apiClient,
            keychain: keychain,
            sessionCache: SessionCache(defaults: suite),
            repository: repository,
            sessionStore: sessionStore,
            navigation: navigation,
            connectivity: connectivity,
            authService: authService,
            appleService: AppleSignInService(),
            timerService: timerService,
            localStore: store,
            undoBuffer: undoBuffer,
            syncController: makeSyncController(store: store, client: apiClient, connectivity: connectivity, sessionStore: sessionStore),
            clientHolder: nil
        )
    }

    /// Testable snapshot of a timer activity for the fixture-ownership rule
    /// below (the test host never has live ActivityKit activities, so the
    /// predicate is verified against snapshots instead).
    struct FixtureActivitySnapshot: Equatable {
        var id: String
        var entryText: String
        var state: ActivityState
    }

    /// Whether a capture-owned activity still needs an explicit end: a
    /// just-requested live anchor reads as `.pending` in a fresh process
    /// (iOS 26+: request accepted, not yet presented) and a visible banner
    /// can read as `.stale`. Both are still on screen — only an explicit
    /// end clears them (a reboot never does). `.ended`/`.dismissed` are
    /// already gone; `@unknown default` ends rather than leaks (still
    /// scoped to capture-owned activities by the caller).
    static func isEndableState(_ state: ActivityState) -> Bool {
        switch state {
        case .active, .stale:
            return true
        case .ended, .dismissed:
            return false
        @unknown default:
            return true
        }
    }

    /// Capture-owned matching rule (fixture text only — never another
    /// account's): an activity is capture-owned when its id is the known
    /// live anchor from capture-state.json (provenance beats content — a
    /// renamed/drifted text still ends) or when its entry text is any
    /// supported deck's draft text (stale banners from a previous run,
    /// locale changes included).
    static func endableFixtureSnapshots(
        _ snapshots: [FixtureActivitySnapshot],
        expectedActivityID: String?
    ) -> [FixtureActivitySnapshot] {
        let draftTexts = Set(ScreenshotFixture.allDraftTexts)
        return snapshots.filter { snapshot in
            let owned: Bool
            if let expected = expectedActivityID, snapshot.id == expected {
                owned = true
            } else {
                owned = draftTexts.contains(snapshot.entryText)
            }
            return owned && isEndableState(snapshot.state)
        }
    }

    /// Ends capture-owned live activities (fixture text only — never another
    /// account's): stale banners from a previous run must not leak into the
    /// next run's status chrome (two consecutive pilot runs). Matches any
    /// supported deck's draft text so a locale change still cleans the
    /// previous run. Returns the ended activity ids for the cleanup
    /// acknowledgement.
    ///
    /// When the known live anchor is supplied (cleanup path,
    /// `capture-state.json`'s `live_activity.activity_id`), the enumeration
    /// polls up to `timeout`: a fresh launch can read a just-requested
    /// anchor as `.pending` (or miss it entirely until the system delivers
    /// it), while older strays are already `.active` — a single shot ended
    /// the strays and missed exactly the currently-live one. Stray sweeps
    /// (capture start, no anchor) stay single-pass.
    static func endFixtureActivities(
        expectedActivityID: String? = nil,
        timeout: TimeInterval = 0
    ) async -> [String] {
        var ended: [String] = []
        var endedIDs = Set<String>()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let live = Activity<TimerActivityAttributes>.activities
            let snapshots = live.map {
                FixtureActivitySnapshot(id: $0.id, entryText: $0.attributes.entryText, state: $0.activityState)
            }
            let targets = endableFixtureSnapshots(snapshots, expectedActivityID: expectedActivityID)
                .filter { !endedIDs.contains($0.id) }
            for target in targets {
                if let activity = live.first(where: { $0.id == target.id }) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    endedIDs.insert(target.id)
                    ended.append(target.id)
                }
            }
            if expectedActivityID == nil { break }
            if let expected = expectedActivityID, endedIDs.contains(expected) { break }
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return ended
    }

    /// Polls for the real requested activity (realtime mode): acknowledgement
    /// means the system owns a live activity for our anchor. Nil on timeout —
    /// the runner fails the frame incomplete (no mocked timer, design §4).
    static func awaitLiveActivity(text: String, timeout: TimeInterval = 5) async -> Activity<TimerActivityAttributes>? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = Activity<TimerActivityAttributes>.activities.first(where: {
                $0.attributes.entryText == text && $0.activityState == .active
            }) {
                return match
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    static func iso8601(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func commitSHA() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "GIT_COMMIT_SHA") as? String
    }
}
#endif
