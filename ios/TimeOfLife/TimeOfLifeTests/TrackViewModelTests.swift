import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("TrackViewModel")
struct TrackViewModelTests {

    // MARK: - State transitions

    @Test("initial state is idle with no draft")
    func initialState() {
        let vm = makeViewModel()
        #expect(vm.state == .idle)
        #expect(vm.state.draft == nil)
        #expect(vm.elapsed == 0)
        #expect(!vm.canStart)
    }

    @Test("empty trimmed text cannot start")
    func emptyTextCannotStart() {
        let vm = makeViewModel()
        vm.nameDraft = "   "
        vm.state = .ready(TrackState.Draft(text: "   "))
        #expect(!vm.canStart)
        vm.start()
        #expect(vm.state == .ready(TrackState.Draft(text: "   ")))
    }

    @Test("start transitions ready to running and persists the draft")
    func startRuns() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createEntry(makeEntry(id: "e1", text: "Coding", categoryIDs: ["c1"]))
        vm.recents = try await storeRecents(store)
        vm.nameDraft = "Coding"
        vm.state = .ready(TrackState.Draft(text: "Coding", categoryIDs: ["c1"]))
        vm.start()

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(draft.text == "Coding")
        // Exact-recent match inherits its full ordered categories.
        #expect(draft.categoryIDs == ["c1"])
        #expect(vm.state.isRunning)

