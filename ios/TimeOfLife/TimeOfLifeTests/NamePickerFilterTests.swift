import Testing
import Foundation
@testable import TimeOfLife

@Suite("NamePickerFilter")
struct NamePickerFilterTests {

    private var recents: [ExactName] {
        [
            ExactName(text: "Gymnastics", categoryIDs: [], firstCategoryID: nil),
            ExactName(text: "Gym", categoryIDs: ["c1"], firstCategoryID: "c1"),
            ExactName(text: "GYM", categoryIDs: ["c2"], firstCategoryID: "c2")
        ]
    }

    @Test("empty draft lists all recents in order")
    func emptyListsAll() {
        #expect(NamePickerFilter.suggestions(for: "", in: recents).map(\.text) == ["Gymnastics", "Gym", "GYM"])
    }

    @Test("whitespace-only draft lists all recents")
    func whitespaceListsAll() {
        #expect(NamePickerFilter.suggestions(for: "   ", in: recents).count == 3)
    }

    @Test("prefix matches case-insensitively, newest-first")
    func prefixMatch() {
        let result = NamePickerFilter.suggestions(for: "gy", in: recents).map(\.text)
        #expect(result == ["Gymnastics", "Gym", "GYM"])
    }

    @Test("trims surrounding whitespace before matching")
    func trimsWhitespace() {
        let result = NamePickerFilter.suggestions(for: "  Gy  ", in: recents).map(\.text)
        #expect(result == ["Gymnastics", "Gym", "GYM"])
    }

    @Test("exact match is included alongside longer prefix matches")
    func exactIncluded() {
        let result = NamePickerFilter.suggestions(for: "Gym", in: recents).map(\.text)
        #expect(result == ["Gymnastics", "Gym", "GYM"])
    }

    @Test("typing a lone existing name narrows to its row, not the new-name hint")
    func loneExactMatchListsItself() {
        let solo = [ExactName(text: "Gym", categoryIDs: ["c1"], firstCategoryID: "c1")]
        #expect(NamePickerFilter.suggestions(for: "Gym", in: solo).map(\.text) == ["Gym"])
    }

    @Test("no match returns empty")
    func noMatch() {
        #expect(NamePickerFilter.suggestions(for: "Zzz", in: recents).isEmpty)
    }
}
