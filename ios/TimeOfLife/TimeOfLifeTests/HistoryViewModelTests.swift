import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("HistoryViewModel")
struct HistoryViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }

    private func entry(
        id: String,
        startedAt: Date,
        text: String? = nil,
        categoryIDs: [String] = [],
        durationSeconds: Int? = nil,
        endedAt: Date? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text ?? "Entry \(id)",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            categoryIDs: categoryIDs
        )
    }

    // MARK: - Day grouping (D2)

    @Test("groups entries by calendar day, newest day first, newest entry first")
    func groupsByDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let groups = HistoryViewModel.makeDayGroups(
            entries: [
                entry(id: "old-day-b", startedAt: Self.date("2026-08-31 10:00", calendar: calendar)),
                entry(id: "today-a", startedAt: Self.date("2026-09-03 08:00", calendar: calendar)),
                entry(id: "old-day-a", startedAt: Self.date("2026-08-31 18:00", calendar: calendar)),
                entry(id: "today-b", startedAt: Self.date("2026-09-03 12:00", calendar: calendar))
            ],
            now: now,
            calendar: calendar
        )

        #expect(groups.count == 2)
        #expect(groups[0].id == "2026-09-03")
        #expect(groups[0].entries.map(\.id) == ["today-b", "today-a"])
        #expect(groups[1].id == "2026-08-31")
        #expect(groups[1].entries.map(\.id) == ["old-day-a", "old-day-b"])
    }

    @Test("empty entries produce no groups")
    func emptyEntries() {
        let groups = HistoryViewModel.makeDayGroups(entries: [], now: Date())
        #expect(groups.isEmpty)
    }

    @Test("entries on the same day across midnight boundaries group by startedAt day")
    func midnightBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 12:00", calendar: calendar)
        let groups = HistoryViewModel.makeDayGroups(
            entries: [
                entry(id: "late", startedAt: Self.date("2026-09-02 23:30", calendar: calendar)),
                entry(id: "early", startedAt: Self.date("2026-09-03 00:10", calendar: calendar))
            ],
            now: now,
            calendar: calendar
        )
        #expect(groups.count == 2)
        #expect(groups[0].id == "2026-09-03")
        #expect(groups[1].id == "2026-09-02")
    }

    // MARK: - Day labels (D3)

    @Test("today and yesterday use relative labels")
    func relativeLabels() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        #expect(HistoryViewModel.dayLabel(
            for: Self.date("2026-09-03 00:00", calendar: calendar),
            now: now,
            calendar: calendar
        ) == L10n.historyDayToday.text)
        #expect(HistoryViewModel.dayLabel(
            for: Self.date("2026-09-02 23:59", calendar: calendar),
            now: now,
            calendar: calendar
        ) == L10n.historyDayYesterday.text)
    }

    @Test("older days use the regional absolute date")
    func absoluteLabels() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let label = HistoryViewModel.dayLabel(
            for: Self.date("2026-08-31 10:00", calendar: calendar),
            now: now,
            calendar: calendar
        )
        #expect(label != L10n.historyDayToday.text)
        #expect(label != L10n.historyDayYesterday.text)
        #expect(!label.isEmpty)
    }

    // MARK: - Day totals (D8)

    @Test("day total sums known durations")
    func dayTotalSumsDurations() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let groups = HistoryViewModel.makeDayGroups(
            entries: [
                entry(id: "a", startedAt: Self.date("2026-09-03 09:00", calendar: calendar), durationSeconds: 4800),
                entry(id: "b", startedAt: Self.date("2026-09-03 14:00", calendar: calendar), durationSeconds: 1200)
            ],
            now: now,
            calendar: calendar
        )
        #expect(groups[0].total == "1h 40m")
    }

    @Test("in-progress entries contribute zero to the day total")
    func inProgressContributesZero() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let groups = HistoryViewModel.makeDayGroups(
            entries: [
                entry(id: "done", startedAt: Self.date("2026-09-03 09:00", calendar: calendar), durationSeconds: 4800),
                entry(id: "running", startedAt: Self.date("2026-09-03 14:00", calendar: calendar))
            ],
            now: now,
            calendar: calendar
        )
        #expect(groups[0].total == "1h 20m")
    }

    @Test("empty day total is 0s")
    func emptyDayTotal() {
        let total = HistoryViewModel.naturalDuration(0)
        #expect(total == "0s")
    }

    // MARK: - Entry-owned category resolution (remove-activities-layer 4.4)

    @Test("rows read categories from the entry itself, position-preserved")
    func loadsAndResolvesCategories() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "c1", name: "Health", icon: "figure.run"))
        try await store.createCategory(Category(id: "c2", name: "Work", icon: "briefcase"))
        try await store.createEntry(entry(
            id: "e1",
            startedAt: Date(timeIntervalSinceNow: -3600),
            text: "Running",
            categoryIDs: ["c2", "c1"],
            durationSeconds: 3600,
            endedAt: Date()
        ))
        try await store.createEntry(entry(
            id: "e2",
            startedAt: Date(timeIntervalSinceNow: -7200),
            text: "Meditation",
            durationSeconds: 600,
            endedAt: Date(timeIntervalSinceNow: -6000)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.load()

        #expect(vm.dayGroups.count == 1)
        #expect(vm.dayGroups[0].entries.count == 2)

        let running = vm.dayGroups[0].entries.first { $0.id == "e1" }!
        #expect(vm.icon(for: running) == "briefcase")
        #expect(vm.categoryNames(for: running) == "Work, Health")

        let meditation = vm.dayGroups[0].entries.first { $0.id == "e2" }!
        #expect(vm.icon(for: meditation) == "questionmark")
        #expect(vm.categoryNames(for: meditation).isEmpty)
    }

    @Test("a deleted category vanishes from rows while entries survive")
    func deletedCategoryStripsRows() async throws {
        let store = try makeStore()
        try await store.createCategory(Category(id: "c1", name: "Health", icon: "figure.run"))
        try await store.createEntry(entry(
            id: "e1",
            startedAt: Date(timeIntervalSinceNow: -3600),
            text: "Running",
            categoryIDs: ["c1"],
            durationSeconds: 60,
            endedAt: Date(timeIntervalSinceNow: -3540)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.categoryNames(for: vm.dayGroups[0].entries[0]) == "Health")

        try await store.deleteCategory(id: "c1")
        vm.invalidate()
        await vm.loadIfNeeded()

        #expect(vm.dayGroups.count == 1)
        #expect(vm.icon(for: vm.dayGroups[0].entries[0]) == "questionmark")
        #expect(vm.categoryNames(for: vm.dayGroups[0].entries[0]).isEmpty)
    }

    @Test("in-progress entry shows the in-progress indicator")
    func inProgressDisplay() async throws {
        let store = try makeStore()
        try await store.createEntry(entry(id: "e1", startedAt: Date(timeIntervalSinceNow: -60)))

        let vm = HistoryViewModel(store: store)
        await vm.load()

        let running = vm.dayGroups[0].entries[0]
        #expect(vm.isInProgress(running))
        #expect(vm.durationText(for: running) == L10n.historyInProgress.text)
        #expect(vm.timeframeText(for: running).contains(L10n.historyInProgress.text))
    }

    // MARK: - Reload contract (loadIfNeeded / invalidate)

    @Test("loadIfNeeded serves the cached snapshot until invalidate, then reloads")
    func reloadAfterInvalidate() async throws {
        let store = try makeStore()
        try await store.createEntry(entry(
            id: "e1",
            startedAt: Date(timeIntervalSinceNow: -3600),
            durationSeconds: 60,
            endedAt: Date(timeIntervalSinceNow: -3540)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        // Entry saved elsewhere (Track tab, compact timer) while History is
        // off-screen must not leak into the cached snapshot…
        try await store.createEntry(entry(
            id: "e2",
            startedAt: Date(timeIntervalSinceNow: -600),
            durationSeconds: 30,
            endedAt: Date(timeIntervalSinceNow: -570)
        ))
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        // …but appears after invalidate (History re-appears) + loadIfNeeded.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e1"])
    }

    // MARK: - Entry edit/delete propagation (entry-editor)

    @Test("edited entry values appear after invalidate + reload")
    func editedEntryReflectedAfterReload() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(entry(
            id: "e1",
            startedAt: start,
            durationSeconds: 60,
            endedAt: start.addingTimeInterval(60)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.durationText(for: vm.dayGroups[0].entries[0]) == "1m")

        // Edit behind the entry form cover (the updateEntry path).
        var updated = try #require(try await store.entry(id: "e1"))
        updated.endedAt = start.addingTimeInterval(3_700)
        updated.durationSeconds = 3_700
        updated.updatedAt = Date()
        #expect(try await store.updateEntry(updated))

        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        #expect(vm.durationText(for: vm.dayGroups[0].entries[0]) == "1h 1m")
    }

    @Test("deleted entry disappears and empties its day group after reload")
    func deletedEntryRemovedAfterReload() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(entry(
            id: "e1",
            startedAt: start,
            durationSeconds: 60,
            endedAt: start.addingTimeInterval(60)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.count == 1)

        // Delete behind the entry form (the undoable path).
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())

        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.isEmpty)
    }

    // MARK: - Sync merge propagation (fix-history-sync-refresh)

    @Test("synced pull appears and tombstone deletion disappears after invalidate + reload")
    func syncMergeReflectedAfterReload() async throws {
        let store = try makeStore()
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(entry(
            id: "local",
            startedAt: start,
            durationSeconds: 60,
            endedAt: start.addingTimeInterval(60)
        ))

        let vm = HistoryViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["local"])

        // A sync pull merges a cross-device entry behind the visible list.
        let remoteStart = Date(timeIntervalSinceNow: -600)
        try await store.mergeEntry(entry(
            id: "remote",
            startedAt: remoteStart,
            text: "Remote",
            durationSeconds: 30,
            endedAt: remoteStart.addingTimeInterval(30)
        ))
        // The guarded snapshot hides it — the stale-list bug.
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["local"])

        // The view's sync observer runs invalidate + loadIfNeeded on cycle end.
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["remote", "local"])

        // A tombstone for a cross-device delete converges on the next cycle.
        try await store.applyDeletionTombstone(Deletion(
            resource: "entry",
            recordID: "remote",
            deletedAt: Date()
        ))
        vm.invalidate()
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["local"])
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
