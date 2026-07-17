import Foundation

/// Abstract persistent secret storage (Keychain in production, in-memory
/// in tests). Only tokens live here — the session cache (id/email) is kept
/// in `UserDefaults` via `SessionCache`.
protocol KeychainStoring: AnyObject, Sendable {
    func setString(_ string: String, for key: KeychainKey) async
    func string(for key: KeychainKey) async -> String?
    func remove(key: KeychainKey) async
    func removeAll() async
}

/// Stable Keychain keys. Never put user-facing data here — secrets only.
enum KeychainKey: String, Sendable {
    case accessToken = "com.timeoflife.access_token"
    case refreshToken = "com.timeoflife.refresh_token"
}