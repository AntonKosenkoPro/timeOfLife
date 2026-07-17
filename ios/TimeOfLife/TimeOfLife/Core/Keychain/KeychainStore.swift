import Foundation
import Security

/// Production `KeychainStoring` backed by the Security framework.
///
/// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so secrets survive
/// first unlock but never leave the device (no iCloud sync). Concurrency:
/// Keychain Services is thread-safe; we wrap the calls in an actor so the
/// protocol is uniform with the in-memory test double.
actor KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "com.timeoflife.keychain") {
        self.service = service
    }

    func setString(_ string: String, for key: KeychainKey) async {
        let data = Data(string.utf8)
        var query: [String: Any] = baseQuery(for: key)
        // Delete before add to avoid duplicates (no sec_item_update needed).
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func string(for key: KeychainKey) async -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(key: KeychainKey) async {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    func removeAll() async {
        for key in [KeychainKey.accessToken, KeychainKey.refreshToken] {
            SecItemDelete(baseQuery(for: key) as CFDictionary)
        }
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}