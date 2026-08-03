import Testing
import Foundation
@testable import TimeOfLife

@Suite("ActivityValidator")
struct ActivityValidatorTests {
    @Test("validates the activity limits and shared icon set")
    func validatesLimits() {
        #expect(ActivityValidator.validateName("") == [.nameEmpty])
        #expect(ActivityValidator.validateName(String(repeating: "a", count: 61)) == [.nameTooLong])
        #expect(ActivityValidator.validateNotes(String(repeating: "a", count: 281)) == [.notesTooLong])
        #expect(CatalogValidator.validateIcon("invalid") == [.iconInvalid])
    }

    @Test("collapses validation to one localized message per field")
    func unifiedMessages() {
        #expect(ActivityValidator.unifiedNameMessage([.nameEmpty, .nameTooLong]) == L10n.activityValidationNameEmpty.text)
        #expect(ActivityValidator.unifiedNotesMessage([.notesTooLong]) == L10n.activityValidationNotesTooLong.text)
        #expect(ActivityValidator.unifiedNameMessage([]) == nil)
    }
}
