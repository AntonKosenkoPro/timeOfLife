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

    // MARK: - Helpers

    private func makeViewModel(
        now: Date = Date(),
        initialActivity: Activity? = nil
    ) -> LogTimeViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let service = TimerService(store: store)
        return LogTimeViewModel(service: service, initialActivity: initialActivity, now: now)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite")
    }
}
