import Foundation

/// Test double for `KeychainStoring` that keeps secrets in memory. Lives in
/// the app target so the test bundle can import and reuse it directly.
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [KeychainKey: String] = [:]
    private let lock = NSLock()

    init(initial: [KeychainKey: String] = [:]) {
        self.storage = initial
    }

    func setString(_ string: String, for key: KeychainKey) async {
        lock.lock(); defer { lock.unlock() }
        storage[key] = string
    }

    func string(for key: KeychainKey) async -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func remove(key: KeychainKey) async {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    func removeAll() async {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    /// Test-only snapshot accessor.
    func snapshot() -> [KeychainKey: String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}