import Testing
import Foundation
@testable import TimeOfLife

@Suite("RecentActivitiesChips.recents")
struct RecentActivitiesChipsTests {

    private func recent(_ id: String) -> TrackViewModel.RecentEntry {
        TrackViewModel.RecentEntry(text: id, categoryIDs: [], firstCategoryID: nil)
    }

    @Test("caps at six recents, preserving the input order")
    func capsAtSix() {
        let recents = (0..<8).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(capped.count == 6)
        #expect(capped.map(\.text) == (0..<6).map { "a\($0)" })
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
