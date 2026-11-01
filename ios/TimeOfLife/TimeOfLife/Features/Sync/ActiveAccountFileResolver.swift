import Foundation

/// Session-marker helpers for the active account's database file — no session
/// of their own, so the shared-session user id selects the file.
///
/// The user id is read FILE-FIRST (`active-session-user-id` in the
/// container, mirrored by `SessionCache` on every sign-in/out): suite
/// `UserDefaults` reads detach from `cfprefsd` inside some extension
/// processes (observed on-device), while group-container file reads stay
/// reliable — the same channel `LocalStore` itself depends on
/// cross-process. Suite defaults remain as the fallback.
///
/// Never opens, migrates, or writes a database — nothing here creates files
/// as a side effect (`LocalStore` remains the single mutation chokepoint).
struct ActiveAccountFileResolver {
    /// Reads the shared-session user id from the app's session cache
    /// defaults (production) — the same store `SessionCache` writes.
    private let sessionDefaults: UserDefaults?

    init(sessionDefaults: UserDefaults? = nil) {
        self.sessionDefaults = sessionDefaults
    }

    /// The `SessionCache` user-id key (SessionCache.swift: `Keys.id`) — kept
    /// in one place here rather than reaching into `SessionCache`'s private
    /// keys.
    private static let sessionUserIDKey = "com.timeoflife.session.id"

    /// The session-id sidecar file in the container root (mirrored by
    /// `SessionCache` on sign-in, removed on sign-out).
    static let sessionFileName = "active-session-user-id"

    /// The sidecar URL for `SessionCache` wiring (nil when the shared
    /// container is unavailable — file mirroring stays off, defaults only).
    static func sessionFileURL() -> URL? {
        appGroupBase().appendingPathComponent(sessionFileName)
    }

    /// Reads the shared-session user id (file-first, defaults fallback)
    /// without resolving a file. Used by deletion cleanup to clear the
    /// cross-process marker ONLY when it still names the deleted UUID —
    /// never when another account is active.
    func readSessionUserID(base: URL? = nil) -> String? {
        readSessionFile(base: base) ?? readSessionDefaults()
    }

    /// The App Group shared container's UserDefaults (the shared session
    /// surface extensions read), or nil when the group is unavailable.
    private static func appGroupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: LocalStore.appGroupID)
    }

    /// File-first session id (see type docs): nil when absent/unreadable.
    /// Read-only — never creates anything.
    private func readSessionFile(base: URL?) -> String? {
        let container = base ?? Self.appGroupBase()
        let url = container.appendingPathComponent(Self.sessionFileName)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Suite-defaults session id (fallback for contexts where `cfprefsd`
    /// stays reachable).
    private func readSessionDefaults() -> String? {
        let defaults = sessionDefaults ?? Self.appGroupDefaults()
        guard let userID = defaults?.string(forKey: Self.sessionUserIDKey),
              !userID.isEmpty else {
            return nil
        }
        return userID
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
