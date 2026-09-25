import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("InsightsViewModel")
struct InsightsViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1")))
    }

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

    /// Monday-start week so `weekOfYear` boundaries are deterministic
    /// regardless of the device locale.
    private func mondayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: - Hero totals per period

    @Test("hero equals the committed sum for each period")
    func heroPerPeriod() async throws {
        let calendar = mondayCalendar()
        // Thursday 2026-09-03 15:00.
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        for (id, start, seconds) in [
            ("today", Self.date("2026-09-03 09:00", calendar: calendar), 3600),
            ("yesterday", Self.date("2026-09-02 10:00", calendar: calendar), 1800),
            ("last-week", Self.date("2026-08-25 10:00", calendar: calendar), 600)
        ] as [(String, Date, Int)] {
            try await store.createEntry(entry(
                id: id, startedAt: start,
                durationSeconds: seconds, endedAt: start.addingTimeInterval(TimeInterval(seconds))))
        }
        // In-progress entries never contribute.
        try await store.createEntry(entry(
            id: "running", startedAt: Self.date("2026-09-03 14:00", calendar: calendar)))

        let vm = InsightsViewModel(store: store) { now }
        await vm.loadIfNeeded()

        #expect(vm.hasCommittedAllTime)
        #expect(vm.breakdown(period: .today, lens: .activity, calendar: calendar).totalSeconds == 3600)
        #expect(vm.breakdown(period: .week, lens: .activity, calendar: calendar).totalSeconds == 5400)
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 6000)
    }

    // MARK: - Lenses share one snapshot

    @Test("lens switch preserves the period and attributes from entry-owned categories")
    func lensSwitchPreservesPeriod() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        try await store.createCategory(Category(id: "c1", name: "Work", icon: "briefcase"))
        try await store.createCategory(Category(id: "c2", name: "Study", icon: "book"))
        let start = Self.date("2026-09-03 09:00", calendar: calendar)
        try await store.createEntry(entry(
            id: "e1", startedAt: start, text: "Course", categoryIDs: ["c1", "c2"],
            durationSeconds: 3600, endedAt: start.addingTimeInterval(3600)))

        let vm = InsightsViewModel(store: store) { now }
        await vm.loadIfNeeded()

        let categories = vm.breakdown(period: .week, lens: .category, calendar: calendar)
        let activities = vm.breakdown(period: .week, lens: .activity, calendar: calendar)
        #expect(categories.totalSeconds == activities.totalSeconds)
        #expect(categories.rows.count == 2)
        #expect(activities.rows.count == 1)
        #expect(activities.rows.first?.name == "Course")
        #expect(activities.rows.reduce(0) { $0 + $1.totalSeconds } == activities.totalSeconds)
    }

    // MARK: - Reload contract (loadIfNeeded / invalidate)

    @Test("loadIfNeeded serves the cached snapshot until invalidate, then reloads")
    func reloadAfterInvalidate() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(entry(
            id: "e1", startedAt: start,
            durationSeconds: 60, endedAt: start.addingTimeInterval(60)))

        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 60)

        // Entry saved elsewhere (Track tab, compact timer) while Insights is
        // off-screen must not leak into the cached snapshot…
        try await store.createEntry(entry(
            id: "e2", startedAt: Date(timeIntervalSinceNow: -600),
            durationSeconds: 30, endedAt: Date(timeIntervalSinceNow: -570)))
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 60)

        // …but appears after invalidate (Insights re-appears) + loadIfNeeded.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 90)
    }

    // MARK: - Empty store

    @Test("empty store reports no committed time but counts as loaded")
    func emptyStore() async throws {
        let store = try makeStore()
        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()

        #expect(vm.hasLoaded)
        #expect(!vm.hasCommittedAllTime)
        let breakdown = vm.breakdown(period: .week, lens: .category)
        #expect(breakdown.totalSeconds == 0)
        #expect(breakdown.rows.isEmpty)
    }

    // MARK: - Sync merge propagation (fix-history-sync-refresh)

    @Test("synced pull recomputes the breakdown after invalidate + reload")
    func syncMergeReflectedAfterReload() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(entry(
            id: "local", startedAt: start,
            durationSeconds: 60, endedAt: start.addingTimeInterval(60)))

        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 60)

        // A sync pull merges a cross-device entry behind the visible screen.
        let remoteStart = Date(timeIntervalSinceNow: -600)
        try await store.mergeEntry(entry(
            id: "remote", startedAt: remoteStart, text: "Remote",
            durationSeconds: 30, endedAt: remoteStart.addingTimeInterval(30)))
        // The guarded snapshot hides it — the stale-breakdown bug.
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 60)

        // The view's sync observer runs invalidate + loadIfNeeded on cycle end.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 90)
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
