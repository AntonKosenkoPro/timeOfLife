import Foundation

/// Errors thrown by `AccountDatabasePath`.
enum AccountDatabasePathError: Error, CustomStringConvertible {
    /// The supplied `userUUID` is not a valid UUID string.
    case invalidUUID(String)

    var description: String {
        switch self {
        case .invalidUUID(let uuid):
            return "Invalid user UUID: '\(uuid)' — expected a valid UUID string"
        }
    }
}

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
    /// Returns the URL for the given user's database file, creating the
    /// parent directory if necessary.
    /// - Parameter userUUID: The authenticated user's server-assigned UUID.
    /// - Returns: The file URL for `<…>/accounts/<user-uuid>.sqlite`.
    /// - Throws: `CocoaError` if the directory cannot be created, or
    ///   `AccountDatabasePathError.invalidUUID` if `userUUID` is not a valid UUID.
    static func databaseURL(forUserUUID userUUID: String) throws -> URL {
        guard UUID(uuidString: userUUID) != nil else {
            throw AccountDatabasePathError.invalidUUID(userUUID)
        }

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
