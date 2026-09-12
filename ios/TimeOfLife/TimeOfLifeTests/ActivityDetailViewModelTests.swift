import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ActivityDetailViewModel")
struct ActivityDetailViewModelTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }

    private func makeActivity(id: String = "a1", name: String = "Running") -> Activity {
        Activity(id: id, name: name)
    }

    private func makeEntry(
        startedAt: Date,
        endedAt: Date?,
        id: String = "e1",
        activityID: String = "a1",
        durationSeconds: Int? = nil,
        source: String = "manual"
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityID: activityID,
            activityName: "Running",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            source: source
        )
    }

    @Test("same-day entry shows bare times")
    func sameDayBareTimes() async throws {
        let store = try makeStore()
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        let start = Calendar.current.date(bySettingHour: 14, minute: 34, second: 0, of: Date())!
        let entry = makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_706),
            durationSeconds: 3_706
        )
        let range = vm.timeRangeText(for: entry)
        #expect(range.contains("–"))
        #expect(!range.contains(","))
        #expect(vm.durationText(for: entry) == "1h 1m 46s")
        #expect(vm.provenanceName(for: entry).isEmpty)
    }

    @Test("cross-midnight entry prefixes both endpoints with day labels")
    func crossMidnightDayPrefixes() async throws {
        let store = try makeStore()
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let entry = makeEntry(
            startedAt: startOfToday.addingTimeInterval(-1_800),
            endedAt: startOfToday.addingTimeInterval(1_800),
            durationSeconds: 3_600
        )
        let range = vm.timeRangeText(for: entry)
        #expect(range == "Yesterday, \(HistoryViewModel.timeText(for: entry.startedAt)) – Today, \(HistoryViewModel.timeText(for: entry.endedAt!))")
    }

    @Test("provenance name is bare source name, empty for manual")
    func provenanceName() async throws {
        let store = try makeStore()
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        let start = Date()
        let garmin = makeEntry(startedAt: start, endedAt: start, source: "garmin")
        #expect(vm.provenanceName(for: garmin) == L10n.provenanceNameGarmin.text)
        let manual = makeEntry(startedAt: start, endedAt: start, source: "manual")
        #expect(vm.provenanceName(for: manual).isEmpty)
    }

    @Test("load resolves categories, total, and groups")
    func loadResolves() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_700),
            durationSeconds: 3_700
        ))
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        await vm.load()
        #expect(vm.activity?.name == "Running")
        #expect(vm.totalText == "1h 1m 40s")
        #expect(vm.dayGroups.count == 1)
        #expect(vm.activityIsGone == false)
    }

    @Test("missing activity marks the sheet gone")
    func missingActivityGone() async throws {
        let store = try makeStore()
        let vm = ActivityDetailViewModel(store: store, activityID: "nope")
        await vm.load()
        #expect(vm.activityIsGone == true)
        #expect(vm.activity == nil)
    }

    @Test("performUndo restores a buffered entry deletion and reloads the list")
    func undoRestoresBufferedEntryDeletion() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_700),
            durationSeconds: 3_700
        ))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let vm = ActivityDetailViewModel(
            store: store,
            activityID: "a1",
            undoBuffer: UndoBufferStore(store: store)
        )
        await vm.load()
        #expect(vm.dayGroups.isEmpty)

        await vm.performUndo()

        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        #expect(vm.totalText == "1h 1m 40s")
        #expect(try await store.outboxRows().allSatisfy { $0.op != "delete" })
    }

    @Test("performUndo restores an old buffered entry deletion (no window)")
    func undoOldBufferedDeletionRestores() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_700),
            durationSeconds: 3_700
        ))
        _ = try await store.deleteEntryUndoable(
            id: "e1",
            deletedAt: Date().addingTimeInterval(-3_600)
        )
        let vm = ActivityDetailViewModel(
            store: store,
            activityID: "a1",
            undoBuffer: UndoBufferStore(store: store)
        )

        await vm.performUndo()

        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        #expect(try await store.outboxRows().allSatisfy { $0.op != "delete" })
    }

    @Test("performUndo leaves buffer rows owned by other surfaces alone")
    func undoIgnoresNonEntryBufferRows() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "c1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        let vm = ActivityDetailViewModel(
            store: store,
            activityID: "a1",
            undoBuffer: UndoBufferStore(store: store)
        )

        await vm.performUndo()

        // The category deletion is untouched — its owner restores it.
        #expect(try await store.category(id: "c1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.outboxRows().allSatisfy { $0.op != "delete" })
    }

    @Test("reassigned entry leaves the old activity's list with a recomputed total")
    func reassignedEntryLeavesOldList() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createActivity(makeActivity(id: "a2", name: "Writing"))
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_700),
            durationSeconds: 3_700
        ))
        var moved = try #require(try await store.entry(id: "e1"))
        moved.activityID = "a2"
        moved.updatedAt = Date()
        #expect(try await store.updateEntry(moved))

        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        await vm.load()

        #expect(vm.dayGroups.isEmpty)
        #expect(vm.totalText == "0s")
        #expect(vm.activityIsGone == false)
    }

    @Test("performUndo restores only the newest of two buffered deletions per call")
    func undoRestoresNewestFirstOneAtATime() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(startedAt: start, endedAt: start.addingTimeInterval(3_700), id: "e1", durationSeconds: 3_700))
        try await store.createEntry(makeEntry(startedAt: start, endedAt: start.addingTimeInterval(60), id: "e2", durationSeconds: 60))
        let now = Date()
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: now.addingTimeInterval(-10))
        _ = try await store.deleteEntryUndoable(id: "e2", deletedAt: now)
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        await vm.load()
        #expect(vm.dayGroups.isEmpty)
        await vm.performUndo()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2"])
        await vm.performUndo()
        #expect(Set(vm.dayGroups.flatMap(\.entries).map(\.id)) == ["e1", "e2"])
    }
    @Test("registerSystemUndo offers one undo when an entry deletion is restorable")
    func registerOffersUndoWhenRestorable() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(startedAt: start, endedAt: start.addingTimeInterval(3_700), durationSeconds: 3_700))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(undoManager.canUndo)
        #expect(!undoManager.undoActionName.isEmpty)
    }
    @Test("registerSystemUndo offers nothing when the buffer is empty")
    func registerOffersNothingWhenEmpty() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(!undoManager.canUndo)
    }
    @Test("registerSystemUndo offers nothing for non-entry buffer rows")
    func registerIgnoresNonEntryBufferRows() async throws {
        let store = try makeStore()
        try await store.createCategory(TimeOfLife.Category(id: "c1", name: "Work", icon: "briefcase"))
        _ = try await store.deleteCategoryUndoable(id: "c1", deletedAt: Date())
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(!undoManager.canUndo)
    }
    @Test("registerSystemUndo offers an old buffered entry deletion (no window)")
    func registerOffersOldBufferedDeletion() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(startedAt: start, endedAt: start.addingTimeInterval(3_700), durationSeconds: 3_700))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date().addingTimeInterval(-3_600))
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(undoManager.canUndo)
    }
    @Test("registration after a restore offers nothing (single-shot)")
    func registerClearedAfterRestore() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(startedAt: start, endedAt: start.addingTimeInterval(3_700), durationSeconds: 3_700))
        _ = try await store.deleteEntryUndoable(id: "e1", deletedAt: Date())
        let vm = ActivityDetailViewModel(store: store, activityID: "a1", undoBuffer: UndoBufferStore(store: store))
        let undoManager = UndoManager()
        await vm.registerSystemUndo(with: undoManager)
        #expect(undoManager.canUndo)
        await vm.performUndo()
        await vm.registerSystemUndo(with: undoManager)
        #expect(!undoManager.canUndo)
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
    }

    @Test("performUndo with an empty buffer is a no-op")
    func undoEmptyBufferIsNoOp() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let vm = ActivityDetailViewModel(
            store: store,
            activityID: "a1",
            undoBuffer: UndoBufferStore(store: store)
        )
        await vm.load()

        await vm.performUndo()

        #expect(vm.activity?.name == "Running")
        #expect(vm.dayGroups.isEmpty)
    }

    @Test("load excludes in-progress entries from groups and total")
    func loadExcludesInProgress() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        let start = Date().addingTimeInterval(-3_700)
        try await store.createEntry(makeEntry(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_700),
            durationSeconds: 3_700
        ))
        // In-progress entry (no end time): committed via createEntry with a
        // nil end, like a synced uncommitted session.
        try await store.createEntry(makeEntry(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: nil,
            id: "e-running",
            durationSeconds: nil
        ))
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        await vm.load()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        #expect(vm.totalText == "1h 1m 40s")
    }

    @Test("only in-progress entries leave the sheet empty but present")
    func onlyInProgressLeavesEmptyGroups() async throws {
        let store = try makeStore()
        try await store.createActivity(makeActivity())
        try await store.createEntry(makeEntry(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: nil,
            durationSeconds: nil
        ))
        let vm = ActivityDetailViewModel(store: store, activityID: "a1")
        await vm.load()
        #expect(vm.dayGroups.isEmpty)
        #expect(vm.totalText == "0s")
        #expect(vm.activityIsGone == false)
    }
}
