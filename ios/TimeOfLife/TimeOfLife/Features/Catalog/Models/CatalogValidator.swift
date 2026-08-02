import Foundation

/// Pure validation mirroring the backend catalog rules (U1) so the client can
/// reject before hitting the network; the server remains authoritative.
/// One field → one unified message (U4), reused by editor views in 1-2..1-5.
enum CatalogValidator {
    static let maxName = 60
    static let maxNotes = 280

    enum Field: String, Hashable, Sendable {
        case name
        case notes
        case color
        case icon
    }

    enum ValidationError: Error, Equatable, Sendable {
        case nameEmpty
        case nameTooLong
        case notesTooLong
        case colorInvalid
        case iconInvalid
    }

    /// Validates an activity/category name: non-empty after trim, ≤ `maxName`.
    static func validateName(_ raw: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errors.append(.nameEmpty)
            return errors
        }
        if name.count > maxName {
            errors.append(.nameTooLong)
        }
        return errors
    }

    /// Validates notes: ≤ `maxNotes` (notes may be empty — the field is optional).
    static func validateNotes(_ raw: String) -> [ValidationError] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxNotes {
            return [.notesTooLong]
        }
        return []
    }

    /// Validates a raw color key against the palette.
    static func validateColor(_ raw: String) -> [ValidationError] {
        ActivityColor.validKeys.contains(raw) ? [] : [.colorInvalid]
    }

    /// Validates a raw icon key against the allowed SF Symbols set.
    static func validateIcon(_ raw: String) -> [ValidationError] {
        ActivityIcon.validKeys.contains(raw) ? [] : [.iconInvalid]
    }

    /// Normalizes a name for reuse lookups: trimmed + lowercased (F4).
    static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Unified messages (U4)

    /// A single, merged message for the name field, or `nil` when valid.
    static func unifiedNameMessage(_ errors: [ValidationError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.contains(.nameEmpty) {
            return L10n.activityValidationNameEmpty.text
        }
        if errors.contains(.nameTooLong) {
            return L10n.activityValidationNameTooLong.text
        }
        return nil
    }

    /// A single message for the notes field, or `nil` when valid.
    static func unifiedNotesMessage(_ errors: [ValidationError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.contains(.notesTooLong) {
            return L10n.activityValidationNotesTooLong.text
        }
        return nil
    }

    /// A single message for the color field, or `nil` when valid.
    static func unifiedColorMessage(_ errors: [ValidationError]) -> String? {
        guard errors.contains(.colorInvalid) else { return nil }
        return L10n.validationCatalogColorInvalid.text
    }

    /// A single message for the icon field, or `nil` when valid.
    static func unifiedIconMessage(_ errors: [ValidationError]) -> String? {
        guard errors.contains(.iconInvalid) else { return nil }
        return L10n.validationCatalogIconInvalid.text
    }
}
