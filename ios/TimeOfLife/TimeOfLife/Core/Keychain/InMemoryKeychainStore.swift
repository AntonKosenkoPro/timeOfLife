import Foundation

/// Test double for `KeychainStoring` that keeps secrets in memory. Lives in
/// the app target so the test bundle can import and reuse it directly.
actor InMemoryKeychainStore: KeychainStoring {
    private var storage: [KeychainKey: String] = [:]
    private var snapshotStorage: CredentialSnapshot?
    /// When set, `saveSnapshot` fails with this error instead of writing.
    /// Decremented per attempt when positive via `failNextSaves`.
    private(set) var saveSnapshotError: KeychainError?
    /// Number of upcoming `saveSnapshot` calls that fail with
    /// `saveSnapshotError` (0 = never fail). Lets tests fail only the
    /// successor save while the earlier intent save succeeds.
    private(set) var failNextSaves = 0
    /// When set, `loadSnapshot` fails with this error instead of reading.
    private(set) var loadSnapshotError: KeychainError?

    init(initial: [KeychainKey: String] = [:], snapshot: CredentialSnapshot? = nil) {
        self.storage = initial
        self.snapshotStorage = snapshot
    }

    /// Fault injection for storage-failure tests (cross-actor mutation of
    /// the flags above is not allowed, so tests go through these).
    func setSaveSnapshotError(_ error: KeychainError?, failNextSaves count: Int = 0) {
        saveSnapshotError = error
        failNextSaves = count
    }

    func setLoadSnapshotError(_ error: KeychainError?) {
        loadSnapshotError = error
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

    func saveSnapshot(_ snapshot: CredentialSnapshot) async -> Result<Void, KeychainError> {
        if failNextSaves > 0, let error = saveSnapshotError {
            failNextSaves -= 1
            return .failure(error)
        }
        snapshotStorage = snapshot
        return .success(())
    }

    func loadSnapshot() async -> Result<CredentialSnapshot?, KeychainError> {
        if let error = loadSnapshotError {
            return .failure(error)
        }
        return .success(snapshotStorage)
    }

    func removeSnapshot() async {
        snapshotStorage = nil
    }
}
