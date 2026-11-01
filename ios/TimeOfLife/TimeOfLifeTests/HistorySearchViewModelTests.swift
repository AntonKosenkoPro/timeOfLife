import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("HistorySearchViewModel")
struct HistorySearchViewModelTests {
    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1")))
    }

    private func makeVM(store: LocalStore) -> HistoryViewModel {
        HistoryViewModel(store: store, undoBuffer: UndoBufferStore(store: store))
    }

    private func entry(
        id: String,
        startedAt: Date,
        text: String,
        categoryIDs: [String] = [],
        notes: String = "",
        durationSeconds: Int? = 60
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationSeconds: durationSeconds,
            categoryIDs: categoryIDs,
            notes: notes
        )
    }

    private static func utc(_ iso: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let datePart = iso.split(separator: "T")[0].split(separator: "-").compactMap { Int($0) }
        let timePart = iso.split(separator: "T")[1].split(separator: ":").compactMap { Int($0) }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = datePart[0]
        comps.month = datePart[1]
        comps.day = datePart[2]
        comps.hour = timePart[0]
        comps.minute = timePart[1]
        return comps.date!
    }

    private func seedTwoDays(_ store: LocalStore) async throws {
        try await store.createCategory(Category(id: "c1", name: "Sport", icon: "figure.run"))
        try await store.createEntry(entry(
            id: "e1",
            startedAt: Self.utc("2026-10-05T10:00:00"),
            text: "Morning Gym",
            categoryIDs: ["c1"],
            notes: "remember the HR belt",
            durationSeconds: 1800
        ))
        try await store.createEntry(entry(
            id: "e2",
            startedAt: Self.utc("2026-10-05T18:00:00"),
            text: "Evening Run",
            durationSeconds: 3600
        ))
        try await store.createEntry(entry(
            id: "e3",
            startedAt: Self.utc("2026-10-04T09:00:00"),
            text: "Gym Induction",
            durationSeconds: 600
        ))
    }

    // MARK: - Blank-query parity (task 3.4)

    @Test("blank and whitespace-only queries show exact unfiltered History")
    func blankParity() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        let baseline = HistoryViewModel.makeDayGroups(
            entries: try await store.entries(),
            now: Date()
        )
        #expect(vm.dayGroups.map(\.id) == baseline.map(\.id))
        #expect(vm.isSearchFiltering == false)
        #expect(vm.searchDiagnostic == nil)

        vm.searchText = "   "
        #expect(vm.dayGroups.map(\.id) == baseline.map(\.id))
        #expect(vm.isSearchFiltering == false)
        #expect(vm.searchPresentation(for: baseline[0].entries[0]) == nil)
    }

    @Test("fresh view models start blank: no carried query, results, or excerpts")
    func freshStartsBlank() throws {
        let vm = makeVM(store: try makeStore())
        #expect(vm.searchText.isEmpty)
        #expect(vm.searchDiagnostic == nil)
        #expect(vm.isSearchFiltering == false)
    }

    // MARK: - Filtered derivation (tasks 3.4, 4.4)

    @Test("valid queries narrow groups newest-first and omit empty days")
    func filteredGroups() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym"
        #expect(vm.isSearchFiltering)
        #expect(vm.searchDiagnostic == nil)
        let ids = vm.dayGroups.flatMap(\.entries).map(\.id)
        #expect(ids == ["e1", "e3"])
        #expect(vm.dayGroups.count == 2)
    }

    @Test("matching entries appear once with matching totals")
    func matchingTotalsAndDedup() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym belt in:name,notes"
        let ids = vm.dayGroups.flatMap(\.entries).map(\.id)
        #expect(ids == ["e1"])
        let expected = HistoryViewModel.naturalDuration(1800)
        #expect(vm.dayGroups[0].total == expected)
    }

    @Test("scope-only and date-only queries enter filtered presentation")
    func qualifierOnlyFiltering() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "in:notes"
        #expect(vm.isSearchFiltering)
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e1", "e3"])
        #expect(vm.searchPresentation(for: vm.dayGroups[0].entries[0])?.excerpt == nil)
    }

    @Test("invalid queries show a diagnostic and no rows")
    func invalidState() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "source:healthkit"
        #expect(vm.searchDiagnostic != nil)
        #expect(vm.dayGroups.isEmpty)
        #expect(!vm.isSearchFiltering)
        vm.searchText = ""
        #expect(vm.searchDiagnostic == nil)
        #expect(vm.dayGroups.flatMap(\.entries).count == 3)
    }

    @Test("loads re-apply the latest query, never a stale capture")
    func latestQueryWins() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        vm.searchText = "gym"
        await vm.load()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1", "e3"])
        vm.searchText = "run"
        await vm.load()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2"])
    }

    // MARK: - Extended grammar (task 12.2, section 12)

    @Test("OR groups return either side's matches newest-first")
    func orGroupsEndToEnd() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym OR run"
        #expect(vm.isSearchFiltering)
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e1", "e3"])
    }

    @Test("has: presence filters end to end with -has: negation")
    func hasPresenceEndToEnd() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        // Only e1 carries notes in the seed.
        vm.searchText = "has:notes"
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        vm.searchText = "-has:notes"
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e3"])
        // Only e1 carries a category in the seed.
        vm.searchText = "has:category"
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        vm.searchText = "-has:category"
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e3"])
    }

    @Test("ended: bounds filter on the entry end")
    func endedEndToEnd() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        // All seeds ended in 2026; none ended before 2020. Date-only
        // bounds stay timezone-proof for these far-apart years.
        vm.searchText = "ended:>2020-01-01"
        #expect(vm.isSearchFiltering)
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e2", "e1", "e3"])
        vm.searchText = "ended:<2020-01-01"
        #expect(vm.searchDiagnostic == nil)
        #expect(vm.dayGroups.isEmpty)
    }

    // MARK: - Lifecycle composition (task 5.1)

    @Test("edits, renames, and deletes re-evaluate without clearing the query")
    func reevaluationKeepsQuery() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym"

        // Editing an entry out of the match removes it from results.
        var edited = try #require(try await store.entry(id: "e1"))
        edited.activityText = "Morning Yoga"
        edited.notes = ""
        edited.updatedAt = Date()
        #expect(try await store.updateEntry(edited))
        await vm.load()
        #expect(vm.searchText == "gym")
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e3"])

        // A category rename is re-evaluated too.
        vm.searchText = "sport in:categories"
        await vm.load()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        var renamed = try #require(try await store.category(id: "c1"))
        renamed.name = "Leisure"
        renamed.updatedAt = Date()
        _ = try await store.updateCategory(renamed)
        await vm.load()
        #expect(vm.searchText == "sport in:categories")
        #expect(vm.dayGroups.isEmpty)
    }

    @Test("undo restores entries without clearing the query")
    func undoKeepsQuery() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym"
        _ = try await store.deleteEntryUndoable(id: "e3", deletedAt: Date())
        await vm.load()
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1"])
        await vm.performUndo()
        #expect(vm.searchText == "gym")
        #expect(vm.dayGroups.flatMap(\.entries).map(\.id) == ["e1", "e3"])
    }

    @Test("a fresh view model carries no query across account remounts")
    func accountRemountResets() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let first = makeVM(store: store)
        await first.load()
        first.searchText = "belt in:notes"
        #expect(first.isSearchFiltering)

        // `RootView` recreates account-bound shell state on sign-out or
        // account change, so the next History owns a blank view model.
        let second = makeVM(store: store)
        await second.load()
        #expect(second.searchText.isEmpty)
        #expect(!second.isSearchFiltering)
        #expect(second.dayGroups.flatMap(\.entries).count == 3)
    }

    @Test("queries never reach persistent storage")
    func queryNotPersisted() async throws {
        let store = try makeStore()
        try await seedTwoDays(store)
        let vm = makeVM(store: store)
        await vm.load()
        let query = "belt in:notes \(UUID().uuidString)" // unique token: any hit is a leak
        func leaks(_ value: Any) -> Bool { // Data: UTF-8-decode + raw-byte-scan; containers recursed
            if let data = value as? Data {
                return String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains(query) == true
                    || data.range(of: Data(query.utf8)) != nil
            }
            if let dict = value as? [String: Any] { return dict.contains { leaks($0.key) || leaks($0.value) } }
            if let array = value as? [Any] { return array.contains(where: leaks) }
            return ((value as? String) ?? String(describing: value)).localizedCaseInsensitiveContains(query)
        }
        func scan() -> [String] { // `.standard` + the App Group suite the app uses; read-only
            var dict = UserDefaults.standard.dictionaryRepresentation()
            if let extra = UserDefaults(suiteName: LocalStore.appGroupID)?.dictionaryRepresentation() {
                dict.merge(extra) { kept, _ in kept }
            }
            return dict.compactMap { leaks($0.key) || leaks($0.value) ? $0.key : nil }
        }
        vm.searchText = query
        let leaked = scan() // fresh-UUID token: any hit is a leak, no before-snapshot needed
        #expect(leaked.isEmpty, "search query leaked into UserDefaults: \(leaked)")
        #expect(leaked.isEmpty, "search query leaked into UserDefaults: \(leaked)")
    }

    @Test("a failed fetch never presents as a zero-match query, even on later keystrokes")
    func failedFetchNeverFilters() async {
        // Unbound store: every read throws `notBound`, so the fetch fails.
        let vm = makeVM(store: LocalStore())
        await vm.load()
        #expect(!vm.isSearchFiltering)
        #expect(vm.dayGroups.isEmpty)
        // The regression: the next applySearch — any keystroke, or the
        // foreground time-context refresh — re-entered the filtering
        // branch on the never-loaded empty snapshot, resurrecting the
        // no-results + Clear-search state the failure path removed.
        vm.searchText = "gym"
        #expect(!vm.isSearchFiltering, "keystroke after a failed fetch must not filter")
        #expect(vm.dayGroups.isEmpty)
        #expect(vm.searchSummary == nil)
        vm.refreshTimeContext()
        #expect(!vm.isSearchFiltering, "foreground refresh after a failed fetch must not filter")
        #expect(vm.dayGroups.isEmpty)
    }

    // MARK: - Performance (task 5.3)

    @Test("thousands-entry derivation stays comfortably interactive")
    func derivationPerformance() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var entries: [TimeEntry] = []
        entries.reserveCapacity(3000)
        let notes = String(repeating: "training log filler text with squats buried inside ", count: 20)
        for index in 0 ..< 3000 {
            entries.append(TimeEntry(
                id: "p\(index)",
                activityText: index.isMultiple(of: 3) ? "Gym session \(index)" : "Run \(index)",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60)),
                endedAt: Date(timeIntervalSince1970: 1_700_003_600 + Double(index * 60)),
                durationSeconds: 3600,
                categoryIDs: ["c1"],
                notes: index.isMultiple(of: 5) ? notes : "short note"
            ))
        }
        let categories = [Category(id: "c1", name: "Sport", icon: "figure.run")]
        guard case .valid(let parsedQuery) = HistorySearchParser.parse(
            "gym squats in:name,notes started:>=2023-11-01",
            calendar: calendar
        ) else {
            Issue.record("expected valid query")
            return
        }
        let query = parsedQuery
        // The full per-keystroke path: snapshot derivation plus day
        // regrouping (labels included), exactly what `applySearch` runs on
        // every query edit. `ContinuousClock` (monotonic) replaces the wall
        // clock so NTP steps cannot skew the guard.
        let clock = ContinuousClock()
        var hits = 0
        var presentations = 0
        var groups: [DayGroup] = []
        let elapsed = clock.measure {
            let derived = HistorySearchEvaluator.derive(
                entries: entries,
                categoriesByID: ["c1": categories[0]],
                query: query,
                calendar: calendar
            )
            hits = derived.matched.count
            presentations = derived.presentations.count
            groups = HistoryViewModel.makeDayGroups(
                entries: derived.matched,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                calendar: calendar
            )
        }
        #expect(hits > 0)
        #expect(presentations > 0)
        #expect(!groups.isEmpty)
        // Pathological-regression guard, not a performance target: measured
        // ~0.1s for this corpus in a local Debug simulator build, so 2s
        // leaves ~20x headroom for slow shared CI runners while still
        // catching algorithmic blowups (the full per-keystroke path must
        // stay synchronous-safe without debounce).
        #expect(elapsed < .seconds(2))
    }
}
