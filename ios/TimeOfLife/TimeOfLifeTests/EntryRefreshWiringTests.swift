import Testing
import Foundation
@testable import TimeOfLife

/// Regression coverage for the event-driven refresh contract that replaces
/// the compact timer's `refreshSignal` (remove-compact-timer, group 2).
///
/// History/Insights must surface committed saves through the existing
/// invalidate + guarded-reload flow alone — no tab switch (no
/// onDisappear/onAppear cycle) required — whether the save lands while the
/// tab is visible (existing external-stop path) or while the app is
/// suspended (picked up on foreground return). Covers empty-to-populated
/// and already-populated snapshots; repeated events must not blank content
/// or disturb Insights period/lens derivation.
@MainActor
@Suite("Entry Refresh Wiring (remove-compact-timer)")
struct EntryRefreshWiringTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1")))
    }

    /// A committed save through the real stop path (the same
    /// `stopTimerDraft` every Stop path — Track, Island intent, external
    /// stop — flows through), with a fixed anchor so durations are exact.
    private func commitStop(
        service: TimerService,
        text: String,
        startedAt: Date,
        duration: TimeInterval
    ) async throws {
        try await service.startTimerDraft(text: text, categoryIDs: [], startedAt: startedAt)
        try await service.stopTimerDraft(
            text: text,
            categoryIDs: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration)
        )
    }

    // MARK: - History: external-stop save while visible

    @Test("external-stop save appears on visible History without a tab switch")
    func historyExternalStopWhileVisible() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Earlier",
            startedAt: start, endedAt: start.addingTimeInterval(60),
            durationSeconds: 60, categoryIDs: []
        ))

        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        // External-stop path commits while History stays visible: no
        // onDisappear/onAppear fires, only the event-driven invalidate +
        // guarded reload the view runs on `.timerStoppedExternally`.
        let runStart = Date(timeIntervalSinceNow: -120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        vm.invalidate()
        await vm.loadIfNeeded()

        let ids = vm.dayGroups.flatMap(\.entries).map(\.id)
        #expect(ids.count == 2)
        #expect(vm.dayGroups.flatMap(\.entries).first?.activityText == "Deep work")
    }

    @Test("external-stop save populates empty History without a tab switch")
    func historyEmptyToPopulated() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.isEmpty)

        let runStart = Date(timeIntervalSinceNow: -90)
        try await commitStop(service: service, text: "First run", startedAt: runStart, duration: 90)
        vm.invalidate()
        await vm.loadIfNeeded()

        #expect(vm.dayGroups.count == 1)
        #expect(vm.dayGroups.first?.entries.first?.activityText == "First run")
    }

    @Test("repeated refresh events never blank populated History")
    func historyRepeatedEventsKeepContent() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Earlier",
            startedAt: start, endedAt: start.addingTimeInterval(60),
            durationSeconds: 60, categoryIDs: []
        ))
        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.loadIfNeeded()

        // Foreground return, sync exit, and external stop can fire back to
        // back; each is an invalidate + guarded reload with no save between.
        for _ in 0..<3 {
            vm.invalidate()
            await vm.loadIfNeeded()
        }
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        let runStart = Date(timeIntervalSinceNow: -30)
        try await commitStop(service: service, text: "Later", startedAt: runStart, duration: 30)
        for _ in 0..<3 {
            vm.invalidate()
            await vm.loadIfNeeded()
        }
        #expect(vm.dayGroups.flatMap(\.entries).count == 2)
    }

    @Test("save while suspended appears on History after foreground refresh")
    func historyBackgroundedSaveOnForeground() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.isEmpty)

        // The stop commits while the app is suspended (no observer runs);
        // the foreground return invalidates and reloads once.
        let runStart = Date(timeIntervalSinceNow: -600)
        try await commitStop(service: service, text: "Background run", startedAt: runStart, duration: 600)
        vm.invalidate()
        await vm.loadIfNeeded()

        #expect(vm.dayGroups.flatMap(\.entries).first?.activityText == "Background run")
    }

    // MARK: - Insights: external-stop save while visible

    @Test("external-stop save contributes to visible Insights without a tab switch")
    func insightsExternalStopWhileVisible() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Earlier",
            startedAt: start, endedAt: start.addingTimeInterval(60),
            durationSeconds: 60, categoryIDs: []
        ))
        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 60)

        let runStart = Date(timeIntervalSinceNow: -120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        vm.invalidate()
        await vm.loadIfNeeded()

        #expect(vm.hasCommittedAllTime)
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 180)
    }

    @Test("external-stop save populates empty Insights without a tab switch")
    func insightsEmptyToPopulated() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()
        #expect(!vm.hasCommittedAllTime)
        #expect(vm.breakdown(period: .all, lens: .activity).totalSeconds == 0)

        let runStart = Date(timeIntervalSinceNow: -90)
        try await commitStop(service: service, text: "First run", startedAt: runStart, duration: 90)
        vm.invalidate()
        await vm.loadIfNeeded()

        #expect(vm.hasCommittedAllTime)
        let breakdown = vm.breakdown(period: .all, lens: .activity)
        #expect(breakdown.totalSeconds == 90)
        #expect(breakdown.rows.map(\.name) == ["First run"])
    }

    @Test("repeated refresh events keep Insights totals and breakdown shape")
    func insightsRepeatedEventsKeepTotals() async throws {
        let store = try makeStore()
        let service = TimerService(store: store)
        let start = Date(timeIntervalSinceNow: -3600)
        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Earlier",
            startedAt: start, endedAt: start.addingTimeInterval(60),
            durationSeconds: 60, categoryIDs: []
        ))
        let vm = InsightsViewModel(store: store)
        await vm.loadIfNeeded()

        // Period/lens selection lives in the view; the view-model contract
        // is that repeated invalidate + reload cycles keep every
        // period/lens derivation stable and non-blank.
        for _ in 0..<3 {
            vm.invalidate()
            await vm.loadIfNeeded()
        }
        for period in [InsightsPeriod.today, .week, .all] {
            for lens in [InsightsLens.category, .activity] {
                #expect(vm.breakdown(period: period, lens: lens).totalSeconds == 60)
            }
        }

        let runStart = Date(timeIntervalSinceNow: -30)
        try await commitStop(service: service, text: "Later", startedAt: runStart, duration: 30)
        for _ in 0..<3 {
            vm.invalidate()
            await vm.loadIfNeeded()
        }
        for period in [InsightsPeriod.today, .week, .all] {
            for lens in [InsightsLens.category, .activity] {
                #expect(vm.breakdown(period: period, lens: lens).totalSeconds == 90)
            }
        }
        #expect(vm.breakdown(period: .all, lens: .activity).rows.count == 2)
    }
}
