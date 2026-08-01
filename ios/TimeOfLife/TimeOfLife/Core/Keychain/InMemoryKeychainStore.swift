import Foundation

/// Test double for `KeychainStoring` that keeps secrets in memory. Lives in
/// the app target so the test bundle can import and reuse it directly.
actor InMemoryKeychainStore: KeychainStoring {
    private var storage: [KeychainKey: String] = [:]

    init(initial: [KeychainKey: String] = [:]) {
        self.storage = initial
    }

    func setString(_ string: String, for key: KeychainKey) async {
        storage[key] = string
    }

    func string(for key: KeychainKey) async -> String? {
        storage[key]
    }

    func remove(key: KeychainKey) async {
        storage.removeValue(forKey: key)
    }

    /// Test-only snapshot accessor.
    func snapshot() async -> [KeychainKey: String] {
        storage
    }
}
