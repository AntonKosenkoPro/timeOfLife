import Foundation

/// Resolves the ACTIVE account's database file for cross-process surfaces —
/// lock-screen Control intents, widgets, and any future extension (lock-
/// screen-controls delta, account-bound-local-data 4.2). These surfaces hold
/// no session of their own: device unlock is the authorization, and the
/// shared-session user id (the same `SessionCache` UserDefaults the app
/// persists on sign-in) selects which `lifio_<userId>.db` is active.
///
/// Resolution rules (lock-screen-controls delta spec):
/// - No shared-session user id (signed out at the auth gate) → `.locked`:
///   the control shows a locked/empty state and never reads or creates an
///   anonymous file.
/// - A user id exists but its file is missing on disk (erased account, or
///   the device holds only dormant files for other accounts) → `.noData`:
///   the control shows an empty state without creating the file.
/// - A readable file → `.ready` with its URL; the caller opens it read-only
///   (or via the app's store when in-process) — never a dormant account's
///   file, because only the shared-session user id is ever resolved.
///
/// Never opens, migrates, or writes a database — extension surfaces must not
/// create files as a side effect of rendering (`LocalStore` remains the
/// single mutation chokepoint).
struct ActiveAccountFileResolver {
    /// Reads the shared-session user id from the app's session cache
    /// defaults (production) — the same store `SessionCache` writes.
    private let sessionDefaults: UserDefaults?

    init(sessionDefaults: UserDefaults? = nil) {
        self.sessionDefaults = sessionDefaults
    }

    /// The control-surface resolution outcomes.
    enum Resolution: Equatable {
        /// No active account (signed out): locked/empty state, no file touch.
        case locked
        /// An active account id exists but its file is absent (fresh or
        /// erased account, tracked only by the app): locked/empty state, no
        /// file created.
        case noData
        /// The active account's file exists and may be read.
        case ready(URL)
    }

    /// The `SessionCache` user-id key (SessionCache.swift: `Keys.id`) — kept
    /// in one place here rather than reaching into `SessionCache`'s private
    /// keys.
    private static let sessionUserIDKey = "com.timeoflife.session.id"

    /// Resolves the active account's file URL inside the App Group container
    /// (or `base` in tests/previews). Never creates anything.
    func resolve(base: URL? = nil) -> Resolution {
        let defaults = sessionDefaults ?? Self.appGroupDefaults()
        guard let userID = defaults?.string(forKey: Self.sessionUserIDKey),
              !userID.isEmpty else {
            return .locked
        }
        let sanitized = userID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !sanitized.isEmpty, sanitized == userID else {
            return .locked
        }
        let container = base ?? Self.appGroupBase()
        let url = container.appendingPathComponent(
            LocalStore.databaseFileName(userID: sanitized)
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .noData
        }
        return .ready(url)
    }

    /// The App Group shared container's UserDefaults (the shared session
    /// surface extensions read), or nil when the group is unavailable.
    private static func appGroupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: LocalStore.appGroupID)
    }

    private static func appGroupBase() -> URL {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: LocalStore.appGroupID)
        return container ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
