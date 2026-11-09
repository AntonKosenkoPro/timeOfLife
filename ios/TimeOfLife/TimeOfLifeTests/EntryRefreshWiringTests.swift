// swiftlint:disable file_length
import Testing
import Foundation
import UIKit
@testable import TimeOfLife

/// Regression coverage for the event-driven refresh contract
/// (remove-compact-timer, group 2).
///
/// History/Insights must surface committed saves through the shared
/// invalidate + guarded-reload helper (`handleExternalReload`) — no tab
/// switch (no onDisappear/onAppear cycle) required — whether the save lands
/// while the tab is visible (existing external-stop path) or while the app
/// is suspended (picked up on foreground return). Covers empty-to-populated
/// and already-populated snapshots; repeated events must not blank content
/// or disturb Insights period/lens derivation.
///
/// Two layers: the contract tests below drive the production helper the
/// views call, and the notification tests at the bottom post REAL
/// notifications to REAL view models — the VMs own the
/// `.timerStoppedExternally` + foreground subscriptions, so deleting a
/// subscription fails those tests.
/// The mid-load tests pin the dropped-reload race the serialized
/// `loadIfNeeded` closes.
@MainActor
@Suite("Entry Refresh Wiring (remove-compact-timer)", .serialized)
struct EntryRefreshWiringTests {

    /// Cross-suite policy isolation: `History`/`Insights` loads fail fast
    /// while the process-global `DatabaseSuspension.shared` reads suspended,
    /// and the suspension suites flip that singleton from parallel
    /// executions. Every test in this suite assumes resumable access, so
    /// each one starts resumed (a fresh suite instance runs before every
    /// test); suspension suites restore the resumed state in their defers,
    /// so this only repairs a policy a neighbor parked mid-flight.
    init() {
        if DatabaseSuspension.shared.isSuspended {
            DatabaseSuspension.shared.noteResumed()
        }
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1")))
    }

    /// Fixed clock so period assertions never depend on wall-clock midnight
    /// or the device firstWeekday (InsightsViewModelTests precedent):
    /// Thursday 2026-09-03 15:00 on a Monday-start Gregorian calendar.
    private func mondayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

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

    /// Seeds the one baseline entry every notification test starts from.
    private func seedEarlier(_ store: LocalStore, now: Date) async throws {
        let start = now.addingTimeInterval(-3600)
        try await store.createEntry(TimeEntry(
            id: "e1", activityText: "Earlier",
            startedAt: start, endedAt: start.addingTimeInterval(60),
            durationSeconds: 60, categoryIDs: []
        ))
    }

    /// History VM modelling a visible tab on an isolated notification
    /// center: the event-driven reload gate requires visibility, and the
    /// private center keeps global posts from parallel suites from
    /// reloading this VM mid-test.
    private func visibleHistoryVM(
        store: LocalStore,
        now: Date,
        center: NotificationCenter
    ) -> HistoryViewModel {
        let vm = HistoryViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            now: { now },
            notifications: center
        )
        vm.setVisible(true)
        return vm
    }

    /// Insights counterpart of `visibleHistoryVM`.
    private func visibleInsightsVM(
        store: LocalStore,
        now: Date,
        center: NotificationCenter
    ) -> InsightsViewModel {
        let vm = InsightsViewModel(store: store, now: { now }, notifications: center)
        vm.setVisible(true)
        return vm
    }

    // MARK: - History: external-stop save while visible

    @Test("external-stop save appears on visible History without a tab switch")
    func historyExternalStopWhileVisible() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)

        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        // External-stop path commits while History stays visible: no
        // onDisappear/onAppear fires, only the event-driven helper the view
        // runs on `.timerStoppedExternally`.
        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        await vm.handleExternalReload()

        let ids = vm.dayGroups.flatMap(\.entries).map(\.id)
        #expect(ids.count == 2)
        #expect(vm.dayGroups.flatMap(\.entries).first?.activityText == "Deep work")
    }

    @Test("external-stop save populates empty History without a tab switch")
    func historyEmptyToPopulated() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.isEmpty)

        let runStart = now.addingTimeInterval(-90)
        try await commitStop(service: service, text: "First run", startedAt: runStart, duration: 90)
        await vm.handleExternalReload()

        #expect(vm.dayGroups.count == 1)
        #expect(vm.dayGroups.first?.entries.first?.activityText == "First run")
    }

    @Test("repeated refresh events never blank populated History")
    func historyRepeatedEventsKeepContent() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()

        // Foreground return, sync exit, and external stop can fire back to
        // back; each is an invalidate + guarded reload with no save between.
        for _ in 0..<3 {
            await vm.handleExternalReload()
        }
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        let runStart = now.addingTimeInterval(-30)
        try await commitStop(service: service, text: "Later", startedAt: runStart, duration: 30)
        for _ in 0..<3 {
            await vm.handleExternalReload()
        }
        #expect(vm.dayGroups.flatMap(\.entries).count == 2)
    }

    @Test("save while suspended appears on History after foreground refresh")
    func historyBackgroundedSaveOnForeground() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.isEmpty)

        // The stop commits while the app is suspended (no observer runs);
        // the foreground return delivers the resume signal on the private
        // center and reloads through the real subscription path (this
        // test's empty-state counterpart to historyPostedForegroundReloads
        // below). Production posts didResume synchronously from the
        // foreground transition, so the VM subscribes to the resume signal
        // only — one trigger per foreground return, not two.
        let runStart = now.addingTimeInterval(-600)
        try await commitStop(service: service, text: "Background run", startedAt: runStart, duration: 600)
        center.post(name: DatabaseSuspension.didResumeNotification, object: nil)

        #expect(await waitForHistoryTexts(vm, ["Background run"]))
    }

