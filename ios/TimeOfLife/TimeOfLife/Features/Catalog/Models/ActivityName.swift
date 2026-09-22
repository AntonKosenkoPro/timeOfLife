import Foundation

/// Shared entry-name normalization and validation (remove-activities-layer
/// D1): identity is the trimmed exact text compared case-SENSITIVELY
/// (`Gym` ≠ `GYM`), and a valid name is non-empty and at most 60 characters.
/// Used by Track capture, recents chips, and the entry form so every path
/// applies the same rules. Trim stays to avoid `"Gym "` ghosts.
enum ActivityName {
    /// The maximum name length in characters.
    static let maxLength = 60

    /// The outcome of validating a candidate name.
    enum Validation: Equatable {
        /// The name is valid; the associated value is the normalized name
        /// (surrounding whitespace trimmed).
        case valid(String)
        /// The trimmed name is empty.
        case empty
        /// The trimmed name exceeds `maxLength` characters.
        case tooLong
    }

    /// Trims surrounding whitespace and newlines.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates a candidate name, returning the normalized name on success.
    static func validate(_ name: String) -> Validation {
        let trimmed = normalized(name)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= maxLength else { return .tooLong }
        return .valid(trimmed)
    }
}
