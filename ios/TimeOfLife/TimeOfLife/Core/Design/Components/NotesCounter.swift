import Foundation

/// Pure notes-length helper (extend-notes-limit): mirrors the relay rule
/// (trim, then count runes) so the editor counter matches the 2000-rune
/// gate. `unicodeScalars.count` is the Swift measure closest to Go's
/// `RuneCountInString` — identical for all valid strings except
/// multi-scalar graphemes (accepted edge; the server stays authoritative).
enum NotesCounter {
    /// Maximum notes length in trimmed runes (relay `maxNotesLen`).
    static let maxRunes = 2000

    /// Trimmed scalar count of the draft.
    static func trimmedCount(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    /// Whether the draft exceeds the relay bound.
    static func isOverLimit(_ text: String) -> Bool {
        trimmedCount(text) > maxRunes
    }
}