#if DEBUG || SCREENSHOT_CAPTURE
    @Test("History invalidate during an in-flight load retries instead of serving stale data")
    func historyInvalidateMidLoadRetries() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])

        // Hold the next load open between its snapshot read and its publish:
        // a commit landing there must still surface. `entered` proves the
        // first load is parked at the gate (past its read) — polling
        // `isLoading` alone cannot: it flips before the read, so the commit
        // could land inside the first load's own fetch and the old
        // `guard needsReload, !isLoading` early-return would still produce
        // the expected result, pinning nothing.
        let gate = LoadGate()
        vm.loadGate = { await gate.wait() }
        vm.invalidate()
        let first = Task { await vm.loadIfNeeded() }
        var parked = false
        for _ in 0..<400 {
            if await gate.entered >= 1 { parked = true; break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard parked else {
            Issue.record("held History load never reached the gate")
            await gate.go()
            await first.value
            vm.loadGate = nil
            return
        }
        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        let second = Task { await vm.handleExternalReload() }
        await gate.go()
        // The retry must actually start: after the first load publishes its
        // stale snapshot, exactly one waiter claims a second load through
        // the gate. A dropped-reload regression leaves `entered` at 1, so
        // the final assertion below would pass without proving anything.
        var retried = false
        for _ in 0..<400 {
            if await gate.entered >= 2 { retried = true; break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard retried else {
            Issue.record("History retry load never started")
            await first.value
            await second.value
            vm.loadGate = nil
            return
        }
        await first.value
        await second.value
        vm.loadGate = nil

        #expect(vm.dayGroups.flatMap(\.entries).map(\.activityText) == ["Deep work", "Earlier"])
    }
#endif

    // MARK: - Insights: external-stop save while visible

    @Test("external-stop save contributes to visible Insights without a tab switch")
    func insightsExternalStopWhileVisible() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 60)

        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        await vm.handleExternalReload()

        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).rows.map(\.name) == ["Deep work", "Earlier"])
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 180)
    }

    @Test("external-stop save populates empty Insights without a tab switch")
    func insightsEmptyToPopulated() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(!vm.hasCommittedAllTime)
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 0)

        let runStart = now.addingTimeInterval(-90)
        try await commitStop(service: service, text: "First run", startedAt: runStart, duration: 90)
        await vm.handleExternalReload()

        #expect(vm.hasCommittedAllTime)
        let breakdown = vm.breakdown(period: .all, lens: .activity, calendar: calendar)
        #expect(breakdown.totalSeconds == 90)
        #expect(breakdown.rows.map(\.name) == ["First run"])
    }

    @Test("repeated refresh events keep Insights totals and breakdown shape")
    func insightsRepeatedEventsKeepTotals() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()

        // Period/lens selection lives in the view; the view-model contract
        // is that repeated invalidate + reload cycles keep every
        // period/lens derivation stable and non-blank. The fixed clock and
        // explicit Monday-start calendar keep `.today`/`.week` exact.
        for _ in 0..<3 {
            await vm.handleExternalReload()
        }
        for period in [InsightsPeriod.today, .week, .all] {
            for lens in [InsightsLens.category, .activity] {
                #expect(vm.breakdown(period: period, lens: lens, calendar: calendar).totalSeconds == 60)
            }
        }

        let runStart = now.addingTimeInterval(-30)
        try await commitStop(service: service, text: "Later", startedAt: runStart, duration: 30)
        for _ in 0..<3 {
            await vm.handleExternalReload()
        }
        for period in [InsightsPeriod.today, .week, .all] {
            for lens in [InsightsLens.category, .activity] {
                #expect(vm.breakdown(period: period, lens: lens, calendar: calendar).totalSeconds == 90)
            }
        }
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).rows.count == 2)
    }

