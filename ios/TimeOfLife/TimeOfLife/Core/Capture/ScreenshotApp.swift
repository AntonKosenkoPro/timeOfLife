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
    static func applyProcessLocale(_ request: ScreenshotCaptureRequest) {
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

    /// Ends capture-owned live activities (fixture text only — never another
    /// account's): stale banners from a previous run must not leak into the
    /// next run's status chrome (two consecutive pilot runs). Matches any
    /// supported deck's draft text so a locale change still cleans the
    /// previous run. Returns the ended activity ids for the cleanup
    /// acknowledgement.
    static func endFixtureActivities() async -> [String] {
        let draftTexts = Set(ScreenshotFixture.allDraftTexts)
        let stale = Activity<TimerActivityAttributes>.activities.filter {
            $0.activityState == .active && draftTexts.contains($0.attributes.entryText)
        }
        var ended: [String] = []
        for activity in stale {
            await activity.end(nil, dismissalPolicy: .immediate)
            ended.append(activity.id)
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

/// In-process locale override for capture chrome (screenshot-capture
/// regression fix: chrome lagged one run behind the request).
///
/// Writes to `AppleLanguages`/`AppleLocale` after launch never re-resolve
/// `Bundle.main` or `Locale.current` in the same process, so each run
/// rendered the previous run's language while the fixture — keyed directly
/// off `request.localeIdentifier` — was already correct. The override
/// resolves chrome from the request's `.lproj` in-process: `L10n.text` /
/// `String.localized` (string chrome) and the default-locale duration/time
/// helpers (unit chrome) consult it. Explicit locale/bundle parameters
/// always win, so unit tests passing explicit values are unaffected.
/// Capture-only; shipping builds keep stock behavior. Reads fall back to
/// prior behavior when unset or unresolvable (never crashes).
///
/// Concurrency: set once on the main actor before the shell mounts (and
/// per-test with a `reset()` in `defer`); reads come from any thread, so
/// all state is lock-guarded after the `NSLock` pattern in
/// `AppContainer+UITesting.swift`.
enum ScreenshotLocale {
    private static let lock = NSLock()
    // Lock-guarded (see `AppContainer+UITesting.swift`): `nonisolated(unsafe)`
    // silences Swift 6 global-state diagnostics; the lock provides the real
    // discipline (set once pre-mount / per-test with `reset()`, reads anywhere).
    nonisolated(unsafe) private static var _overrideIdentifier: String?
    nonisolated(unsafe) private static var _appleLocaleIdentifier: String?
    nonisolated(unsafe) private static var _timeZoneIdentifier: String?

    /// The request locale identifier (e.g. `ru`, `zh-Hans`), if set.
    static var overrideIdentifier: String? {
        lock.lock(); defer { lock.unlock() }
        return _overrideIdentifier
    }

    static func apply(request: ScreenshotCaptureRequest) {
        lock.lock(); defer { lock.unlock() }
        _overrideIdentifier = request.localeIdentifier
        _appleLocaleIdentifier = request.appleLocaleIdentifier
        _timeZoneIdentifier = request.timeZone.identifier
    }

    /// Clears the override (tests; capture processes set it once per launch).
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _overrideIdentifier = nil
        _appleLocaleIdentifier = nil
        _timeZoneIdentifier = nil
    }

    /// The request's `.lproj` bundle, or nil when unset/unresolvable
    /// (callers fall back to prior behavior).
    static func overrideBundle() -> Bundle? {
        guard let id = overrideIdentifier,
              let path = Bundle.main.path(forResource: id, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        return bundle
    }

    /// Request-locale string for `key`, or nil to keep prior behavior.
    static func localizedString(key: String) -> String? {
        guard let bundle = overrideBundle() else { return nil }
        let value = NSLocalizedString(key, bundle: bundle, comment: "")
        return value == key ? nil : value
    }

    /// Request locale for default-locale duration/time helpers, or nil to
    /// keep `.current`.
    static var appLocale: Locale? {
        lock.lock(); defer { lock.unlock() }
        guard let id = _appleLocaleIdentifier else { return nil }
        return Locale(identifier: id)
    }

    /// Request time zone for default-zone time helpers, or nil to keep the
    /// process zone.
    static var appTimeZone: TimeZone? {
        lock.lock(); defer { lock.unlock() }
        guard let id = _timeZoneIdentifier else { return nil }
        return TimeZone(identifier: id)
    }
}
#endif
