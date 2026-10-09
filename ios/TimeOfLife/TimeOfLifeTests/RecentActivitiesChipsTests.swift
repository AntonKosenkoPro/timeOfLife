import Testing
import Foundation
@testable import TimeOfLife

@Suite("RecentActivitiesChips.recents")
struct RecentActivitiesChipsTests {

    private func recent(_ id: String) -> ExactName {
        ExactName(text: id, categoryIDs: [], firstCategoryID: nil)
    }

    @Test("caps at twelve recents, preserving the input order")
    func capsAtTwelve() {
        let recents = (0..<14).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(capped.count == 12)
        #expect(capped.map(\.text) == (0..<12).map { "a\($0)" })
    }

    @Test("omits the oldest recents beyond the cap")
    func omitsOldestBeyondCap() {
        let recents = (0..<13).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(!capped.map(\.text).contains("a12"))
        #expect(capped.last?.text == "a11")
    }

    @Test("returns all recents when fewer than the cap")
    func fewerThanCap() {
        let recents = (0..<3).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(capped.count == 3)
        #expect(capped.map(\.text) == recents.map(\.text))
    }

    @Test("returns nothing for an empty input")
    func emptyInput() {
        #expect(RecentActivitiesChips.recents(from: []).isEmpty)
    }

    @Test("preserves the store-sorted order exactly")
    func preservesOrder() {
        let recents = [recent("oldest"), recent("middle"), recent("newest")]
        #expect(RecentActivitiesChips.recents(from: recents).map(\.text) == ["oldest", "middle", "newest"])
    }

    @Test("honours a custom limit")
    func customLimit() {
        let recents = (0..<4).map { recent("a\($0)") }
        #expect(RecentActivitiesChips.recents(from: recents, limit: 2).count == 2)
    }
}