#if DEBUG || SCREENSHOT_CAPTURE
    @Test("Insights invalidate during an in-flight load retries instead of serving stale data")
    func insightsInvalidateMidLoadRetries() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 60)

        // Same dropped-reload race as History: the gate sits between the
        // snapshot read and the publish, so the commit below lands strictly
        // inside the held load. `entered` proves the park point (see the
        // History counterpart) — `isLoading` alone cannot.
        let gate = LoadGate()
        vm.loadGate = { await gate.wait() }
        vm.invalidate()
        let first = Task { await vm.loadIfNeeded() }
        var parked = false
        for _ in 0..<400 {
            if await gate.entered >= 1 { parked = true; break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard parked else {
            Issue.record("held Insights load never reached the gate")
            await gate.go()
            await first.value
            vm.loadGate = nil
            return
        }
        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        let second = Task { await vm.handleExternalReload() }
        await gate.go()
        // The retry must actually start (see the History counterpart): a
        // dropped-reload regression leaves `entered` at 1.
        var retried = false
        for _ in 0..<400 {
            if await gate.entered >= 2 { retried = true; break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard retried else {
            Issue.record("Insights retry load never started")
            await first.value
            await second.value
            vm.loadGate = nil
            return
        }
        await first.value
        await second.value
        vm.loadGate = nil

        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 180)
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).rows.count == 2)
    }
#endif

    // MARK: - Real notification path (VM subscriptions)

    /// The view models own the `.timerStoppedExternally` + foreground
    /// subscriptions, so these tests post REAL notifications to REAL view
    /// models and assert the reload — the ONLY trigger is the post (no
    /// direct invalidate/loadIfNeeded calls). Deleting a subscription fails
    /// here: nothing else reloads the VM. Posts go to each test's private
    /// center (never `.default`), so parallel suites cannot observe or
    /// disturb each other. Bounded polls only, never an
    /// unbounded suspend.

    @Test("History reloads on the posted external-stop notification")
    func historyPostedExternalStopReloads() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.activityText) == ["Earlier"])

        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        center.post(name: .timerStoppedExternally, object: nil)

        #expect(await waitForHistoryTexts(vm, ["Deep work", "Earlier"]))
    }

    @Test("History reloads on foreground return after a backgrounded save")
    func historyPostedForegroundReloads() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleHistoryVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()

        // The stop commits while the app is suspended (no delivery); the
        // foreground return delivers the resume signal and reloads (the VM
        // owns the didResume subscription only — see observeExternalReload).
        let runStart = now.addingTimeInterval(-600)
        try await commitStop(service: service, text: "Background run", startedAt: runStart, duration: 600)
        center.post(name: DatabaseSuspension.didResumeNotification, object: nil)

        #expect(await waitForHistoryTexts(vm, ["Background run", "Earlier"]))
    }

