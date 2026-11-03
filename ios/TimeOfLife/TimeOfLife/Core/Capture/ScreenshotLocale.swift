#if SCREENSHOT_CAPTURE
import Foundation

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
    // Memoized `.lproj` bundle: `L10n.text` resolves per key per render,
    // and each resolution took the lock, hit the filesystem
    // (`Bundle.main.path(forResource:)`) and allocated a fresh Bundle —
    // per string, per frame. The bundle only changes on `apply`/`reset`,
    // so it is cached keyed by the override identifier and invalidated
    // in both.
    nonisolated(unsafe) private static var _cachedBundleIdentifier: String?
    nonisolated(unsafe) private static var _cachedBundle: Bundle?

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
        _cachedBundleIdentifier = nil
        _cachedBundle = nil
    }

    /// Clears the override (tests; capture processes set it once per launch).
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _overrideIdentifier = nil
        _appleLocaleIdentifier = nil
        _timeZoneIdentifier = nil
        _cachedBundleIdentifier = nil
        _cachedBundle = nil
    }

    /// The request's `.lproj` bundle, or nil when unset/unresolvable
    /// (callers fall back to prior behavior). Memoized per override
    /// identifier: repeated lookups return the same instance without
    /// re-locking or touching the filesystem.
    static func overrideBundle() -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let id = _overrideIdentifier,
           id == _cachedBundleIdentifier,
           let cached = _cachedBundle {
            return cached
        }
        guard let id = _overrideIdentifier,
              let path = Bundle.main.path(forResource: id, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            _cachedBundleIdentifier = nil
            _cachedBundle = nil
            return nil
        }
        _cachedBundleIdentifier = id
        _cachedBundle = bundle
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
