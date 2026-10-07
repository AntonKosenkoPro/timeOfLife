import Foundation

/// Pure notes-length helper (extend-notes-limit): counts every rune in the
/// draft (`unicodeScalars.count`, the Swift measure closest to Go's
/// `RuneCountInString` — identical for all valid strings) against the
/// 2000-rune relay bound, so every keystroke moves the counter by exactly
/// one. Surrounding whitespace counts client-side even though the relay
/// trims before gating: the client is strictly tighter, so anything it lets
/// through the relay accepts (no sync wedge), and the counter never jumps.
enum NotesCounter {
    /// Maximum notes length in runes (relay `maxNotesLen`).
    static let maxRunes = 2000

    /// Scalar count of the draft, untrimmed.
    static func count(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// Whether the draft exceeds the relay bound.
    static func isOverLimit(_ text: String) -> Bool {
        count(text) > maxRunes
    }
}
