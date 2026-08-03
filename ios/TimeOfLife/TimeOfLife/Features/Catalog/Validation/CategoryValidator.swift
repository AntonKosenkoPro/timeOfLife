import Foundation

/// Category-specific presentation over the shared catalog rules. The rules
/// stay in one pure validator while the editor owns the category copy.
enum CategoryValidator {
    typealias ValidationError = CatalogValidator.ValidationError

    static func validateName(_ raw: String) -> [ValidationError] {
        CatalogValidator.validateName(raw)
    }

    static func validateIcon(_ raw: String) -> [ValidationError] {
        CatalogValidator.validateIcon(raw)
    }

    static func unifiedNameMessage(_ errors: [ValidationError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.contains(.nameEmpty) {
            return L10n.activityValidationNameEmpty.text
        }
        guard errors.contains(.nameTooLong) else { return nil }
        return "\(L10n.validationNamePrefix.text) \(L10n.validationNameRuleTooLong.text)."
    }

    static func unifiedIconMessage(_ errors: [ValidationError]) -> String? {
        guard errors.contains(.iconInvalid) else { return nil }
        return L10n.validationCatalogIconInvalid.text
    }
}
