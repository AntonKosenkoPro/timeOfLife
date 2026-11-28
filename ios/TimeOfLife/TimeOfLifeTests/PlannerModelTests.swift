import Testing
import Foundation
@testable import TimeOfLife

@Suite("Planner position keys (parity with relay fixtures)")
struct PlannerPositionKeyTests {
    @Test("Shared fixtures match the relay contract exactly")
    func sharedFixtures() {
        #expect(PlannerPositionKey.allocate(before: nil, after: nil) == "500000")
        #expect(PlannerPositionKey.allocate(before: "500000", after: nil) == "500001")
        #expect(PlannerPositionKey.allocate(before: "500001", after: nil) == "500002")
        #expect(PlannerPositionKey.allocate(before: "500000", after: "500001") == "500000.5")
        #expect(PlannerPositionKey.allocate(before: "500000", after: "500000.5") == "500000.25")
        #expect(PlannerPositionKey.allocate(before: "500000.5", after: "500001") == "500000.75")
        #expect(PlannerPositionKey.allocate(before: nil, after: "500000") == "499999")
    }

    @Test("Allocated keys validate and order byte-wise like numeric order")
    func ordering() {
        let keys = ["499999", "500000", "500000.25", "500000.5", "500000.75", "500001"]
        for key in keys {
            #expect(PlannerPositionKey.validate(key), "must validate: \(key)")
        }
        #expect(keys == keys.sorted())
        // A midpoint always lands strictly inside its gap.
        let mid = PlannerPositionKey.allocate(before: "500000", after: "500001")
        #expect(mid != nil && mid! > "500000" && mid! < "500001")
    }

    @Test("Validation rejects non-canonical keys")
    func validation() {
        for key in ["500000", "000000", "999999", "500000.5", "499999.000000000000000000000000000001"] {
            #expect(PlannerPositionKey.validate(key))
        }
        for key in ["", "50000", "5000000", "500000.", "500000.50", "500000.0", "abc", "500000.5 ", "-1", "50000a"] {
            #expect(!PlannerPositionKey.validate(key), "must reject: \(key)")
        }
        #expect(PlannerPositionKey.allocate(before: "abc", after: nil) == nil)
        #expect(PlannerPositionKey.allocate(before: "500001", after: "500000") == nil)
    }

    @Test("Repeated bisection in one gap stays exact")
    func bisection() throws {
        var low = "500000", high = "500001"
        var last = ""
        for _ in 0..<12 {
            let mid = PlannerPositionKey.allocate(before: low, after: high)
            let key = try #require(mid)
            #expect(PlannerPositionKey.validate(key))
            #expect(key > low && key < high)
            #expect(key != last)
            last = key
            low = key
        }
    }
}

@Suite("Planner Today projection")
struct PlannerTodayTests {
    private func task(_ name: String, key: String, completedOn: String? = nil) -> PlannerTask {
        PlannerTask(
            id: "id-\(name)-\(key)", name: name, positionKey: key,
            completedOn: completedOn, createdAt: Date(), updatedAt: Date()
        )
    }

    @Test("Shows unfinished plus today's completions in shared order")
    func projection() {
        let tasks = [
            task("A", key: "500001"),
            task("B", key: "500000"),
            task("C", key: "500002", completedOn: "2026-11-25"),
            task("Old", key: "499999", completedOn: "2026-11-20"),
        ]
        let snapshot = PlannerToday.project(tasks: tasks, on: "2026-11-25")
        #expect(snapshot.tasks.map(\.name) == ["B", "A", "C"])
        #expect(snapshot.done == 1)
        #expect(snapshot.total == 3)
    }

    @Test("Order ties break identically on task id")
    func tieBreak() {
        let first = PlannerTask(
            id: "aaa", name: "X", positionKey: "500000",
            createdAt: Date(), updatedAt: Date()
        )
        let second = PlannerTask(
            id: "zzz", name: "X", positionKey: "500000",
            createdAt: Date(), updatedAt: Date()
        )
        let snapshot = PlannerToday.project(tasks: [second, first], on: "2026-11-25")
        #expect(snapshot.tasks.map(\.id) == ["aaa", "zzz"])
    }

    @Test("A completion stays visible only on its date")
    func completionDay() {
        let tasks = [task("C", key: "500000", completedOn: "2026-11-25")]
        #expect(PlannerToday.project(tasks: tasks, on: "2026-11-25").tasks.count == 1)
        #expect(PlannerToday.project(tasks: tasks, on: "2026-11-26").tasks.isEmpty)
    }

    @Test("Civil dates are Gregorian local dates")
    func civilDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
        #expect(PlannerCivilDate.today(on: date, timeZone: TimeZone(identifier: "America/New_York")!) == "2026-11-25")
        #expect(PlannerCivilDate.today(on: date).count == 10)
    }
}
