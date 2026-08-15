import Testing
import Foundation
@testable import TimeOfLife

@Suite("ActivityName")
struct ActivityNameTests {

    @Test("surrounding whitespace and newlines are trimmed")
    func trimsSurroundingWhitespace() {
        #expect(ActivityName.normalized("  Coding  ") == "Coding")
        #expect(ActivityName.normalized("\n\tReading\n") == "Reading")
        #expect(ActivityName.normalized("   ").isEmpty)
    }

    @Test("internal whitespace is preserved")
    func preservesInternalWhitespace() {
        #expect(ActivityName.normalized("Deep  work") == "Deep  work")
    }

    @Test("a non-empty trimmed name within the limit is valid")
    func validName() {
        #expect(ActivityName.validate("Coding") == .valid("Coding"))
        #expect(ActivityName.validate("  Deep work  ") == .valid("Deep work"))
        #expect(ActivityName.validate(String(repeating: "a", count: 60)) == .valid(String(repeating: "a", count: 60)))
    }

    @Test("an empty or whitespace-only name is invalid")
    func emptyNameIsInvalid() {
        #expect(ActivityName.validate("") == .empty)
        #expect(ActivityName.validate("   ") == .empty)
        #expect(ActivityName.validate("\n\t") == .empty)
    }

    @Test("a name longer than 60 characters is invalid")
    func tooLongNameIsInvalid() {
        #expect(ActivityName.validate(String(repeating: "a", count: 61)) == .tooLong)
        #expect(ActivityName.validate("  " + String(repeating: "a", count: 61)) == .tooLong)
    }

    @Test("normalized empty string is empty")
    func normalizedEmpty() {
        #expect(ActivityName.normalized("").isEmpty)
    }
}
