// swiftlint:disable file_length
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

    /// #242 resolved end-to-end (task 4.1): the editor page is opened with
    /// the confirmed notes, the user types more without tapping save, then
    /// the Island Stop link stops through the in-app path. The completed
    /// entry keeps the confirmed notes with the recorded end time; Review
    /// opens the retained text without writing; confirm saves it to the
    /// exact entry with an ordinary transactional update.
    @Test("review then confirm saves the retained text to the exact entry")
    func reviewThenConfirmSavesRetainedTextToExactEntry() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let endedAt = startedAt.addingTimeInterval(600)
        let vm = makeViewModel(now: endedAt)
        let store = vm.service.store
        try await store.saveTimerDraft(
            activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed"
        )
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        // Simulates the editor page's local copy: opened with the confirmed
        // text, user typed more, never confirmed before Stop.
        let unconfirmedText = "confirmed + uncommitted thought"
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent(unconfirmedText)

        await vm.stop()

        // The entry first completes with the confirmed notes and the
        // recorded end time, independent of the later decision.
        var entries = try await store.entries()
        #expect(entries.count == 1)
        let entryID = try #require(entries.first?.id)
        #expect(entries.first?.notes == "confirmed")
        #expect(entries.first?.endedAt == endedAt)
        #expect(entries.first?.durationSeconds == 600)
        let createsBefore = try await store.outboxRows().filter { $0.op == "create" }
        #expect(createsBefore.count == 1)
        // The unconfirmed text is retained against that exact entry.
        let pending = try #require(vm.pendingReview)
        #expect(pending.entryID == entryID)
        #expect(pending.retainedText == unconfirmedText)

        // Review opens the retained text without validating or writing.
        vm.beginReview()
        #expect(vm.pendingReview?.phase == .reviewing)
        #expect(try await store.entry(id: entryID)?.notes == "confirmed")
        #expect(try await store.outboxRows().count == createsBefore.count)

        // Only the review editor's confirm validates and saves — to that
        // exact entry, with an ordinary transactional sync update.
        let confirmed = await vm.confirmReviewedNotes(unconfirmedText)
        #expect(confirmed)
        entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.notes == unconfirmedText)
        #expect(entries.first?.endedAt == endedAt, "resolution must never move the recorded end time")
        #expect(entries.first?.durationSeconds == 600)
        let updates = try await store.outboxRows().filter { $0.resource == "entry" && $0.op == "update" }
        #expect(updates.count == 1)
        #expect(updates.first?.recordID == entryID)
        #expect(vm.pendingReview == nil)
        #expect(vm.runningNotesEdit == nil)
    }

    @Test("dirty stop retains the unconfirmed text bound to the exact completed entry")
    func dirtyStopRetainsUnconfirmedTextForReview() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let endedAt = startedAt.addingTimeInterval(600)
        let vm = makeViewModel(now: endedAt)
        let store = vm.service.store
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("confirmed + uncommitted thought")

        await vm.stop()

        let entries = try await store.entries()
        #expect(entries.count == 1)
        let review = try #require(vm.pendingReview)
        #expect(review.entryID == entries.first?.id, "review binds the exact completed entry, never the newest row")
        #expect(review.retainedText == "confirmed + uncommitted thought")
        #expect(review.confirmedNotes == "confirmed")
        #expect(review.entryName == "Gym")
        #expect(review.runStartedAt == startedAt)
        #expect(review.endedAt == endedAt)
        #expect(review.phase == .awaitingDecision)
    }

    @Test("discarding keeps the confirmed notes and writes nothing")
    func discardingKeepsConfirmedNotesAndWritesNothing() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("unconfirmed")

        await vm.stop()
        let entryID = try #require(try await store.entries().first?.id)
        let outboxBefore = try await store.outboxRows().count

        vm.discardPendingReview()

        #expect(vm.pendingReview == nil)
        #expect(vm.runningNotesEdit == nil)
        #expect(try await store.entry(id: entryID)?.notes == "confirmed")
        #expect(try await store.outboxRows().count == outboxBefore, "discard writes nothing")
    }

    @Test("clearing confirmed notes is an unconfirmed change; reverting is not")
    func clearingIsDirtyRevertingIsClean() async throws {
        // Clearing non-empty confirmed notes offers the decision, and
        // confirming the empty text clears the completed entry's notes.
        do {
            let vm = makeViewModel()
            let store = vm.service.store
            let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
            try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "keep")
            vm.state = .running(TrackState.Draft(text: "Gym", notes: "keep"), startedAt: startedAt)
            vm.openRunningNotesEditor()
            vm.updateRunningNotesCurrent("")

            await vm.stop()

            let entryID = try #require(try await store.entries().first?.id)
            #expect(vm.pendingReview != nil, "clearing notes is a change")
            vm.beginReview()
            #expect(await vm.confirmReviewedNotes(""))
            #expect(try await store.entry(id: entryID)?.notes.isEmpty == true)
        }
        // Editing then reverting to the confirmed text is clean: no prompt.
        do {
            let vm = makeViewModel()
            let store = vm.service.store
            let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
            try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "keep")
            vm.state = .running(TrackState.Draft(text: "Gym", notes: "keep"), startedAt: startedAt)
            vm.openRunningNotesEditor()
            vm.updateRunningNotesCurrent("keep with more")
            vm.updateRunningNotesCurrent("keep")

            await vm.stop()

            #expect(vm.pendingReview == nil, "reverting to the confirmed text is clean")
            #expect(try await store.entries().first?.notes == "keep")
        }
    }

    @Test("confirmed or untouched notes never prompt")
    func confirmedOrUntouchedNotesNeverPrompt() async throws {
        // Already confirmed via the editor's save: clean.
        do {
            let vm = makeViewModel()
            let store = vm.service.store
            let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
            try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
            vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)
            vm.openRunningNotesEditor()
            await vm.updateDraftNotes("saved mid-run")

            await vm.stop()

            #expect(vm.pendingReview == nil)
            #expect(try await store.entries().first?.notes == "saved mid-run")
        }
        // Editor never opened: no session, no prompt — even with no notes.
        do {
            let vm = makeViewModel()
            let store = vm.service.store
            let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
            try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
            vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)

            await vm.stop()

            #expect(vm.pendingReview == nil)
        }
        // Editor opened but untouched: clean.
        do {
            let vm = makeViewModel()
            let store = vm.service.store
            let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
            try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "steady")
            vm.state = .running(TrackState.Draft(text: "Gym", notes: "steady"), startedAt: startedAt)
            vm.openRunningNotesEditor()

            await vm.stop()

            #expect(vm.pendingReview == nil)
            #expect(try await store.entries().first?.notes == "steady")
        }
    }

    @Test("the exact completed entry is updated when a newer entry exists")
    func reviewConfirmTargetsExactEntryNotNewest() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let vm = makeViewModel(now: startedAt.addingTimeInterval(600))
        let store = vm.service.store
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        let entryID = try #require(try await store.entries().first?.id)

        // A newer entry committed afterwards (another surface, sync, manual):
        // review must still target the exact completed entry.
        let newerAt = startedAt.addingTimeInterval(3_600)
        _ = try await store.createEntry(TimeEntry(
            id: "entry-newer", activityText: "Run",
            startedAt: newerAt, endedAt: newerAt.addingTimeInterval(60), durationSeconds: 60,
            notes: "newer notes"
        ))

        vm.beginReview()
        #expect(await vm.confirmReviewedNotes("reviewed"))

        #expect(try await store.entry(id: entryID)?.notes == "reviewed")
        #expect(try await store.entry(id: entryID)?.endedAt == startedAt.addingTimeInterval(600))
        #expect(try await store.entry(id: "entry-newer")?.notes == "newer notes")
        let updates = try await store.outboxRows().filter { $0.op == "update" }
        #expect(updates.count == 1)
        #expect(updates.first?.recordID == entryID)
    }

    @Test("a second confirm after success resolves nothing and writes nothing")
    func secondConfirmAfterSuccessResolvesNothing() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        vm.beginReview()
        #expect(await vm.confirmReviewedNotes("first"))
        #expect(try await store.outboxRows().filter { $0.op == "update" }.count == 1)

        #expect(!(await vm.confirmReviewedNotes("second")), "no pending review: nothing to resolve")
        let entryID = try #require(try await store.entries().first?.id)
        #expect(try await store.entry(id: entryID)?.notes == "first")
        #expect(try await store.outboxRows().filter { $0.op == "update" }.count == 1)
    }

    @Test("a stale duplicate stop never stops a replacement run")
    func staleDuplicateStopNeverStopsReplacementRun() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt)
        vm.state = .running(TrackState.Draft(text: "Gym"), startedAt: startedAt)

        // A stop request raised before this run started (a link in flight
        // while the replacement run began) must not stop it.
        await vm.stop(onlyIfStartedAtBefore: startedAt.addingTimeInterval(-1))
        guard case .running = vm.state else {
            Issue.record("stale duplicate must not stop the replacement run, got \(vm.state)")
            return
        }
        #expect(try await store.entries().isEmpty)

        // The boundary (request raised as the run started) still stops.
        await vm.stop(onlyIfStartedAtBefore: startedAt)
        guard case .saved = vm.state else {
            Issue.record("expected .saved for the timely stop, got \(vm.state)")
            return
        }
        #expect(try await store.entries().count == 1)
    }

    @Test("saved reset and foreground reload retain the pending decision")
    func savedResetAndForegroundReloadRetainPendingReview() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        #expect(vm.pendingReview != nil)

        // Foreground/tab-return reload (the DatabaseSuspension resume path).
        await vm.load()
        #expect(vm.pendingReview?.retainedText == "dirty")
        #expect(vm.pendingReview?.phase == .awaitingDecision)

        // The 1.6s saved reset returning to ready (simulated synchronously).
        vm.state = .ready(TrackState.Draft(text: "Gym"))
        #expect(vm.pendingReview?.retainedText == "dirty")
    }

    @Test("notes resolution never ends the activity again")
    func notesResolutionNeverEndsActivityAgain() async throws {
        let store = try LocalStore(url: temporaryStoreURL())
        let fake = FakeLiveActivities()
        let vm = TrackViewModel(
            service: TimerService(store: store, liveActivities: fake),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        #expect(fake.ended.count == 1, "the single Saved card fires at stop")

        vm.beginReview()
        #expect(await vm.confirmReviewedNotes("dirty"))
        #expect(fake.ended.count == 1, "review confirm emits no second activity-ending event")
    }

    @Test("a throwing store retains the reviewed text for retry")
    func throwingStoreRetainsReviewedTextForRetry() async {
        // Unbound store: every write throws `notBound` (the same fail-fast
        // shape as a suspension refusal) — the text must be retained for
        // correction/retry, never discarded or falsely confirmed.
        let vm = TrackViewModel(
            service: TimerService(store: LocalStore()),
            connectivity: MockConnectivity(connected: true)
        )
        vm.pendingReview = TrackViewModel.PendingNotesReview(
            entryID: "e1", entryName: "Gym",
            runStartedAt: Date(timeIntervalSince1970: 1_600_000_000),
            endedAt: Date(timeIntervalSince1970: 1_600_000_600),
            confirmedNotes: "confirmed", retainedText: "reviewed",
            accountUserID: nil, phase: .reviewing
        )

        #expect(!(await vm.confirmReviewedNotes("reviewed")))

        #expect(vm.pendingReview?.retainedText == "reviewed")
        #expect(vm.pendingReview?.phase == .reviewing)
        #expect(vm.errorMessage != nil)
    }

    @Test("review confirm posts the entry-change invalidation")
    func reviewConfirmPostsEntryChangeInvalidation() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        vm.beginReview()

        let posted = PostedFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .timerStoppedExternally, object: nil, queue: nil
        ) { _ in posted.mark() }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(await vm.confirmReviewedNotes("dirty"))
        #expect(posted.wasPosted, "History/search/notes surfaces converge through the posted invalidation")
    }

    @Test("review confirm preserves a concurrent unrelated edit")
    func reviewConfirmPreservesConcurrentEdit() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createCategory(Category(id: "c2", name: "Health", icon: CatalogIcon.heart.rawValue))
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: ["c1"], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", categoryIDs: ["c1"], notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        let entryID = try #require(try await store.entries().first?.id)

        // A concurrent merge (sync pull) retags the entry before the review
        // resolves: the notes write must preserve the latest other fields.
        var merged = try #require(try await store.entry(id: entryID))
        merged.categoryIDs = ["c1", "c2"]
        try await store.mergeEntry(merged)

        vm.beginReview()
        #expect(await vm.confirmReviewedNotes("reviewed"))

        let resolved = try #require(try await store.entry(id: entryID))
        #expect(resolved.notes == "reviewed")
        #expect(resolved.categoryIDs == ["c1", "c2"])
        #expect(resolved.activityText == "Gym")
        #expect(resolved.startedAt == startedAt)
    }

    @Test("review confirm against a deleted target retains the text and never recreates")
    func reviewConfirmMissingTargetRetainsWithoutRecreating() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        vm.pendingReview = TrackViewModel.PendingNotesReview(
            entryID: "gone", entryName: "Gym",
            runStartedAt: Date(timeIntervalSince1970: 1_600_000_000),
            endedAt: Date(timeIntervalSince1970: 1_600_000_600),
            confirmedNotes: "confirmed", retainedText: "reviewed",
            accountUserID: nil, phase: .awaitingDecision
        )

        let ok = await vm.confirmReviewedNotes("reviewed")

        #expect(!ok)
        #expect(try await store.entry(id: "gone") == nil, "a missing target is never recreated")
        #expect(vm.pendingReview?.retainedText == "reviewed", "the text is retained for correction/retry")
        #expect(vm.pendingReview?.phase == .reviewing)
        #expect(vm.errorMessage != nil)
    }

    @Test("account teardown invalidates the pending review without writing")
    func accountTeardownInvalidatesPendingReview() async throws {
        let url = temporaryStoreURL()
        let store = try LocalStore(url: url, userID: "u1")
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        vm.updateRunningNotesCurrent("dirty")

        await vm.stop()
        let accounted = try #require(vm.pendingReview?.accountUserID)
        #expect(accounted == "u1")

        await store.closeAccount()

        let ok = await vm.confirmReviewedNotes("reviewed")
        #expect(!ok, "a stale callback must not write to another account/store")
        #expect(vm.pendingReview == nil)
    }

    @Test("same-tick review confirm bumps strictly newer and succeeds")
    func sameTickReviewConfirmBumpsStrictlyNewer() async throws {
        let tick = Date(timeIntervalSince1970: 1_600_000_000)
        let vm = makeViewModel(now: tick)
        let store = vm.service.store
        _ = try await store.createEntry(TimeEntry(
            id: "e-tick", activityText: "Gym",
            startedAt: tick.addingTimeInterval(-600), endedAt: tick, durationSeconds: 600,
            notes: "confirmed", createdAt: tick, updatedAt: tick
        ))
        vm.pendingReview = TrackViewModel.PendingNotesReview(
            entryID: "e-tick", entryName: "Gym",
            runStartedAt: tick.addingTimeInterval(-600), endedAt: tick,
            confirmedNotes: "confirmed", retainedText: "reviewed",
            accountUserID: nil, phase: .reviewing
        )

        #expect(await vm.confirmReviewedNotes("reviewed"))

        let resolved = try #require(try await store.entry(id: "e-tick"))
        #expect(resolved.notes == "reviewed")
        #expect(resolved.updatedAt > tick, "the notes update needs an updatedAt strictly later at wire precision")
    }

    @Test("a mid-run backdate keeps dirty tracking on the moved run")
    func backdateKeepsDirtyTrackingOnMovedRun() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let startedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try await store.saveTimerDraft(activityText: "Gym", categoryIDs: [], startedAt: startedAt, notes: "confirmed")
        vm.state = .running(TrackState.Draft(text: "Gym", notes: "confirmed"), startedAt: startedAt)
        vm.openRunningNotesEditor()
        // Backdate the run, then type: the session identity must follow the
        // moved anchor or the later receipt check would drop the decision.
        vm.updateDraftStartedAt(startedAt.addingTimeInterval(-600))
        vm.updateRunningNotesCurrent("dirty after backdate")

        await vm.stop()

        let review = try #require(vm.pendingReview)
        #expect(review.retainedText == "dirty after backdate")
        #expect(review.runStartedAt <= startedAt)
    }

    /// Sendable posted-flag for the default-center invalidation test (the
    /// observer closure cannot actor-hop). Lock-guarded after the
    /// `AppContainer+UITesting` `NSLock` precedent.
    final class PostedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flagged = false
        var wasPosted: Bool { lock.withLock { flagged } }
        func mark() { lock.withLock { flagged = true } }
    }

    /// Stop-retry identity (design §21): the atomic transition commits
    /// nothing on failure, the failed stop stays retryable, and the retry
    /// reuses the one logical completion identity instead of minting a fresh
    /// id. First the entry INSERT fails (trigger); then the trigger is
    /// lifted and the retry must converge on the held identity with a single
    /// entry and a single create outbox row.
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
        try failEntryInserts(at: url)

        await vm.stop()

        // The atomic transition commits nothing on failure (no partial
        // entry, no outbox row, no Saved card) and stays retryable.
        #expect(try await store.entries().isEmpty)
        #expect(try await store.outboxRows().isEmpty)
        let identity = try #require(vm.pendingStopEntryID)
        guard case .error = vm.state else {
            Issue.record("expected recoverable .error after the failed stop, got \(vm.state)")
            return
        }

        try dropStopReproTrigger(at: url)
        await vm.retryStop()

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.id == identity, "retry must reuse the one completion identity")
        let creates = try await store.outboxRows().filter { $0.resource == "entry" && $0.op == "create" }
        #expect(creates.count == 1, "one logical completion enqueues one create")
        guard case .saved = vm.state else {
            Issue.record("expected .saved after the retried stop, got \(vm.state)")
            return
        }
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

    private func dropStopReproTrigger(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "DROP TRIGGER stop_repro_fail")
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
