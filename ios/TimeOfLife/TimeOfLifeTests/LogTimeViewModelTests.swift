import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("LogTimeViewModel")
struct LogTimeViewModelTests {

    // MARK: - Defaults

    @Test("sheet opens with Start floored to 5 minutes and End one hour later")
    func defaultTimes() {
        // 2:37:20 PM -> Start 2:35 PM, End 3:35 PM.
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 9
        components.hour = 14
        components.minute = 37
        components.second = 20
        let now = Calendar.current.date(from: components)!
        let vm = makeViewModel(now: now)

        let calendar = Calendar.current
        #expect(calendar.component(.minute, from: vm.startsAt) == 35)
        #expect(calendar.component(.second, from: vm.startsAt) == 0)
        #expect(vm.endsAt.timeIntervalSince(vm.startsAt) == 3_600)
    }

    @Test("Add is disabled with no activity chosen")
    func gateRequiresActivity() {
        let vm = makeViewModel()

        #expect(!vm.isAddEnabled)
    }

    // MARK: - Validity gate

    @Test("Add enables when an activity is chosen and End is after Start")
    func gateValidForm() {
        let vm = makeViewModel()
        vm.select(Activity(id: "a1", name: "Reading"))

        #expect(vm.isAddEnabled)
    }

    @Test("Add disables when End moves to Start")
    func gateEndEqualStart() {
        let vm = makeViewModel()
        vm.select(Activity(id: "a1", name: "Reading"))

        vm.setEndsAt(vm.startsAt)

        #expect(!vm.isAddEnabled)
    }

    @Test("Add disables when End moves before Start")
    func gateEndBeforeStart() {
        let vm = makeViewModel()
        vm.select(Activity(id: "a1", name: "Reading"))

        vm.setEndsAt(vm.startsAt.addingTimeInterval(-60))

        #expect(!vm.isAddEnabled)
    }

    // MARK: - Duration preservation

    @Test("moving Start past End auto-pushes End preserving duration")
    func startPastEndPushesEnd() {
        let vm = makeViewModel()
        let originalEnd = vm.endsAt

        vm.setStartsAt(originalEnd.addingTimeInterval(25 * 60))

        #expect(vm.endsAt == originalEnd.addingTimeInterval(25 * 60).addingTimeInterval(3_600))
    }

    @Test("moving Start earlier keeps End in place")
    func startEarlierKeepsEnd() {
        let vm = makeViewModel()
        let originalEnd = vm.endsAt

        vm.setStartsAt(vm.startsAt.addingTimeInterval(-95 * 60))

        #expect(vm.endsAt == originalEnd)
    }

    @Test("a shortened custom duration is the one preserved on push")
    func customDurationPreserved() {
        let vm = makeViewModel()
        vm.setEndsAt(vm.startsAt.addingTimeInterval(30 * 60))

        vm.setStartsAt(vm.startsAt.addingTimeInterval(2 * 3_600))

        #expect(vm.endsAt.timeIntervalSince(vm.startsAt) == 30 * 60)
    }

    @Test("moving End never moves Start")
    func endNeverMovesStart() {
        let vm = makeViewModel()
        let originalStart = vm.startsAt

        vm.setEndsAt(originalStart.addingTimeInterval(-10))

        #expect(vm.startsAt == originalStart)
    }

    // MARK: - Save

    @Test("save persists a manual entry with derived duration")
    func savePersistsManualEntry() async throws {
        let vm = makeViewModel()
        let activity = Activity(id: "a1", name: "Reading")
        try await vm.service.store.createActivity(activity)
        vm.select(activity)

        let saved = await vm.save()

        #expect(saved)
        let entries = try await vm.service.store.entries()
        #expect(entries.count == 1)
        #expect(entries[0].activityID == "a1")
        #expect(entries[0].activityName == "Reading")
        #expect(entries[0].startedAt == vm.startsAt)
        #expect(entries[0].endedAt == vm.endsAt)
        #expect(entries[0].durationSeconds == 3_600)
        #expect(entries[0].source == "manual")
        #expect(entries[0].sourceRef == nil)
    }

