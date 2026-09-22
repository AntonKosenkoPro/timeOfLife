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

    @Test("sheet opens with empty name, categories, and notes")
    func defaultEmptyFields() {
        let vm = makeViewModel()
        #expect(vm.name.isEmpty)
        #expect(vm.categoryIDs.isEmpty)
        #expect(vm.notes.isEmpty)
        #expect(!vm.isAddEnabled)
    }

    // MARK: - Validity gate

    @Test("Add is disabled with an empty name")
    func gateRequiresName() {
        let vm = makeViewModel()
        #expect(!vm.isAddEnabled)
    }

    @Test("Add is disabled with a whitespace-only name")
    func gateWhitespaceName() {
        let vm = makeViewModel()
        vm.name = "   "
        #expect(!vm.isAddEnabled)
    }

    @Test("Add enables when the trimmed name is non-empty and End is after Start")
    func gateValidForm() {
        let vm = makeViewModel()
        vm.name = " Reading "

        #expect(vm.isAddEnabled)
    }

    @Test("Add disables when End moves to Start")
    func gateEndEqualStart() {
        let vm = makeViewModel()
        vm.name = "Reading"

        vm.setEndsAt(vm.startsAt)

        #expect(!vm.isAddEnabled)
    }

    @Test("Add disables when End moves before Start")
    func gateEndBeforeStart() {
        let vm = makeViewModel()
        vm.name = "Reading"

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
        vm.name = "Reading"
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

    // MARK: - Category selection

    @Test("toggling categories preserves selection order")
    func togglePreservesOrder() {
        let vm = makeViewModel()
        vm.toggleCategory("c1")
        vm.toggleCategory("c2")
        vm.toggleCategory("c3")
        #expect(vm.categoryIDs == ["c1", "c2", "c3"])

        vm.toggleCategory("c2")
        #expect(vm.categoryIDs == ["c1", "c3"])
    }

    // MARK: - Save

    @Test("save persists a manual entry with text, tags, notes, and derived duration")
    func savePersistsManualEntry() async throws {
        let vm = makeViewModel()
        try? await vm.service.store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try? await vm.service.store.createCategory(Category(id: "c2", name: "Health", icon: CatalogIcon.briefcase.rawValue))
        vm.name = "  Reading  "
        vm.notes = "Chapter 4"
        vm.toggleCategory("c1")
        vm.toggleCategory("c2")

        let saved = await vm.save()

        #expect(saved)
        let entries = try await vm.service.store.entries()
        #expect(entries.count == 1)
        #expect(entries[0].activityText == "Reading")
        #expect(entries[0].categoryIDs == ["c1", "c2"])
        #expect(entries[0].notes == "Chapter 4")
        #expect(entries[0].startedAt == vm.startsAt)
        #expect(entries[0].endedAt == vm.endsAt)
        #expect(entries[0].durationSeconds == 3_600)
        #expect(entries[0].source == "manual")
        #expect(entries[0].sourceRef == nil)
    }

    @Test("save on an invalid form returns false without an error")
    func saveInvalidForm() async {
        let vm = makeViewModel()

        let saved = await vm.save()

        #expect(!saved)
        #expect(vm.errorMessage == nil)
    }

    @Test("save never re-resolves an activity — the entry owns its text")
    func saveWithoutActivityResolve() async throws {
        let vm = makeViewModel()
        vm.name = "Gym"

        let saved = await vm.save()

        #expect(saved)
        #expect(try await vm.service.store.entries().first?.activityText == "Gym")
    }

    // MARK: - Modes

    @Test("mode routing: none is create, manual is edit, imported is locked")
    func modeRouting() {
        #expect(LogTimeViewModel.mode(for: nil) == .create)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "manual")) == .edit)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "garmin")) == .locked)
        #expect(LogTimeViewModel.mode(for: storedEntry(source: "healthkit")) == .locked)
    }

    @Test("EDIT prefills name, categories, notes, and interval from the entry")
    func editPrefillsFromEntry() async throws {
        let entry = storedEntry(categoryIDs: ["c1", "c2"], notes: "Some notes")
        let vm = makeViewModel(editing: entry)

        #expect(vm.mode == .edit)
        #expect(!vm.isLocked)
        #expect(vm.name == "Reading")
        #expect(vm.categoryIDs == ["c1", "c2"])
        #expect(vm.notes == "Some notes")
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
        #expect(vm.name == "Reading")
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
        let store = try await makeStore()
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

    @Test("EDIT save retexts and retags only this entry")
    func editSaveRetextsRetags() async throws {
        let store = try await makeStore()
        let entry = storedEntry()
        try await store.createEntry(entry)
        let other = storedEntry(id: "e2")
        try await store.createEntry(other)
        try await store.createCategory(Category(id: "c9", name: "Health", icon: CatalogIcon.briefcase.rawValue))
        let vm = makeViewModel(store: store, editing: entry)
        vm.name = "Workout"
        vm.toggleCategory("c9")

        #expect(await vm.save())

        #expect(try await store.entry(id: "e1")?.activityText == "Workout")
        #expect(try await store.entry(id: "e1")?.categoryIDs == ["c9"])
        // No other entry with the same text changes (per-entry isolation).
        #expect(try await store.entry(id: "e2")?.activityText == "Reading")
        #expect(try await store.entry(id: "e2")?.categoryIDs.isEmpty == true)
    }

    @Test("EDIT save fails with the draft intact on a stale write")
    func editSaveStaleKeepsDraft() async throws {
        let store = try await makeStore()
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

    // MARK: - Delete into the undo buffer

    @Test("deleteConfirmed removes the entry into the buffer without syncing")
    func deleteConfirmedBuffersWithoutSync() async throws {
        let store = try await makeStore()
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
        let store = try await makeStore()
        let vm = makeViewModel(store: store, editing: storedEntry())

        #expect(await vm.deleteConfirmed())
    }

    @Test("deleteConfirmed in CREATE mode does nothing")
    func deleteConfirmedCreateDoesNothing() async throws {
        let store = try await makeStore()
        let vm = makeViewModel(store: store)

        #expect(await vm.deleteConfirmed() == false)
        #expect(try await store.undoBufferMostRecent() == nil)
    }

    // MARK: - Helpers

    private func storedEntry(
        id: String = "e1",
        source: String = "manual",
        categoryIDs: [String] = [],
        notes: String = ""
    ) -> TimeEntry {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        return TimeEntry(
            id: id, activityText: "Reading",
            startedAt: start, endedAt: start.addingTimeInterval(3_600),
            durationSeconds: 3_600, source: source,
            categoryIDs: categoryIDs, notes: notes,
            createdAt: start, updatedAt: start
        )
    }

    private func makeStore() async throws -> LocalStore {
        try LocalStore(url: temporaryStoreURL())
    }

    private func makeViewModel(
        now: Date = Date()
    ) -> LogTimeViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, now: now)
    }

    private func makeViewModel(
        store: LocalStore,
        editing entry: TimeEntry? = nil
    ) -> LogTimeViewModel {
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, editing: entry)
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