        let state = try await vm.service.runningTimerDraft()
        #expect(state != nil)
        #expect(state?.status == "running")
        #expect(state?.activityText == "Coding")
    }

    @Test("start without an exact recents match starts with empty categories")
    func startInheritsNothingWithoutMatch() async throws {
        let vm = makeViewModel()
        vm.nameDraft = "Novel"
        vm.state = .ready(TrackState.Draft(text: "Novel"))
        vm.start()

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(draft.categoryIDs.isEmpty)
    }

    @Test("stop saves entry with final tags and returns to saved then ready")
    func stopSaves() async {
        let vm = makeViewModel()
        try? await vm.service.store.createCategory(Category(id: "c9", name: "Health", icon: CatalogIcon.briefcase.rawValue))
        vm.nameDraft = "Reading"
        vm.state = .ready(TrackState.Draft(text: "Reading"))
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .running = vm.state else {
            Issue.record("expected running state")
            return
        }
        vm.toggleDraftCategory("c9")

        await vm.stop()

        guard case let .saved(draft, duration) = vm.state else {
            Issue.record("expected saved state")
            return
        }
        #expect(draft.text == "Reading")
        #expect(draft.categoryIDs == ["c9"])
        #expect(duration >= 0)
        #expect(!vm.state.isRunning)

        let entries = try? await vm.service.store.entries()
        #expect(entries?.count == 1)
        #expect(entries?.first?.source == "manual")
        #expect(entries?.first?.activityText == "Reading")
        #expect(entries?.first?.categoryIDs == ["c9"])
        #expect(entries?.first?.notes.isEmpty == true)

        let state = try? await vm.service.runningTimerDraft()
        #expect(state == nil)
    }

    @Test("toggling tags mid-run rewrites only the running draft snapshot")
    func toggleRewritesDraftOnly() async throws {
        let vm = makeViewModel()
        vm.nameDraft = "Work"
        vm.state = .ready(TrackState.Draft(text: "Work", categoryIDs: ["c1"]))
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)

        vm.toggleDraftCategory("c1") // deselect
        vm.toggleDraftCategory("c2") // select

        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        // Order preserved: the surviving selection appends in toggle order.
        #expect(draft.categoryIDs == ["c2"])
        #expect(try await vm.service.store.entries().isEmpty)
        let persisted = try await vm.service.runningTimerDraft()
        #expect(persisted?.categoryIDs == ["c2"])
        // No entry exists mid-run; nothing entered History.
        #expect(try await vm.service.store.outboxRows().allSatisfy { $0.resource != "entry" })
    }

    @Test("elapsed formatting matches TimeFormatter")
    func elapsedFormatting() {
        let vm = makeViewModel()
        vm.nameDraft = "Work"
        vm.state = .ready(TrackState.Draft(text: "Work"))
        vm.start()
        vm.elapsed = 125

        #expect(TimeFormatter.formattedDuration(vm.elapsed) == "02:05")
        #expect(TimeFormatter.formattedDuration(3661) == "1:01:01")
    }

    // MARK: - Recents

    @Test("load populates the recents and the categories map")
    func loadPopulatesRecents() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createEntry(makeEntry(id: "e1", text: "Coding", categoryIDs: ["c1"]))

        await vm.load()

        #expect(vm.recents.map(\.text) == ["Coding"])
        #expect(vm.recents.first?.firstCategoryID == "c1")
        #expect(vm.categories["c1"]?.name == "Work")
    }

    @Test("load seeds the starter categories on a fresh store")
    func loadEmptyRecents() async throws {
        let vm = makeViewModel()

        await vm.load()

        #expect(vm.recents.isEmpty)
        // First load seeds the seven starter categories (no collision on a
        // fresh dataset), so the running tag selector is never empty.
        #expect(vm.categories.count == 7)
        #expect(vm.categories.values.map(\.name).contains("Work"))
    }

    @Test("exact text identity: Gym and GYM are separate recents")
    func exactRecentsIdentity() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", startedAt: Date(timeIntervalSinceNow: -100)))
        try await store.createEntry(makeEntry(id: "e2", text: "GYM"))

        await vm.load()

        #expect(Set(vm.recents.map(\.text)) == ["Gym", "GYM"])
        // Newest first by that text's newest started_at.
        #expect(vm.recents.first?.text == "GYM")
    }

    @Test("selecting a recents chip prepares it without starting")
    func selectChipPrepares() async throws {
        let vm = makeViewModel()
        vm.recents = [TrackViewModel.RecentEntry(text: "Reading", categoryIDs: ["c1"], firstCategoryID: "c1")]

        vm.select(vm.recents[0])

        #expect(vm.state == .ready(TrackState.Draft(text: "Reading", categoryIDs: ["c1"])))
        #expect(vm.elapsed == 0)
        #expect(!vm.state.isRunning)
        #expect(try await vm.service.store.entries().isEmpty)
    }

    @Test("editing after a chip selection re-derives the draft from the field")
    func editAfterChipReselects() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createEntry(makeEntry(id: "e1", text: "Gym", categoryIDs: ["c1"]))
        vm.recents = try await storeRecents(store)
        vm.select(vm.recents[0])
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym", categoryIDs: ["c1"])))

        // Typing a different text must follow the field, not the stale chip.
        vm.nameDraft = "Gym2"
        vm.syncReadyFromDraft()
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym2", categoryIDs: [])))

        // Clearing the field returns to idle.
        vm.nameDraft = "   "
        vm.syncReadyFromDraft()
        #expect(vm.state == .idle)
    }

    @Test("typing a history-tagged name inherits its categories after reload")
    func typingInheritsAfterHistoryEdit() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createCategory(Category(id: "c1", name: "Sport", icon: CatalogIcon.briefcase.rawValue))
        // Entry first saved categoryless (e.g. from the timer), then tagged
        // from the History entry form.
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        var tagged = try #require(try await store.entry(id: "e1"))
        tagged.categoryIDs = ["c1"]
        tagged.updatedAt = Date().addingTimeInterval(10)
        #expect(try await store.updateEntry(tagged))

        // Returning to Track reloads recents + categories (AppShellView).
        await vm.load()
        #expect(vm.recents.first?.categoryIDs == ["c1"])
        #expect(vm.categories["c1"]?.name == "Sport")

        vm.nameDraft = "Gym"
        vm.syncReadyFromDraft()
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym", categoryIDs: ["c1"])))

        vm.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state")
            return
        }
        #expect(draft.categoryIDs == ["c1"])
    }

    @Test("focused start waits out the keyboard slide, keeping tap-time start")
    func focusedStartDefers() async {
        let vm = makeViewModel()
        vm.nameDraft = "Gym"
        vm.state = .ready(TrackState.Draft(text: "Gym"))
        vm.nameFieldFocused = true

        let tapTime = Date()
        vm.start()
        // Still ready immediately — the swap waits for the slide.
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym")))

        // No keyboard dismissal fires in tests, so the bounded fallback
        // (600 ms) triggers the swap.
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard case let .running(draft, startedAt) = vm.state else {
            Issue.record("expected running state after the delay")
            return
        }
        #expect(draft.text == "Gym")
        #expect(startedAt >= tapTime)
        #expect(startedAt.timeIntervalSince(tapTime) < 1)
    }

    @Test("a draft edit cancels a deferred start")
    func draftEditCancelsDeferredStart() async {
        let vm = makeViewModel()
        vm.nameDraft = "Gym"
        vm.state = .ready(TrackState.Draft(text: "Gym"))
        vm.nameFieldFocused = true
        vm.start()

        vm.nameDraft = "Gym2"
        vm.syncReadyFromDraft()

        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(!vm.state.isRunning)
        #expect(vm.state == .ready(TrackState.Draft(text: "Gym2", categoryIDs: [])))
    }

    // MARK: - Recoverable save failure

    @Test("stop retry after a recoverable failure preserves elapsed state")
    func retryStopPreservesState() async {
        let vm = makeViewModel()
        vm.nameDraft = "Reading"
        vm.state = .ready(TrackState.Draft(text: "Reading"))
        vm.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case let .running(draft, startedAt) = vm.state else {
            Issue.record("expected running state")
            return
        }

        // Simulate the recoverable error path.
        vm.state = .error(draft, startedAt: startedAt)
        await vm.retryStop()

        guard case let .saved(saved, _) = vm.state else {
            Issue.record("expected saved state")
            return
        }
        #expect(saved.text == "Reading")
        #expect((try? await vm.service.store.entries().count) == 1)
    }

    // MARK: - Helpers

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
            source: "manual",
            categoryIDs: categoryIDs
        )
    }

    private func storeRecents(_ store: LocalStore) async throws -> [TrackViewModel.RecentEntry] {
        try await store.recents(limit: 6).map { recent in
            TrackViewModel.RecentEntry(
                text: recent.activityText,
                categoryIDs: recent.categoryIDs,
                firstCategoryID: recent.categoryIDs.first
            )
        }
    }

    private func makeViewModel() -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return TrackViewModel(service: service, connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
