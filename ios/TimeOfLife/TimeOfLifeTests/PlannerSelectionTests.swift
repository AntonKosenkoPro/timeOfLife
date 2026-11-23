import Testing
import Foundation
@testable import TimeOfLife

/// Text-only planner selection (timer-capture-experience delta): selecting a
/// planner task prepares the exact normalized name with EMPTY categories and
/// notes, dismisses on success (the sheet owns dismissal), and never writes
/// a timer draft, creates an entry, inherits categories, or completes the
/// task. Guards recheck at execution time.
@MainActor
@Suite("PlannerSelection")
struct PlannerSelectionTests {

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "sel-u1"))
    }

    private func makeViewModel(now: Date? = nil) -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL(), userID: "sel-u1")
        let service = TimerService(store: store)
        if let now {
            let fixed = now
            return TrackViewModel(service: service, connectivity: connectivity) { fixed }
        }
        return TrackViewModel(service: service, connectivity: connectivity)
    }

    private func makeEntry(
        id: String,
        text: String,
        categoryIDs: [String] = [],
        startedAt: Date = Date(),
        duration: Int = 60
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(duration)),
            durationSeconds: duration,
            categoryIDs: categoryIDs
        )
    }

    @Test("selection prepares the exact name with empty categories and notes")
    func selectionPreparesTextOnly() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        // An exact historical match WITH categories must not leak them.
        try await store.createCategory(Category(
            id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1"]))
        vm.recents = try await store.recents(limit: TrackViewModel.recentsLimit)
            .map(ExactName.init(storeRecent:))
        #expect(vm.selectPlannerTask("Gym"))
        guard case let .ready(draft) = vm.state else {
            Issue.record("expected ready state")
            return
        }
        #expect(draft.text == "Gym")
        #expect(draft.categoryIDs.isEmpty)
        #expect(draft.notes.isEmpty)
        #expect(vm.nameDraft == "Gym")
    }

    @Test("selection trims and rejects invalid text")
    func selectionValidates() {
        let vm = makeViewModel()
        #expect(vm.selectPlannerTask("  Read  "))
        #expect(vm.state == .ready(TrackState.Draft(text: "Read", categoryIDs: [], notes: "")))
        #expect(!vm.selectPlannerTask("   "))
        #expect(!vm.selectPlannerTask(String(repeating: "x", count: 61)))
        // Failed selections leave the prepared draft alone.
        #expect(vm.state == .ready(TrackState.Draft(text: "Read", categoryIDs: [], notes: "")))
    }

    @Test("selection is blocked while running, errored, or saving")
    func selectionBlockedWhileBusy() {
        let vm = makeViewModel()
        let draft = TrackState.Draft(text: "Gym")
        vm.state = .running(draft, startedAt: Date())
        #expect(!vm.selectPlannerTask("Read"))
        #expect(vm.state.isRunning)
        vm.state = .error(draft, startedAt: Date())
        #expect(!vm.selectPlannerTask("Read"))
        vm.state = .saving(draft, startedAt: Date())
        #expect(!vm.selectPlannerTask("Read"))
        #expect(vm.nameDraft.isEmpty)
    }

    @Test("start after selection runs with empty categories and notes")
    func startPreservesTextOnlyPreparation() async throws {
        let fixed = Date()
        let vm = makeViewModel(now: fixed)
        #expect(vm.selectPlannerTask("Gym"))
        vm.start()
        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(draft.text == "Gym")
        #expect(draft.categoryIDs.isEmpty)
        #expect(draft.notes.isEmpty)
        for _ in 0..<100 {
            if try await vm.service.runningTimerDraft() != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let persisted = try await vm.service.runningTimerDraft()
        #expect(persisted?.categoryIDs.isEmpty == true)
        #expect(persisted?.notes.isEmpty == true)
    }

    @Test("Recents selection still inherits categories")
    func recentsInheritanceUnchanged() {
        let vm = makeViewModel()
        let recent = ExactName(text: "Gym", categoryIDs: ["c1"], firstCategoryID: "c1")
        vm.select(recent)
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym", categoryIDs: ["c1"])))
    }

    @Test("stopping never completes the planner task or links to it")
    func stopLeavesTaskUncompleted() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "sel-u1")
        #expect(vm.selectPlannerTask("Gym"))
        vm.start()
        await vm.stop()
        guard case .saved = vm.state else {
            Issue.record("expected saved state")
            return
        }
        let surviving = try await store.plannerTasks(expectedUserID: "sel-u1")
        #expect(surviving.count == 1)
        #expect(surviving[0].id == task.id)
        #expect(!surviving[0].isCompleted)
    }

    @Test("task removal and cleanup never change the prepared or running name")
    func taskRemovalKeepsPreparedName() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let task = try await store.addPlannerTask(text: "Gym", expectedUserID: "sel-u1")
        #expect(vm.selectPlannerTask("Gym"))
        #expect(try await store.removePlannerTask(id: task.id, expectedUserID: "sel-u1"))
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym", categoryIDs: [], notes: "")))
        #expect(vm.nameDraft == "Gym")
        let cutoff = PlannerDayCutoff.startOfLocalDay(containing: Date(), calendar: .current)
        _ = try await store.reconciledPlannerTasks(pruningBefore: cutoff, expectedUserID: "sel-u1")
        #expect(vm.nameDraft == "Gym")
    }

    @Test("selection coexists with a pending notes review")
    func selectionPreservesPendingReview() {
        let vm = makeViewModel()
        vm.pendingReview = TrackViewModel.PendingNotesReview(
            entryID: "e1",
            entryName: "Gym",
            runStartedAt: Date(),
            endedAt: Date(),
            confirmedNotes: "",
            retainedText: "draft notes",
            accountUserID: "sel-u1",
            phase: .awaitingDecision
        )
        #expect(vm.selectPlannerTask("Read"))
        #expect(vm.pendingReview?.entryID == "e1")
        #expect(vm.pendingReview?.retainedText == "draft notes")
    }
}
