import Testing
@testable import TimeOfLife

@Suite("Notes counter")
struct NotesCounterTests {
    @Test("empty draft counts zero")
    func empty() {
        #expect(NotesCounter.count("") == 0)
        #expect(!NotesCounter.isOverLimit(""))
    }

    @Test("ASCII counts by character")
    func ascii() {
        #expect(NotesCounter.count("hello") == 5)
        #expect(!NotesCounter.isOverLimit("hello"))
    }

    @Test("every keystroke counts, including whitespace")
    func countsWhitespace() {
        // No trimming: a space moves the counter by exactly one, so typing
        // never jumps.
        #expect(NotesCounter.count("  hi  ") == 6)
        #expect(NotesCounter.count("   ") == 3)
        #expect(!NotesCounter.isOverLimit("   "))
    }

    @Test("multibyte runes count as one")
    func multibyte() {
        #expect(NotesCounter.count(String(repeating: "я", count: 10)) == 10)
    }

    @Test("2000 runes pass, 2001 fail")
    func boundary() {
        #expect(NotesCounter.count(String(repeating: "a", count: 2000)) == 2000)
        #expect(!NotesCounter.isOverLimit(String(repeating: "a", count: 2000)))
        #expect(NotesCounter.isOverLimit(String(repeating: "a", count: 2001)))
        #expect(NotesCounter.isOverLimit(String(repeating: "я", count: 2001)))
    }

    @Test("client is strictly tighter than the relay")
    func tighterThanRelay() {
        // Surrounding whitespace counts client-side while the relay trims
        // before gating, so a whitespace-padded 2000-rune note reads
        // over-limit here yet the relay would accept it. Safe direction:
        // the client never lets through what the relay rejects.
        #expect(NotesCounter.count("  " + String(repeating: "я", count: 2000) + "  ") == 2004)
        #expect(NotesCounter.isOverLimit("  " + String(repeating: "я", count: 2000) + "  "))
    }
}