#if DEBUG || SCREENSHOT_CAPTURE
    @Test("foreground posts exactly one resume that reloads once")
    func foregroundRelayDeliversSingleReload() async throws {
        // Production relay lock (fix-database-suspension-kill): the VMs own
        // the `didResume` subscription only, and `DatabaseSuspension`
        // derives that signal from the real `willEnterForeground`
        // notification — so one foreground return must drive exactly one
        // reload. Posts the REAL foreground notification on `.default`
        // after `start()` and counts loads through the override hook: a
        // doubled subscription (foreground + resume) would invalidate twice
        // and load twice.
        DatabaseSuspension.shared.start()
        if DatabaseSuspension.shared.isSuspended {
            DatabaseSuspension.shared.noteResumed()
        }
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let vm = HistoryViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            now: { now },
            notifications: .default
        )
        vm.setVisible(true)
        await vm.loadIfNeeded()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        let runStart = now.addingTimeInterval(-600)
        try await commitStop(service: service, text: "Background run", startedAt: runStart, duration: 600)
        // Lock-guarded counter (`BackgroundAccessWindowTests.DidResumeBox`
        // precedent): the override hook is `@Sendable`, so a plain captured
        // `var` is rejected in Swift 6 language mode.
        final class LoadCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            var value: Int {
                lock.lock(); defer { lock.unlock() }
                return count
            }
            func increment() {
                lock.lock(); count += 1; lock.unlock()
            }
        }
        let counter = LoadCounter()
        vm.loadEntriesOverride = {
            counter.increment()
            return (try await store.entries(), try await store.categories())
        }
        defer { vm.loadEntriesOverride = nil }
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #expect(await waitForHistoryTexts(vm, ["Background run", "Earlier"]))
        #expect(counter.value == 1)
    }
#endif

    @Test("Insights reloads on the posted external-stop notification")
    func insightsPostedExternalStopReloads() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()
        #expect(vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == 60)

        let runStart = now.addingTimeInterval(-120)
        try await commitStop(service: service, text: "Deep work", startedAt: runStart, duration: 120)
        center.post(name: .timerStoppedExternally, object: nil)

        #expect(await waitForInsightsTotal(vm, 180, calendar: calendar))
    }

    @Test("Insights reloads on foreground return after a backgrounded save")
    func insightsPostedForegroundReloads() async throws {
        let calendar = mondayCalendar()
        let now = Self.date("2026-09-03 15:00", calendar: calendar)
        let store = try makeStore()
        let service = TimerService(store: store)
        try await seedEarlier(store, now: now)
        let center = NotificationCenter()
        let vm = visibleInsightsVM(store: store, now: now, center: center)
        await vm.loadIfNeeded()

        let runStart = now.addingTimeInterval(-600)
        try await commitStop(service: service, text: "Background run", startedAt: runStart, duration: 600)
        center.post(name: DatabaseSuspension.didResumeNotification, object: nil)

        #expect(await waitForInsightsTotal(vm, 660, calendar: calendar))
    }

    // MARK: - Helpers

    /// Sticky one-shot gate (TrackSyncReloadTests.Gate precedent): `go()`
    /// before `wait()` still releases, so no scheduling interleave can
    /// strand a waiter — and every wait site here is additionally bounded by
    /// a polling cap, never an unbounded suspend. `entered` counts gate
    /// arrivals so tests can prove a load is parked at the gate (after its
    /// snapshot read) instead of merely observing `isLoading`, which flips
    /// before the read.
    private actor LoadGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        private(set) var entered = 0

        func wait() async {
            entered += 1
            if released { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func go() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Bounded poll for the view model's published entries after a posted
    /// notification (the subscription reloads asynchronously).
    private func waitForHistoryTexts(_ vm: HistoryViewModel, _ texts: [String]) async -> Bool {
        for _ in 0..<100 {
            if vm.dayGroups.flatMap(\.entries).map(\.activityText) == texts { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return vm.dayGroups.flatMap(\.entries).map(\.activityText) == texts
    }

    /// Bounded poll for the view model's derived total after a posted
    /// notification. `.all` is clock-independent by construction.
    private func waitForInsightsTotal(_ vm: InsightsViewModel, _ total: Int, calendar: Calendar) async -> Bool {
        for _ in 0..<100 {
            if vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == total { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return vm.breakdown(period: .all, lens: .activity, calendar: calendar).totalSeconds == total
    }
}
