import Foundation

/// Persists non-secret session metadata (`user id`, `email`) in `UserDefaults`
/// so the UI can render a cached session after a cold launch, before `/me`
/// resolves. Tokens never go here — only `KeychainStoring`.
///
/// Thread-safe via a serial `DispatchQueue`.
final class SessionCache: @unchecked Sendable {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.timeoflife.SessionCache")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ session: CachedSession?) {
        queue.sync {
            if let session {
                defaults.set(session.id, forKey: Keys.id)
                defaults.set(session.email, forKey: Keys.email)
                defaults.set(session.emailVerified, forKey: Keys.emailVerified)
            } else {
                defaults.removeObject(forKey: Keys.id)
                defaults.removeObject(forKey: Keys.email)
                defaults.removeObject(forKey: Keys.emailVerified)
            }
        }
    }

    func load() -> CachedSession? {
        queue.sync {
            guard let id = defaults.string(forKey: Keys.id),
                  let email = defaults.string(forKey: Keys.email) else { return nil }
            let verified = defaults.bool(forKey: Keys.emailVerified)
            return CachedSession(id: id, email: email, emailVerified: verified)
        }
    }

    func clear() {
        save(nil)
    }

    private enum Keys {
        static let id = "com.timeoflife.session.id"
        static let email = "com.timeoflife.session.email"
        static let emailVerified = "com.timeoflife.session.emailVerified"
    }
}

/// The subset of `AuthSession` cached on disk (no secrets).
struct CachedSession: Equatable, Codable, Sendable {
    let id: String
    let email: String
    let emailVerified: Bool
}
