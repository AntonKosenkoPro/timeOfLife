import Testing
import Foundation
@testable import TimeOfLife

@Suite("RecentActivitiesChips.recents")
struct RecentActivitiesChipsTests {

    @Test("caps at six activities, preserving the input order")
    func capsAtSix() {
        let activities = (0..<8).map { Activity(id: "a\($0)", name: "Activity \($0)") }
        let recents = RecentActivitiesChips.recents(from: activities)
        #expect(recents.count == 6)
        #expect(recents.map(\.id) == (0..<6).map { "a\($0)" })
    }

    @Test("returns all activities when fewer than the cap")
    func fewerThanCap() {
        let activities = (0..<3).map { Activity(id: "a\($0)", name: "Activity \($0)") }
        let recents = RecentActivitiesChips.recents(from: activities)
        #expect(recents.count == 3)
        #expect(recents.map(\.id) == activities.map(\.id))
    }

    @Test("returns nothing for an empty input")
    func emptyInput() {
        #expect(RecentActivitiesChips.recents(from: []).isEmpty)
    }

    @Test("preserves the store-sorted order exactly")
    func preservesOrder() {
        let activities = [
            Activity(id: "oldest", name: "Oldest"),
            Activity(id: "middle", name: "Middle"),
            Activity(id: "newest", name: "Newest")
        ]
        #expect(RecentActivitiesChips.recents(from: activities).map(\.id) == ["oldest", "middle", "newest"])
    }

    @Test("honours a custom limit")
    func customLimit() {
        let activities = (0..<4).map { Activity(id: "a\($0)", name: "Activity \($0)") }
        #expect(RecentActivitiesChips.recents(from: activities, limit: 2).count == 2)
    }
}
