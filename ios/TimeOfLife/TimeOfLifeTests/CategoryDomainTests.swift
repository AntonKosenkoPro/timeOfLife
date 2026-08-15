import Testing
import Foundation
@testable import TimeOfLife

@Suite("CategoryName")
struct CategoryNameTests {

    @Test("valid names are trimmed and accepted")
    func validNamesTrimmed() {
        #expect(CategoryName.validate("Work") == .valid("Work"))
        #expect(CategoryName.validate("  Work  ") == .valid("Work"))
        #expect(CategoryName.validate("\n\tSport\n") == .valid("Sport"))
    }

    @Test("empty and whitespace-only names are rejected")
    func emptyNamesRejected() {
        #expect(CategoryName.validate("") == .empty)
        #expect(CategoryName.validate("   ") == .empty)
        #expect(CategoryName.validate("\n\t") == .empty)
    }

    @Test("the 60-character boundary is enforced")
    func lengthBoundary() {
        #expect(CategoryName.validate(String(repeating: "a", count: 60)) == .valid(String(repeating: "a", count: 60)))
        #expect(CategoryName.validate(String(repeating: "a", count: 61)) == .tooLong)
    }

    @Test("unicode characters count as characters, not bytes")
    func unicodeCountsAsCharacters() {
        let name = String(repeating: "Ж", count: 60)
        #expect(CategoryName.validate(name) == .valid(name))
        #expect(CategoryName.validate(String(repeating: "Ж", count: 61)) == .tooLong)
    }

    @Test("normalized trims surrounding whitespace and newlines")
    func normalizedTrims() {
        #expect(CategoryName.normalized("  Deep Work  ") == "Deep Work")
        #expect(CategoryName.normalized("Deep\nWork") == "Deep\nWork")
    }

    @Test("duplicate normalization is case-insensitive and whitespace-insensitive")
    func duplicateNormalization() {
        #expect(CategoryName.normalized("work").caseInsensitiveCompare("Work") == .orderedSame)
        #expect(CategoryName.normalized("  WORK  ").caseInsensitiveCompare("work") == .orderedSame)
    }
}

@Suite("CategoryDraft")
struct CategoryDraftTests {

    @Test("create mode defaults the icon to tag")
    func createDefaultsToTag() {
        let draft = CategoryDraft(name: "Sport")
        #expect(draft.icon == .tag)
    }

    @Test("draft preserves an explicitly selected icon")
    func preservesExplicitIcon() {
        let draft = CategoryDraft(name: "Sport", icon: .figureRun)
        #expect(draft.icon == .figureRun)
        #expect(draft.name == "Sport")
    }

    @Test("drafts are equatable and copyable")
    func equatableAndCopyable() {
        let a = CategoryDraft(name: "Work", icon: .briefcase)
        let b = CategoryDraft(name: "Work", icon: .briefcase)
        let c = CategoryDraft(name: "Work", icon: .tag)
        #expect(a == b)
        #expect(a != c)
        var copy = a
        copy.name = "Deep Work"
        #expect(copy != a)
    }

    @Test("an unsupported icon value is rejected by the closed type")
    func unsupportedIconRejected() {
        // The closed CatalogIcon type cannot represent an unsupported symbol;
        // validating an arbitrary string falls back to tag, and the fallback
        // is stable (stored raw values are preserved separately).
        let icon = CatalogIcon(validated: "not.a.real.symbol")
        #expect(icon == .tag)
    }
}
