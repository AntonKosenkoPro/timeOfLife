import Testing
import Foundation
@testable import TimeOfLife

/// Capture-clock seam reproductions (screenshot-capture change, tasks 1.3).
///
/// Each test pins app-owned time to a fixed reference (Tue 2026-10-20 09:41
/// local) through the EXISTING injection points and asserts the loaded state
/// agrees with it. On the current tree the view models bypass the injected
/// clock with direct `Date()` reads, so these fail; after the seam fixes they
/// must pass unchanged. They compile against the current tree (no new API).
@MainActor
@Suite("Capture clock seams")
struct CaptureClockSeamTests {

    /// Fixed reference Tuesday (naive components; interpreted in the test
    /// host's current calendar — the assertion compares two loads under the
    /// same defaults, so the host timezone cancels out).
    private static var referenceNow: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 20
        comps.hour = 9
        comps.minute = 41
        comps.calendar = Calendar(identifier: .gregorian)
        return comps.date!
    }

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "capture-seam")))
    }

    private func committedEntry(id: String, start: Date, minutes: Int) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: "Entry \(id)",
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
            durationSeconds: minutes * 60
        )
    }

    private func makeTrackVM(store: LocalStore, now: @escaping () -> Date, calendar: Calendar = .current) -> TrackViewModel {
        let service = TimerService(store: store, liveActivities: NoopLiveActivityController())
        return TrackViewModel(service: service, connectivity: MockConnectivity(connected: true), now: now, calendar: calendar)
    }

    // MARK: - History load()

    @Test("History load groups relative to the injected now, not the wall clock")
    func historyLoadUsesInjectedNow() async throws {
        let now = Self.referenceNow
        let store = try makeStore()
        try await store.createEntry(committedEntry(
            id: "seam-today", start: now.addingTimeInterval(-3600), minutes: 30
        ))
        try await store.createEntry(committedEntry(
            id: "seam-yesterday", start: now.addingTimeInterval(-86400), minutes: 45
        ))

        let fixed = now
        let vm = HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store)) { fixed }
        await vm.load()

        let expected = HistoryViewModel.makeDayGroups(entries: try await store.entries(), now: fixed)
        #expect(vm.dayGroups == expected)
        #expect(vm.dayGroups.count == 2)
        #expect(vm.dayGroups.first?.label == L10n.historyDayToday.text)
    }

    // MARK: - Track start/stop/ticker

    @Test("Track start anchors the run at the injected now")
    func trackStartUsesInjectedNow() {
        let fixed = Self.referenceNow
        // swiftlint:disable:next force_try
        let store = try! makeStore()
        let vm = makeTrackVM(store: store) { fixed }
        vm.nameDraft = "Deep work"
        vm.syncReadyFromDraft()
        vm.start()

        guard case let .running(_, startedAt) = vm.state else {
            Issue.record("expected .running after start, got \(vm.state)")
            return
        }
        #expect(startedAt == fixed)
    }

    @Test("Track stop derives endedAt and duration from the injected now")
    func trackStopUsesInjectedNow() async throws {
        let start = Self.referenceNow
        var current = start
        // swiftlint:disable:next force_try
        let store = try! makeStore()
        let vm = makeTrackVM(store: store) { current }
        vm.nameDraft = "Deep work"
        vm.syncReadyFromDraft()
        vm.start()

        current = start.addingTimeInterval(754)
        await vm.stop()

        guard case let .saved(_, duration) = vm.state else {
            Issue.record("expected .saved after stop, got \(vm.state)")
            return
        }
        #expect(duration == 754)
        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.endedAt == current)
        #expect(entries.first?.durationSeconds == 754)
    }

    /// Start-editor day math must resolve in the view model's calendar, not
    /// the process calendar (review finding 2026-10-30): `updateDraftStartedAt`
    /// calls the resolver without a calendar. The probe sits on the US
    /// fall-back weekend (Nov 1 2026): folding back one Chicago day spans 25
    /// hours while other zones span 24, so the resolved instants differ by
    /// exactly one hour — outside DST the fold preserves the instant in every
    /// zone and the test would be vacuous. Vacuous (early return) only on
    /// hosts whose current zone resolves identically here.
    @Test("Started-at edit resolves in the model calendar")
    func startedAtEditResolvesInModelCalendar() {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        chicago.locale = Locale(identifier: "en_US")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18, minute: 0))!
        let picked = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30))!
        let expectedChicago = RunningStartTimeResolver.resolve(picked: picked, now: now, calendar: chicago)
        let expectedCurrent = RunningStartTimeResolver.resolve(picked: picked, now: now)
        guard expectedChicago != expectedCurrent else {
            // Host zone resolves identically here; nothing to prove.
            return
        }
        // swiftlint:disable:next force_try
        let store = try! makeStore()
        let vm = makeTrackVM(store: store, now: { now }, calendar: chicago)
        vm.nameDraft = "Deep work"
        vm.syncReadyFromDraft()
        vm.start()
        vm.updateDraftStartedAt(picked)
        guard case let .running(_, startedAt) = vm.state else {
            Issue.record("expected .running after start edit, got \(vm.state)")
            return
        }
        #expect(startedAt == expectedChicago)
    }

    @Test("Adopted running draft seeds elapsed from the injected now")
    func adoptedDraftElapsedUsesInjectedNow() {        let fixed = Self.referenceNow
        let startedAt = fixed.addingTimeInterval(-754)
        // swiftlint:disable:next force_try
        let store = try! makeStore()
        let vm = makeTrackVM(store: store) { fixed }
        vm.adopt(TrackSnapshot(
            recents: [],
            allNames: [],
            categories: [:],
            draft: RunningTimerDraft(
                activityText: "Deep work",
                categoryIDs: [],
                notes: "",
                startedAt: startedAt,
                status: "running"
            ),
            restoredName: "Deep work"
        ))
        #expect(vm.elapsed == 754)
    }

    // MARK: - Compact-timer stop path

    @Test("Compact stop saves with the injected now")
    func compactStopUsesInjectedNow() async throws {
        let start = Self.referenceNow
        let end = start.addingTimeInterval(754)
        let store = try makeStore()
        let service = TimerService(store: store, liveActivities: NoopLiveActivityController())
        try await service.startTimerDraft(text: "Deep work", categoryIDs: [], startedAt: start)

        // NOTE: AppShellViewModel grew the `now:` seam for this test; the
        // assertions below are the exact pre-fix failing expectations.
        let shellVM = AppShellViewModel(service: service) { end }
        await shellVM.load()
        await shellVM.stopFromCompact()

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.endedAt == end)
        #expect(entries.first?.durationSeconds == 754)
    }
}
