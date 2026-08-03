import Foundation

/// Resolves the on-disk path for a per-account SQLite database.
///
/// Each authenticated user gets an isolated database file at
/// `Application Support/TimeOfLife/accounts/<user-uuid>.sqlite`.
/// This ensures Account A's data can never be read under Account B.
enum AccountDatabasePath {

    /// Returns the URL for the given user's database file, creating the
    /// parent directory if necessary.
    /// - Parameter userUUID: The authenticated user's server-assigned UUID.
    /// - Returns: The file URL for `<…>/accounts/<user-uuid>.sqlite`.
    /// - Throws: A `CocoaError` if the directory cannot be created.
    static func databaseURL(forUserUUID userUUID: String) throws -> URL {
        let fm = FileManager.default

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)

        let accountsDir = appSupport
            .appendingPathComponent("TimeOfLife", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)

        try fm.createDirectory(at: accountsDir, withIntermediateDirectories: true)

        return accountsDir.appendingPathComponent("\(userUUID).sqlite")
    }
}
