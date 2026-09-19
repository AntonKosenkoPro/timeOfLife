import Testing
import Foundation
@testable import TimeOfLife

@Suite("InsightsBreakdown")
struct InsightsBreakdownTests {

    private func entry(
        id: String,
        startedAt: Date,
        text: String = "Reading",
        categoryIDs: [String] = [],
        durationSeconds: Int? = nil,
        endedAt: Date? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            categoryIDs: categoryIDs
        )
    }

    private func makeCategory(id: String, name: String, icon: String = "briefcase") -> Category {
        Category(id: id, name: name, icon: icon)
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
            entries: entries, categories: [],
            interval: InsightsPeriod.today.interval(now: now, calendar: calendar), lens: .activity)
        // Future-dated entries count by startedAt with no special-casing.
        #expect(today.totalSeconds == 3900)
        #expect(today.rows.count == 1)

        let week = InsightsViewModel.makeBreakdown(
            entries: entries, categories: [],
            interval: InsightsPeriod.week.interval(now: now, calendar: calendar), lens: .activity)
        #expect(week.totalSeconds == 5700)

        let all = InsightsViewModel.makeBreakdown(
            entries: entries, categories: [],
            interval: nil, lens: .activity)
        #expect(all.totalSeconds == 6300)
    }

    // MARK: - Committed only

    @Test("in-progress entries are excluded; nil durations contribute zero")
    func committedOnly() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "done", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "running", startedAt: Self.date("2026-09-03 14:00", calendar: calendar)),
                entry(id: "no-duration", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      endedAt: Self.date("2026-09-03 11:05", calendar: calendar))
            ],
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
                      categoryIDs: ["c1", "c2"], durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "e2", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      categoryIDs: ["c2"], durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 11:10", calendar: calendar))
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

    @Test("entries without categories aggregate into the uncategorized bucket")
    func uncategorizedBucket() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 09:10", calendar: calendar))
            ],
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
                      categoryIDs: ["deleted"], durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 09:10", calendar: calendar))
            ],
            categories: [makeCategory(id: "c1", name: "Work")],
            interval: nil,
            lens: .category
        )
        #expect(breakdown.rows.map(\.id) == [InsightsBucket.uncategorizedID])
    }

    // MARK: - Activity lens: exact-text grouping (remove-activities-layer 4.5)

    @Test("activity rows group by exact text, sum to the hero, and use entry-owned icons")
    func activityLens() {
        let calendar = mondayCalendar()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Self.date("2026-09-03 09:00", calendar: calendar),
                      text: "Reading", categoryIDs: ["c1"], durationSeconds: 3600,
                      endedAt: Self.date("2026-09-03 10:00", calendar: calendar)),
                entry(id: "e2", startedAt: Self.date("2026-09-03 11:00", calendar: calendar),
                      text: "Reading", durationSeconds: 600,
                      endedAt: Self.date("2026-09-03 11:10", calendar: calendar)),
                entry(id: "e3", startedAt: Self.date("2026-09-03 12:00", calendar: calendar),
                      text: "Meditation", durationSeconds: 1200,
                      endedAt: Self.date("2026-09-03 12:20", calendar: calendar))
            ],
            categories: [makeCategory(id: "c1", name: "Education", icon: "book")],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.totalSeconds == 5400)
        #expect(breakdown.rows.reduce(0) { $0 + $1.totalSeconds } == breakdown.totalSeconds)
        #expect(breakdown.rows.map(\.name) == ["Reading", "Meditation"])
        #expect(breakdown.rows[0].icon == "book")
        #expect(breakdown.rows[1].icon == "questionmark")
        #expect(breakdown.rows[0].entryIDs == ["e1", "e2"])
    }

    @Test("Gym and GYM are distinct activity-lens rows")
    func exactTextIdentity() {
        let now = Date()
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: now.addingTimeInterval(-3600), text: "Gym",
                      durationSeconds: 600, endedAt: now.addingTimeInterval(-3000)),
                entry(id: "e2", startedAt: now.addingTimeInterval(-1800), text: "GYM",
                      durationSeconds: 300, endedAt: now.addingTimeInterval(-1500))
            ],
            categories: [],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.rows.count == 2)
        #expect(Set(breakdown.rows.map(\.name)) == ["Gym", "GYM"])
        #expect(breakdown.rows.reduce(0) { $0 + $1.totalSeconds } == 900)
    }

    @Test("retagging one entry never reclassifies another same-text entry")
    func perEntryIsolation() {
        // e1 owns c1; e2 owns nothing. Both share the exact text — the
        // category lens must attribute each entry's own categories only.
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: Date(timeIntervalSinceNow: -3600), text: "Reading",
                      categoryIDs: ["c1"], durationSeconds: 600, endedAt: Date(timeIntervalSinceNow: -3000)),
                entry(id: "e2", startedAt: Date(timeIntervalSinceNow: -1800), text: "Reading",
                      durationSeconds: 300, endedAt: Date(timeIntervalSinceNow: -1500))
            ],
            categories: [makeCategory(id: "c1", name: "Work")],
            interval: nil,
            lens: .category
        )
        let byID: [String: InsightsBucket] = Dictionary(uniqueKeysWithValues: breakdown.rows.map { ($0.id, $0) })
        #expect(byID["c1"]?.entryIDs == ["e1"])
        #expect(byID[InsightsBucket.uncategorizedID]?.entryIDs == ["e2"])
    }

    // MARK: - Ordering and emptiness

    @Test("rows sort biggest-first with name tiebreak; empty input yields zero total")
    func orderingAndEmpty() {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let breakdown = InsightsViewModel.makeBreakdown(
            entries: [
                entry(id: "e1", startedAt: start, text: "Beta",
                      durationSeconds: 600, endedAt: start.addingTimeInterval(600)),
                entry(id: "e2", startedAt: start, text: "Alpha",
                      durationSeconds: 600, endedAt: start.addingTimeInterval(600)),
                entry(id: "e3", startedAt: start, text: "Gamma",
                      durationSeconds: 60, endedAt: start.addingTimeInterval(60))
            ],
            categories: [],
            interval: nil,
            lens: .activity
        )
        #expect(breakdown.rows.map(\.name) == ["Alpha", "Beta", "Gamma"])

        let empty = InsightsViewModel.makeBreakdown(
            entries: [], categories: [], interval: nil, lens: .category)
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
