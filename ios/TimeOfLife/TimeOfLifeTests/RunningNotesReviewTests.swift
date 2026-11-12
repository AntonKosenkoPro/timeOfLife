import Testing
import Foundation
import GRDB
@testable import TimeOfLife

/// Issue #242 repro + stop-receipt regressions
/// (preserve-running-notes-on-live-stop 1.1/1.3).
///
/// The running-notes editor holds its text in a local copy until ✓
/// (NotesEditorPage copy-on-open). Live Activity Stop completes with the
/// confirmed notes and — on the current tree — no surface retains the
/// unconfirmed edit.
@MainActor
@Suite("RunningNotesReview")
struct RunningNotesReviewTests {

    /// The nonthrowing mutation gap (design §21): `createEntry` reports a
    /// failed INSERT as `.failure` instead of throwing, and the current
    /// `stopTimerDraft` discards that outcome. The stop must surface a
    /// recoverable error so the run stays retryable.
    @Test("stop surfaces a recoverable error when the entry write fails nonthrowing")
    func stopNonthrowingFailureSurfacesRecoverableError() async throws {
        let url = temporaryStoreURL()
        let store = try LocalStore(url: url)
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)
        try failEntryInserts(at: url)

        await vm.stop()

        guard case .error = vm.state else {
            Issue.record("expected recoverable .error after a nonthrowing entry-write failure, got \(vm.state)")
            return
        }
        #expect(vm.errorMessage != nil)
    }

    /// A stop that cannot save must retain the running draft for retry and
    /// must not end the activity with a Saved card (no false success).
    @Test("a nonthrowing entry-write failure retains the draft and skips the Saved card")
    func stopNonthrowingFailureRetainsDraftAndSkipsSavedCard() async throws {
        let url = temporaryStoreURL()
        let store = try LocalStore(url: url)
        let fake = FakeLiveActivities()
        let vm = TrackViewModel(
            service: TimerService(store: store, liveActivities: fake),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)
        try failEntryInserts(at: url)

        await vm.stop()

        #expect(try await store.timerDraft() != nil, "failed stop must retain the running draft for retry")
        #expect(fake.ended.isEmpty, "failed stop must not end the activity with a Saved card")
        #expect(try await store.entries().isEmpty)
    }

    /// Existing Stop timing preservation baseline (design §17): Stop
    /// completes immediately with the end time recorded at stop, independent
    /// of any later notes review or decision delay. Locked green before the
    /// fix so the change cannot move the recorded end time.
    @Test("stop records the entry end time at stop, independent of any later notes decision")
    func stopTimingBaselineCompletesImmediatelyWithFixedEndTime() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let endedAt = startedAt.addingTimeInterval(600)
        let vm = makeViewModel(now: endedAt)
        let store = vm.service.store
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)

        await vm.stop()

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.endedAt == endedAt)
        #expect(entries.first?.durationSeconds == 600)
        #expect(entries.first?.notes == "confirmed")
    }

    /// Repro of #242 on the current tree (task 1.1): the editor page is
    /// opened with the confirmed notes, the user types more without tapping
    /// ✓, then `lifio://track?stop=1` stops through the in-app path
    /// (`DeepLink.stopTimer` → reload → `stop()`). The completed entry keeps
    /// the confirmed notes and the unconfirmed text survives on no app
    /// surface: the saved-state draft keeps the confirmed notes and
    /// post-stop editor input is stranded (ignored outside running states).
    /// Converted into the retention regression by the fix (task 4.1).
    @Test("repro #242: unconfirmed editor text is lost when Stop completes")
    func reproUnconfirmedEditorTextLostOnStop() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(
            activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed"
        )
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        // Simulates the editor page's local copy: opened with the confirmed
        // text, user typed more, never tapped ✓ — the keystrokes live only
        // in the page.
        let unconfirmedText = "confirmed + uncommitted thought"

        await vm.stop()

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.notes == "confirmed", "stop saves confirmed notes only")
        guard case let .saved(savedDraft, _) = vm.state else {
            Issue.record("expected .saved after stop, got \(vm.state)")
            return
        }
        #expect(savedDraft.notes == "confirmed")
        #expect(unconfirmedText != entries.first?.notes, "repro #242: the unconfirmed text is lost")
        // The stranded page writes through `updateDraftNotes`, which
        // ignores non-running states — the edit can never attach.
        await vm.updateDraftNotes(unconfirmedText)
        guard case let .saved(afterDraft, _) = vm.state else {
            Issue.record("expected .saved to survive stranded input, got \(vm.state)")
            return
        }
        #expect(afterDraft.notes == "confirmed", "post-stop editor input is stranded")
    }

    /// Stop-retry identity (design §21): a stop whose entry committed but whose
    /// draft-clear failed stays retryable, and the retry must reuse the one
    /// logical completion identity instead of saving a second entry.
    /// Dropping `timer_state` breaks only the draft clear: the entry create
    /// still commits, so the retry replays against the existing record.
    @Test("stop retry reuses one completion identity across retries")
    func stopRetryReusesSingleCompletionIdentity() async throws {
        let url = temporaryStoreURL()
        let store = try LocalStore(url: url)
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)
        try dropTimerStateTable(at: url)

        await vm.stop()
        #expect(try await store.entries().count == 1, "first stop commits the entry before the draft-clear fails")

        await vm.retryStop()

        #expect(
            try await store.entries().count == 1,
            "retry must reuse the one completion identity, never save a second entry"
        )
    }

    /// Duplicate Stop deliveries during one stop/resolution operation join
    /// or no-op: a second `stop()` landing mid-save must not create a
    /// second entry. Green lock on the current tree (state-guard
    /// serialization), must stay green through the change.
    @Test("a duplicate stop landing mid-save creates no second entry")
    func duplicateStopMidSaveCreatesNoSecondEntry() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)
        let gate = StopGate()
        vm.stopGate = { await gate.wait() }
        let first = Task { await vm.stop() }
        guard await waitUntilSaving(vm) else {
            Issue.record("stop() never entered .saving")
            await gate.go()
            await first.value
            return
        }

        await vm.stop()

        await gate.go()
        await first.value
        #expect(try await store.entries().count == 1)
    }

    // MARK: - Helpers

    /// Drops the draft table to force persistence failures. Fixture-only:
    /// app mutation paths stay behind LocalStore.
    private func dropTimerStateTable(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "DROP TABLE timer_state")
        }
    }

    /// Polls for the transient `.saving` state (the save is gate-held, so
    /// this always resolves; the cap only bounds a broken-seam hang).
    private func waitUntilSaving(_ vm: TrackViewModel) async -> Bool {
        for _ in 0..<400 {
            if vm.state.isSaving { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    /// Holds a `stop()` inside its save window; the test resumes it with
    /// `go()` after interleaving the duplicate call. Sticky release (the
    /// TrackSyncReloadTests `Gate` precedent): a `go()` landing before
    /// `wait()` still releases the waiter.
    actor StopGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            if released { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func go() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }


    /// Makes entry INSERTs fail while entry SELECTs keep working, so
    /// `createEntry` returns its nonthrowing `.failure` (the gap in
    /// design §21) instead of throwing. Fixture-only: app mutation paths
    /// stay behind LocalStore.
    private func failEntryInserts(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER stop_repro_fail BEFORE INSERT ON entries
                BEGIN SELECT RAISE(ABORT, 'stop-repro'); END
                """)
        }
    }

    private func makeViewModel(now: Date? = nil) -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        if let now {
            let fixed = now
            return TrackViewModel(service: service, connectivity: connectivity) { fixed }
        }
        return TrackViewModel(service: service, connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }
}
