import Testing
@testable import TimeOfLife

@Suite("Notes counter")
struct NotesCounterTests {
    @Test("empty draft counts zero")
    func empty() {
        #expect(NotesCounter.trimmedCount("") == 0)
        #expect(!NotesCounter.isOverLimit(""))
    }

    @Test("ASCII counts by character")
    func ascii() {
        #expect(NotesCounter.trimmedCount("hello") == 5)
        #expect(!NotesCounter.isOverLimit("hello"))
    }

    @Test("surrounding whitespace is free")
    func trimsWhitespace() {
        #expect(NotesCounter.trimmedCount("  hi  ") == 2)
        #expect(NotesCounter.trimmedCount("   ") == 0)
        #expect(!NotesCounter.isOverLimit("   "))
    }

    @Test("multibyte runes count as one")
    func multibyte() {
        #expect(NotesCounter.trimmedCount(String(repeating: "я", count: 10)) == 10)
    }

    @Test("2000 trimmed runes pass, 2001 fail")
    func boundary() {
        #expect(NotesCounter.trimmedCount(String(repeating: "a", count: 2000)) == 2000)
        #expect(!NotesCounter.isOverLimit(String(repeating: "a", count: 2000)))
        #expect(NotesCounter.isOverLimit(String(repeating: "a", count: 2001)))
        #expect(!NotesCounter.isOverLimit("  " + String(repeating: "я", count: 2000) + "  "))
        #expect(NotesCounter.isOverLimit(String(repeating: "я", count: 2001)))
    }
}
