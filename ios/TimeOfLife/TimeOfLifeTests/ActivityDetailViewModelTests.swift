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
}