    @Test("save fails gracefully when the activity no longer exists")
    func saveMissingActivity() async {
        let vm = makeViewModel()
        vm.select(Activity(id: "gone", name: "Gone"))

        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.errorMessage == L10n.logTimeActivityMissing.text)
    }

    @Test("save on an invalid form returns false without an error")
    func saveInvalidForm() async {
        let vm = makeViewModel()

        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Modes

    @Test("mode routing: none is create, manual is edit, imported is locked")
    func modeRouting() {
        #expect(LogTimeViewModel.mode(for: nil) == .create)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "manual")) == .edit)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "garmin")) == .locked)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "healthkit")) == .locked)
    }

    @Test("EDIT prefills activity and interval from the entry")
    func editPrefillsFromEntry() async throws {
        let entry = storedEntry()
        let vm = makeViewModel(editing: entry)

        #expect(vm.mode == .edit)
        #expect(!vm.isLocked)
        #expect(vm.selectedActivity?.id == "a1")
        #expect(vm.selectedActivity?.name == "Reading")
        #expect(vm.startsAt == entry.startedAt)
        #expect(vm.endsAt == entry.endedAt)
        #expect(vm.isAddEnabled)
    }

    @Test("LOCKED exposes values read-only with no confirm path")
    func lockedHasNoConfirmPath() async throws {
        let entry = storedEntry(source: "garmin")
        let vm = makeViewModel(editing: entry)

        #expect(vm.mode == .locked)
        #expect(vm.isLocked)
        #expect(vm.selectedActivity?.id == "a1")
        #expect(vm.startsAt == entry.startedAt)

        #expect(await vm.save() == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - EDIT gate and duration

    @Test("Save disables in EDIT when End moves to Start")
    func editGateEndEqualStart() async throws {
        let vm = makeViewModel(editing: storedEntry())
        vm.setEndsAt(vm.startsAt)

        #expect(!vm.isAddEnabled)
        #expect(await vm.save() == false)
    }

    @Test("EDIT preserves duration when Start is pushed past End")
    func editStartPushPreservesDuration() async throws {
        let vm = makeViewModel(editing: storedEntry())
        let originalDuration = vm.endsAt.timeIntervalSince(vm.startsAt)

        vm.setStartsAt(vm.endsAt.addingTimeInterval(600))

        #expect(vm.endsAt.timeIntervalSince(vm.startsAt) == originalDuration)
    }

    // MARK: - EDIT save

    @Test("EDIT save persists the new interval through updateEntry")
    func editSavePersistsUpdate() async throws {
        let store = try await makeEditStore()
        let entry = storedEntry()
        try await store.createEntry(entry)
        let vm = makeViewModel(store: store, editing: entry)

        vm.setEndsAt(vm.endsAt.addingTimeInterval(1_800))
        let saved = await vm.save()

        #expect(saved)
        let stored = try #require(try await store.entry(id: "e1"))
        #expect(stored.endedAt == vm.endsAt)
        #expect(stored.durationSeconds == 5_400)
        #expect(stored.updatedAt >= entry.updatedAt)
        let updates = try await store.outboxRows().filter { $0.op == "update" && $0.recordID == "e1" }
        #expect(updates.count == 1)
    }

    @Test("EDIT save fails with the draft intact on a stale write")
    func editSaveStaleKeepsDraft() async throws {
        let store = try await makeEditStore()
        let entry = storedEntry()
        try await store.createEntry(entry)
        let vm = makeViewModel(store: store, editing: entry)

        // A newer version lands underneath (e.g. a sync pull).
        var newer = entry
        newer.endedAt = entry.endedAt?.addingTimeInterval(60)
        newer.durationSeconds = 3_660
        newer.updatedAt = Date().addingTimeInterval(60)
        try await store.mergeEntry(newer)

        vm.setEndsAt(vm.endsAt.addingTimeInterval(1_800))
        let keptEnd = vm.endsAt
        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.errorMessage == L10n.entryStaleError.text)
        #expect(vm.endsAt == keptEnd)
    }

    @Test("EDIT save reassigns the entry to another activity")
    func editSaveReassignsActivity() async throws {
        let store = try await makeEditStore()
        try await store.createActivity(Activity(id: "a2", name: "Writing"))
        let entry = storedEntry()
        try await store.createEntry(entry)
        let vm = makeViewModel(store: store, editing: entry)
        vm.select(Activity(id: "a2", name: "Writing"))

        #expect(await vm.save())
        #expect(try await store.entry(id: "e1")?.activityID == "a2")
    }

    @Test("EDIT save fails gracefully when the activity no longer exists")
    func editSaveMissingActivity() async throws {
        let store = try await makeEditStore()
        let entry = storedEntry()
        try await store.createEntry(entry)
        let vm = makeViewModel(store: store, editing: entry)
        vm.select(Activity(id: "gone", name: "Gone"))

        #expect(await vm.save() == false)
        #expect(vm.errorMessage == L10n.logTimeActivityMissing.text)
    }

    // MARK: - Delete into the undo buffer

    @Test("deleteConfirmed removes the entry into the buffer without syncing")
    func deleteConfirmedBuffersWithoutSync() async throws {
        let store = try await makeEditStore()
        let entry = storedEntry()
        try await store.createEntry(entry)
        let vm = makeViewModel(store: store, editing: entry)

        #expect(await vm.deleteConfirmed())

        #expect(try await store.entry(id: "e1") == nil)
        #expect(try await store.undoBufferMostRecent() != nil)
        #expect(try await store.outboxRows().allSatisfy { $0.op != "delete" })
    }

    @Test("deleteConfirmed on an already-gone entry still dismisses")
    func deleteConfirmedMissingDismisses() async throws {
        let store = try await makeEditStore()
        let vm = makeViewModel(store: store, editing: storedEntry())

        #expect(await vm.deleteConfirmed())
    }

    @Test("deleteConfirmed in CREATE mode does nothing")
    func deleteConfirmedCreateDoesNothing() async throws {
        let store = try await makeEditStore()
        let vm = makeViewModel(store: store)

        #expect(await vm.deleteConfirmed() == false)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    // MARK: - Helpers

    private func storedEntry(source: String = "manual") -> TimeEntry {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        return TimeEntry(
            id: "e1", activityID: "a1", activityName: "Reading",
            startedAt: start, endedAt: start.addingTimeInterval(3_600),
            durationSeconds: 3_600, source: source,
            createdAt: start, updatedAt: start
        )
    }

    private func makeEditStore() async throws -> LocalStore {
        let store = try LocalStore(url: temporaryStoreURL())
        try await store.createActivity(Activity(id: "a1", name: "Reading"))
        return store
    }

    private func makeViewModel(
        now: Date = Date(),
        initialActivity: Activity? = nil
    ) -> LogTimeViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, initialActivity: initialActivity, now: now)
    }

    private func makeViewModel(
        store: LocalStore,
        editing entry: TimeEntry? = nil,
        initialActivity: Activity? = nil
    ) -> LogTimeViewModel {
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, initialActivity: initialActivity, editing: entry)
    }

    private func makeViewModel(editing entry: TimeEntry) -> LogTimeViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, editing: entry)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
