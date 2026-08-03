import Foundation

/// Activity-specific façade over the shared catalog validation rules.
/// Keeping this name at the feature boundary lets the editor evolve without
/// duplicating the backend-aligned validation implementation.
enum ActivityValidator {
    typealias ValidationError = CatalogValidator.ValidationError

    static func validateName(_ value: String) -> [ValidationError] {
        CatalogValidator.validateName(value)
    }

    static func validateNotes(_ value: String) -> [ValidationError] {
        CatalogValidator.validateNotes(value)
    }

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

    static func unifiedNotesMessage(_ errors: [ValidationError]) -> String? {
        errors.contains(.notesTooLong) ? L10n.activityValidationNotesTooLong.text : nil
    }

}
