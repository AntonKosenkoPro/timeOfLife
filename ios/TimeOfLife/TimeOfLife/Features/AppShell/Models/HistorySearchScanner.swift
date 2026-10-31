import Foundation

/// Whitespace scanner for the History query language (design D2).
/// Splits on unquoted whitespace; `"` toggles phrase grouping with `\"`
/// and `\\` escapes. Quote awareness lets qualifier detection skip quoted
/// colons (so `"project:alpha"` stays literal text).
enum HistorySearchScanner {
    /// One whitespace-separated token. `text` keeps the original spelling
    /// (quotes/escapes intact) for qualifier detection; `value` is the
    /// unescaped literal with quote characters removed.
    struct RawToken {
        var text: String
        var value: String
    }

    enum ScanResult {
        case success([RawToken])
        case failure(HistorySearchDiagnostic)
    }

    static func tokenize(_ raw: String) -> ScanResult {
        var state = State()
        var index = raw.startIndex
        while index < raw.endIndex {
            let char = raw[index]
            if state.inQuotes {
                guard consumeQuoted(char, raw: raw, index: &index, state: &state) else {
                    return .failure(.badQuotes)
                }
            } else if char == "\"" {
                state.beginQuote()
            } else if char.isWhitespace {
                state.flush()
            } else {
                state.append(char)
            }
            index = raw.index(after: index)
        }
        guard !state.inQuotes else {
            return .failure(.badQuotes)
        }
        state.flush()
        return .success(state.tokens)
    }

    /// Index of the first `:` outside quoted spans, or nil.
    static func firstUnquotedColon(in text: String) -> String.Index? {
        firstUnquoted(of: ":", in: text)
    }

    /// Whether the token holds `(` or `)` outside quoted spans. Quoted
    /// parens stay literal phrase text; unquoted ones are unsupported
    /// operators (no parentheses in the query language).
    static func containsUnquotedParen(in text: String) -> Bool {
        firstUnquoted(of: "(", in: text) != nil || firstUnquoted(of: ")", in: text) != nil
    }

    private static func firstUnquoted(of target: Character, in text: String) -> String.Index? {
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if inQuotes {
                if char == "\\" {
                    index = text.index(after: index)
                    if index < text.endIndex {
                        index = text.index(after: index)
                    }
                    continue
                }
                if char == "\"" {
                    inQuotes = false
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == target {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Scanner state

    private struct State {
        var tokens: [RawToken] = []
        var text = ""
        var value = ""
        var inQuotes = false
        var hasContent = false

        mutating func append(_ char: Character) {
            text.append(char)
            value.append(char)
            hasContent = true
        }

        mutating func beginQuote() {
            text.append("\"")
            hasContent = true
            inQuotes = true
        }

        mutating func flush() {
            guard hasContent else { return }
            tokens.append(RawToken(text: text, value: value))
            text = ""
            value = ""
            hasContent = false
        }
    }

    /// Consumes one character inside a quoted phrase. Returns false on
    /// invalid escapes or a trailing backslash.
    private static func consumeQuoted(
        _ char: Character,
        raw: String,
        index: inout String.Index,
        state: inout State
    ) -> Bool {
        if char == "\\" {
            let next = raw.index(after: index)
            guard next < raw.endIndex else { return false }
            let escaped = raw[next]
            guard escaped == "\"" || escaped == "\\" else { return false }
            state.text.append(char)
            state.text.append(escaped)
            state.value.append(escaped)
            state.hasContent = true
            index = next
            return true
        }
        if char == "\"" {
            state.inQuotes = false
            state.text.append(char)
            state.hasContent = true
            return true
        }
        state.text.append(char)
        state.value.append(char)
        state.hasContent = true
        return true
    }
}
