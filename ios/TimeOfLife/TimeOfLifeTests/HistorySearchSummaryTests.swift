import Testing
import Foundation
@testable import TimeOfLife

/// Pins the History result summary and the notes-excerpt identity
/// (`add-history-search` change, section 11): scrolling summary counts and
/// totals with localized plurals, no-summary states, and the at-a-glance +
/// VoiceOver distinction between notes excerpts and category highlights.
@MainActor
@Suite("HistorySearchSummary")
struct HistorySearchSummaryTests {
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
        notes: String = "",
        durationSeconds: Int? = 60,
        endedAt: Date? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: endedAt ?? startedAt.addingTimeInterval(60),
            durationSeconds: durationSeconds,
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

    private func bundle(for locale: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: locale, ofType: "lproj"),
                                "Missing \(locale).lproj in main bundle")
        return try #require(Bundle(path: path))
    }

    // MARK: - Summary math (task 11.2)

    @Test("match totals follow the known-duration-only rule: in-progress contributes zero")
    func matchTotalInProgressZero() {
        let base = Self.utc("2026-10-05T10:00:00")
        let entries = [
            entry(id: "e1", startedAt: base, text: "Gym", durationSeconds: 1800),
            entry(id: "e2", startedAt: base, text: "Run", durationSeconds: 2700),
            // In-progress: no known duration.
            entry(id: "e3", startedAt: base, text: "Swim", durationSeconds: nil, endedAt: nil),
        ]
        #expect(HistorySearchSummary.totalSeconds(entries) == 4500)
        #expect(HistorySearchSummary.totalSeconds([]) == 0)
    }

    @Test("spec scenario: 3 entries at 30, 45, and 0 minutes summarize 3 with a 1h 15m total")
    func specScenarioSummary() throws {
        let en = try bundle(for: "en")
        let text = try #require(HistorySearchSummary.text(
            count: 3,
            totalSeconds: 4500,
            locale: Locale(identifier: "en"),
            bundle: en
        ))
        #expect(text == "3 matching entries · 1h 15m")
    }

    @Test("zero matches produce no summary text")
    func zeroCountNoSummary() throws {
        let en = try bundle(for: "en")
        #expect(HistorySearchSummary.text(
            count: 0,
            totalSeconds: 0,
            locale: Locale(identifier: "en"),
            bundle: en
        ) == nil)
    }

    // MARK: - Plural forms (task 11.2)

    @Test("English singular and plural counts")
    func englishPlurals() throws {
        let en = try bundle(for: "en")
        let singular = try #require(HistorySearchSummary.text(
            count: 1,
            totalSeconds: 60,
            locale: Locale(identifier: "en"),
            bundle: en
        ))
        #expect(singular.hasPrefix("1 matching entry · "))
        let plural = try #require(HistorySearchSummary.text(
            count: 2,
            totalSeconds: 120,
            locale: Locale(identifier: "en"),
            bundle: en
        ))
        #expect(plural.hasPrefix("2 matching entries · "))
    }

    @Test("every locale resolves a summary with its own plural forms")
    func localePluralSpotChecks() throws {
        let expectations: [(locale: String, one: String, other: String)] = [
            ("ru", "1 совпадение", "5 совпадений"),
            ("es-419", "1 resultado encontrado", "2 resultados encontrados"),
            ("pt-BR", "1 resultado encontrado", "2 resultados encontrados"),
            ("zh-Hans", "1 条匹配", "2 条匹配"),
        ]
        for (locale, one, other) in expectations {
            let bundle = try bundle(for: locale)
            let singular = try #require(HistorySearchSummary.text(
                count: 1,
                totalSeconds: 60,
                locale: Locale(identifier: locale),
                bundle: bundle
            ))
            #expect(singular.contains(one), "singular in \(locale): \(singular)")
            let plural = try #require(HistorySearchSummary.text(
                count: locale == "ru" ? 5 : 2,
                totalSeconds: 120,
                locale: Locale(identifier: locale),
                bundle: bundle
            ))
            #expect(plural.contains(other), "plural in \(locale): \(plural)")
        }
    }

    @Test("every locale ships the summary stringsdict with the right plural variants")
    func stringsdictVariantsPerLocale() throws {
        // Variant keys per locale: Russian needs one/few/many, Chinese only
        // other, the rest one/other (all with an other fallback).
        let expectedVariants: [String: Set<String>] = [
            "en": ["one", "other"],
            "ru": ["one", "few", "many", "other"],
            "zh-Hans": ["other"],
            "es-419": ["one", "other"],
            "pt-BR": ["one", "other"],
        ]
        for locale in ["en", "ru", "zh-Hans", "es-419", "pt-BR"] {
            let lproj = try #require(Bundle.main.path(forResource: locale, ofType: "lproj"))
            let dictPath = "\(lproj)/Localizable.stringsdict"
            let data = try #require(FileManager.default.contents(atPath: dictPath))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            let dict = try #require(plist as? [String: Any])
            let entry = try #require(dict["history.search.summary"] as? [String: Any])
            let format = try #require(entry["NSStringLocalizedFormatKey"] as? String)
            #expect(format.contains("%#@entries@"), "format in \(locale)")
            let plurals = try #require(entry["entries"] as? [String: Any])
            let variants = Set(plurals.keys).subtracting([
                "NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey",
            ])
            #expect(variants == expectedVariants[locale], "variants in \(locale): \(variants)")
            for key in expectedVariants[locale] ?? [] {
                let value = try #require(plurals[key] as? String)
                #expect(value.contains("%d"), "count placeholder in \(locale).\(key)")
            }
        }
    }

    // MARK: - No-summary states (task 11.2)

    @Test("blank, invalid, and zero-match queries publish no summary; results do")
    func viewModelSummaryStates() async throws {
        let store = try makeStore()
        try await store.createEntry(entry(
            id: "e1",
            startedAt: Self.utc("2026-10-05T10:00:00"),
            text: "Morning Gym",
            durationSeconds: 1800
        ))
        let vm = makeVM(store: store)
        await vm.load()
        #expect(vm.searchSummary == nil)

        vm.searchText = "   "
        #expect(vm.searchSummary == nil)

        vm.searchText = "source:healthkit"
        #expect(vm.searchDiagnostic != nil)
        #expect(vm.searchSummary == nil)

        vm.searchText = "yoga"
        #expect(vm.searchDiagnostic == nil)
        #expect(vm.dayGroups.isEmpty)
        #expect(vm.searchSummary == nil)

        vm.searchText = "gym"
        let summary = try #require(vm.searchSummary)
        #expect(summary.contains("1"))
        #expect(summary.contains(HistoryViewModel.naturalDuration(1800)))

        // Scope-only and date-only queries with matches summarize too.
        vm.searchText = "in:name"
        #expect(vm.searchSummary != nil)
        vm.searchText = "started:2026-10-05"
        #expect(vm.searchSummary != nil)

        vm.searchText = ""
        #expect(vm.searchSummary == nil)
    }

    @Test("in-progress matches count toward entries but add zero to the total")
    func inProgressSummary() async throws {
        let store = try makeStore()
        let base = Self.utc("2026-10-05T10:00:00")
        try await store.createEntry(entry(
            id: "e1",
            startedAt: base,
            text: "Gym session",
            durationSeconds: 1800
        ))
        try await store.createEntry(TimeEntry(
            id: "e2",
            activityText: "Gym ongoing",
            startedAt: base,
            endedAt: nil,
            durationSeconds: nil
        ))
        let vm = makeVM(store: store)
        await vm.load()
        vm.searchText = "gym"
        let summary = try #require(vm.searchSummary)
        #expect(summary.contains("2"))
        #expect(summary.contains(HistoryViewModel.naturalDuration(1800)))
    }

    // MARK: - Excerpt vs category distinction (task 11.2)

    @Test("VoiceOver identifies excerpts as notes content; category-only rows carry no notes label")
    func excerptNotesIdentification() {
        let notesLabel = L10n.historySearchNotesLabel.text
        let withExcerpt = EntryRow.accessibilityLabel(
            entryText: "Gym",
            categoryNames: "Health",
            timeframeText: "14:00 – 15:20",
            durationText: "1h 20m",
            isInProgress: false,
            viaText: "",
            hasNotes: true,
            excerptText: "… around squats …"
        )
        #expect(withExcerpt.contains("\(notesLabel) … around squats …"))
        #expect(withExcerpt.contains(L10n.historyHasNotes.text))

        let categoryOnly = EntryRow.accessibilityLabel(
            entryText: "Trip",
            categoryNames: "Sport club",
            timeframeText: "14:00 – 15:20",
            durationText: "30m",
            isInProgress: false,
            viaText: "",
            hasNotes: false,
            excerptText: ""
        )
        #expect(!categoryOnly.contains(notesLabel))
    }

    @Test("the row label reads the displayed excerpt, never the full hidden note")
    func excerptLabelHidesFullNote() {
        let fullNote = "warmup prefix around squats then cooldown suffix"
        let label = EntryRow.accessibilityLabel(
            entryText: "Gym",
            categoryNames: "",
            timeframeText: "14:00 – 15:20",
            durationText: "1h 20m",
            isInProgress: false,
            viaText: "",
            hasNotes: true,
            excerptText: "… around squats …"
        )
        #expect(label.contains("… around squats …"))
        #expect(!label.contains("warmup prefix"))
        #expect(!label.contains("cooldown suffix"))
        #expect(!label.contains(fullNote))
    }
}
