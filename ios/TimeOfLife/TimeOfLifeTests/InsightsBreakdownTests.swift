import Testing
import Foundation
@testable import TimeOfLife

@Suite("InsightsBreakdown")
struct InsightsBreakdownTests {

    private func entry(
        id: String,
        startedAt: Date,
        activityID: String = "a1",
        activityName: String? = nil,
        durationSeconds: Int? = nil,
        endedAt: Date? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityID: activityID,
            activityName: activityName ?? "Activity \(activityID)",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds
        )
    }

    private func makeActivity(id: String, name: String, categoryIDs: [String] = []) -> Activity {
        Activity(id: id, name: name, categoryIDs: categoryIDs)
    }

    private func makeCategory(id: String, name: String, icon: String = "briefcase") -> TimeOfLife.Category {
        TimeOfLife.Category(id: id, name: name, icon: icon)
    }

    /// Monday-start week so `weekOfYear` boundaries are deterministic
    /// regardless of the device locale.
    private func mondayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: - Period intervals (1.1)

    @Test("today covers the full calendar day, week the locale week, all is unbounded")
    func periodIntervals() {
        let calendar = mondayCalendar()
        // Thursday 2026-09-03 15:00.
        let now = Self.date("2026-09-03 15:00", calendar: calendar)

        let today = InsightsPeriod.today.interval(now: now, calendar: calendar)!
        #expect(today.start == Self.date("2026-09-03 00:00", calendar: calendar))
        #expect(today.end == Self.date("2026-09-04 00:00", calendar: calendar))

        let week = InsightsPeriod.week.interval(now: now, calendar: calendar)!
        #expect(week.start == Self.date("2026-08-31 00:00", calendar: calendar))
        #expect(week.end == Self.date("2026-09-07 00:00", calendar: calendar))

        #expect(InsightsPeriod.all.interval(now: now, calendar: calendar) == nil)
    }

    // MARK: - Period filtering

    @Test("periods filter by startedAt: today, week, all")
    func periodFiltering() {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let activities = [makeActivity(id: "a1", name: "Reading")]
        let entries = [
            entry(id: "today", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                  durationSeconds: 3600, endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
            entry(id: "future-today", startedAt: Self.date("2026-09-03 20:00", calendar: calendar),
                  durationSeconds: 300, endedAt: Self.date("2026-09-03 20:05", calendar: calendar)),
            entry(id: "yesterday", startedAt: Self.date("2026-09-02 10:00", calendar: calendar),
                  durationSeconds: 1800, endedAt: Self.date("2026-09-02 10:30", calendar: calendar)),
            entry(id: "last-week", startedAt: Self.date("2026-08-25 10:00", calendar: calendar),
                  durationSeconds: 600, endedAt: Self.date("2026-08-25 10:10", calendar: calendar))
        ]

        let today = InsightsViewModel.makeBreakdown(
            entries: entries, activities: activities, categories: [],
            interval: InsightsPeriod.today.interval(now: now, calendar: calendar), lens: .activity)
        // Future-dated entries count by startedAt with no special-casing.
        #expect(today.totalSeconds == 3900)
        #expect(today.rows.map(\.id) == ["a1"])

        let week = InsightsViewModel.makeBreakdown(
            entries: entries, activities: activities, categories: [],
            interval: InsightsPeriod.week.interval(now: now, calendar: calendar), lens: .activity)
        #expect(week.totalSeconds == 5700)

        let all = InsightsViewModel.makeBreakdown(
            entries: entries, activities: activities, categories: [],
            interval: nil, lens: .activity)
        #expect(all.totalSeconds == 6300)
    }

    // MARK: - Committed only

    @Test("in-progress entries are excluded; nil durations contribute zero")
    func committedOnly() {
        let calendar = mondayCalendar()
        let activities = [makeActivity(id: "a1", name: "Reading")]
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "done", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "running", startedAt: Self.date("2026-09-03 14:00", calendar: calendar),
                      activityID: "a1"),
                entry(id: "no-duration", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      activityID: "a1",
                      endedAt: Self.date("2026-09-03 11:05", calendar: calendar))
            ],
            activities: activities,
            categories: [],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.totalSeconds == 3600)
        #expect(breakdown.rows.count == 1)
        #expect(breakdown.rows[0].totalSeconds == 3600)
        #expect(breakdown.rows[0].entryIDs == ["done", "no-duration"])
    }

    // MARK: - Category lens: full credit

    @Test("multi-category entry counts fully toward every attached category")
    func fullCreditAttribution() {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "e2", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      activityID: "a2", durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 11:10", calendar: calendar))
            ],
            activities: [
                makeActivity(id: "a1", name: "Course", categoryIDs: ["c1", "c2"]),
                makeActivity(id: "a2", name: "Run", categoryIDs: ["c2"])
            ],
            categories: [
                makeCategory(id: "c1", name: "Education"),
                makeCategory(id: "c2", name: "Sport", icon: "figure.run")
            ],
            interval: InsightsPeriod.week.interval(now: now, calendar: calendar),
            lens: .category
        )
        // Hero is the unique tracked time; rows overlap by design.
        #expect(breakdown.totalSeconds == 4200)
        let byID: [String: InsightsBucket] = Dictionary(uniqueKeysWithValues: breakdown.rows.map { ($0.id, $0) })
        #expect(byID["c1"]?.totalSeconds == 3600)
        #expect(byID["c2"]?.totalSeconds == 4200)
        #expect(byID["c1"]?.entryIDs == ["e1"])
        #expect(byID["c2"]?.entryIDs == ["e1", "e2"])
        #expect(byID["c2"]?.icon == "figure.run")
    }

    @Test("activities without categories aggregate into the uncategorized bucket")
    func uncategorizedBucket() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 09:10", calendar: calendar))
            ],
            activities: [makeActivity(id: "a1", name: "Staring")],
            categories: [makeCategory(id: "c1", name: "Work")],
            interval: nil,
            lens: .category
        )
        #expect(breakdown.rows.count == 1)
        #expect(breakdown.rows[0].id == InsightsBucket.uncategorizedID)
        #expect(breakdown.rows[0].name == L10n.insightsNoCategory.text)
        #expect(breakdown.rows[0].icon == "questionmark")
        #expect(breakdown.rows[0].totalSeconds == 600)
    }

    @Test("dangling category references fall back to the uncategorized bucket")
    func danglingCategoryIDs() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 09:10", calendar: calendar))
            ],
            activities: [makeActivity(id: "a1", name: "Reading", categoryIDs: ["deleted"])],
            categories: [makeCategory(id: "c1", name: "Work")],
            interval: nil,
            lens: .category
        )
        #expect(breakdown.rows.map(\.id) == [InsightsBucket.uncategorizedID])
    }

    // MARK: - Activity lens

    @Test("activity rows sum to the hero and use first-category icons")
    func activityLens() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "e2", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      activityID: "a1", durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 11:10", calendar: calendar)),
                entry(id: "e3", startedAt: Self.date("2026-09-03 12:00", calendar: calendar),
                      activityID: "a2", durationSeconds: 1200,
                      endedAt: Self.date("2026-09-03 12:20", calendar: calendar))
            ],
            activities: [
                makeActivity(id: "a1", name: "Reading", categoryIDs: ["c1"]),
                makeActivity(id: "a2", name: "Meditation")
            ],
            categories: [makeCategory(id: "c1", name: "Education", icon: "book")],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.totalSeconds == 5400)
        #expect(breakdown.rows.reduce(0) { $0 + $1.totalSeconds } == breakdown.totalSeconds)
        #expect(breakdown.rows.map(\.id) == ["a1", "a2"])
        #expect(breakdown.rows[0].icon == "book")
        #expect(breakdown.rows[1].icon == "questionmark")
        #expect(breakdown.rows[0].entryIDs == ["e1", "e2"])
    }

    @Test("activity missing from the catalog falls back to the entry activity name")
    func unknownActivityFallback() {
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Date(timeIntervalSinceNow: -3600),
                      activityID: "gone", activityName: "Deleted",
                      durationSeconds: 60, endedAt: Date(timeIntervalSinceNow: -3540))
            ],
            activities: [],
            categories: [],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.rows.count == 1)
        #expect(breakdown.rows[0].name == "Deleted")
        #expect(breakdown.rows[0].icon == "questionmark")
    }

    // MARK: - Ordering and emptiness

    @Test("rows sort biggest-first with name tiebreak; empty input yields zero total")
    func orderingAndEmpty() {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: start, activityID: "b-id",
                      durationSeconds: 600, endedAt: start.addingTimeInterval(600)),
                entry(id: "e2", startedAt: start, activityID: "a-id",
                      durationSeconds: 600, endedAt: start.addingTimeInterval(600)),
                entry(id: "e3", startedAt: start, activityID: "c-id",
                      durationSeconds: 60, endedAt: start.addingTimeInterval(60))
            ],
            activities: [
                makeActivity(id: "b-id", name: "Beta"),
                makeActivity(id: "a-id", name: "Alpha"),
                makeActivity(id: "c-id", name: "Gamma")
            ],
            categories: [],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.rows.map(\.name) == ["Alpha", "Beta", "Gamma"])

        let empty = InsightsViewModel.makeBreakdown(
            entries: [], activities: [], categories: [], interval: nil, lens: .category)
        #expect(empty.totalSeconds == 0)
        #expect(empty.rows.isEmpty)
    }

    // MARK: - Helpers

    private static func date(_ iso: String, calendar: Calendar) -> Date {
        let parts = iso.split(separator: " ")
        let dateParts = parts[0].split(separator: "-").compactMap { Int($0) }
        let timeParts = parts[1].split(separator: ":").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = dateParts[0]
        comps.month = dateParts[1]
        comps.day = dateParts[2]
        comps.hour = timeParts[0]
        comps.minute = timeParts[1]
        comps.calendar = calendar
        return comps.date!
    }
}
