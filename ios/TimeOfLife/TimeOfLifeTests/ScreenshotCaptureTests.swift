// swiftlint:disable file_length
#if SCREENSHOT_CAPTURE
import Testing
import Foundation
@testable import TimeOfLife
import LifioLiveActivityCore

/// Capture pipeline + isolation tests (tasks 2.5/3.2/4.3). Gated: they run
/// under the TimeOfLife-Screenshot scheme, where the fixture and preparation
/// code compile in. Debug builds compile this file to nothing.
@MainActor
@Suite("Screenshot capture")
struct ScreenshotCaptureTests {

    private func requestData(
        frame: String = "track-running",
        mode: String = "app-clock-pinned",
        locale: String = "en",
        region: String = "US",
        timezone: String = "America/Chicago"
    ) -> Data {
        let dict: [String: Any] = [
            "schema_version": 1,
            "deck_version": "en-austin-1",
            "locale": locale,
            "region": region,
            "timezone": timezone,
            "calendar": "gregorian",
            "week_rule": "locale-native",
            "reference_local_iso": "2026-10-20T09:41:00",
            "app_elapsed_s": 754,
            "frames": ["track-running", "insights", "history", "add-entry", "live-activity"],
            "frame": frame,
            "mode": mode,
            "run_id": "test-run",
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func parsedRequest() throws -> ScreenshotCaptureRequest {
        try ScreenshotRequestLoader.parse(data: requestData())
    }

    private func parsedRequest(locale: String, region: String, timezone: String) throws -> ScreenshotCaptureRequest {
        try ScreenshotRequestLoader.parse(data: requestData(locale: locale, region: region, timezone: timezone))
    }

    @Test("preparation yields 55 stable entries with resolvable links")
    func preparationCounts() async throws {
        let context = try await ScreenshotPreparation.prepare(request: parsedRequest())
        let entries = try await context.store.entries()
        #expect(entries.count == 55)
        #expect(Set(entries.map(\.id)).count == 55)
        let categories = try await context.store.categories()
        #expect(categories.count == 8)
        #expect(categories.map(\.name) == ["Education", "Entertainment", "Food", "Hobby", "Relax", "Sleep", "Sport", "Work"])
        for entry in entries {
            for id in entry.categoryIDs {
                #expect(context.categoriesByID[id] != nil)
            }
            #expect(entry.endedAt != nil)
        }
        // Multi-category attribution survives the round trip, in order.
        let acl = entries.first { $0.activityText == "ACL festival" }
        #expect(acl?.categoryIDs == [ScreenshotFixture.entertainmentID, ScreenshotFixture.hobbyID])
        // Exactly one notes-bearing entry (the History glyph).
        #expect(entries.count(where:) { !$0.notes.isEmpty } == 1)
        // Exact-text distinction survives (case-sensitive identity).
        #expect(entries.contains { $0.activityText == "Coffee" })
        #expect(entries.contains { $0.activityText == "coffee" })
    }

    @Test("computed totals match the independently calculated manifest")
    func preparationTotals() async throws {
        let context = try await ScreenshotPreparation.prepare(request: parsedRequest())
        let totals = context.totals
        // Independently calculated from the deck definition (python cross-check).
        #expect(totals.allSeconds == 198_600)
        #expect(totals.todaySeconds == 4500)
        #expect(totals.weekSeconds == 23_100)
        #expect(totals.categorySeconds == [
            ScreenshotFixture.educationID: 8700,
            ScreenshotFixture.entertainmentID: 38_700,
            ScreenshotFixture.foodID: 41_400,
            ScreenshotFixture.hobbyID: 20_100,
            ScreenshotFixture.relaxID: 11_700,
            ScreenshotFixture.sportID: 42_300,
            ScreenshotFixture.workID: 51_000,
        ])
        #expect(totals.textSeconds["Deep work"] == 27_000)
        #expect(totals.textSeconds["Live music"] == 18_000)
        #expect(totals.textSeconds["Coffee"] == 3900)
        #expect(totals.textSeconds["coffee"] == 3300)
        #expect(totals.textSeconds.count == 27)
    }

    @Test("localized specs preserve durations, order, and category links")
    func localizedSpecsPreserveTimeline() throws {
        let base = ScreenshotFixture.entries
        #expect(base.count == 55)
        for locale in ["ru", "zh-Hans", "es-419", "pt-BR"] {
            let localized = ScreenshotFixture.entries(for: locale)
            #expect(localized.count == 55, "count \(locale)")
            #expect(Set(localized.map { $0.text }).count == 27, "distinct \(locale)")
            for (index, spec) in localized.enumerated() {
                let en = base[index]
                #expect(spec.daysAgo == en.daysAgo, "\(locale)[\(index)] daysAgo")
                #expect(spec.hour == en.hour && spec.minute == en.minute, "\(locale)[\(index)] wall time")
                #expect(spec.durationMinutes == en.durationMinutes, "\(locale)[\(index)] duration")
                #expect(spec.categoryIDs == en.categoryIDs, "\(locale)[\(index)] links")
            }
            // Exactly one notes-bearing entry at fixture index 22 (0-based 21).
            #expect(localized.filter { !$0.notes.isEmpty }.count == 1, "notes count \(locale)")
            #expect(!localized[21].notes.isEmpty, "notes position \(locale)")
            // Draft twin duplicates entry 1; add-entry sample duplicates the
            // Deep-work entries with the notes value.
            #expect(localized[0].text == ScreenshotFixture.draftText(for: locale), "draft twin \(locale)")
            #expect(localized[21].text == ScreenshotFixture.addEntryText(for: locale), "add-entry text \(locale)")
            #expect(localized[21].notes == ScreenshotFixture.addEntryNotes(for: locale), "add-entry notes \(locale)")
        }
        // ru/zh decks carry no Latin characters in user copy (risks reports).
        let latin = try NSRegularExpression(pattern: "[A-Za-z]")
        for locale in ["ru", "zh-Hans"] {
            for spec in ScreenshotFixture.entries(for: locale) {
                for value in [spec.text, spec.notes] where !value.isEmpty {
                    let range = NSRange(value.startIndex..<value.endIndex, in: value)
                    #expect(latin.firstMatch(in: value, range: range) == nil, "\(locale) leakage: \(value)")
                }
            }
        }
    }

    private struct LocalizedDeckExpectation {
        let locale: String
        let region: String
        let timezone: String
        let categoryNames: Set<String>
        let weekSeconds: Int
    }

    private static let localizedDeckExpectations: [LocalizedDeckExpectation] = [
        LocalizedDeckExpectation(
            locale: "ru", region: "RU", timezone: "Europe/Moscow",
            categoryNames: ["Работа", "Хобби", "Спорт", "Образование", "Отдых", "Сон", "Развлечения", "Еда"],
            weekSeconds: 12_300
        ),
        LocalizedDeckExpectation(
            locale: "zh-Hans", region: "CN", timezone: "Asia/Shanghai",
            categoryNames: ["工作", "爱好", "运动", "学习", "休闲", "睡眠", "娱乐", "美食"],
            weekSeconds: 23_100
        ),
        LocalizedDeckExpectation(
            locale: "es-419", region: "MX", timezone: "America/Mexico_City",
            categoryNames: ["Trabajo", "Pasatiempo", "Deporte", "Estudio", "Descanso", "Sueño", "Entretenimiento", "Comida"],
            weekSeconds: 23_100
        ),
        LocalizedDeckExpectation(
            locale: "pt-BR", region: "BR", timezone: "America/Sao_Paulo",
            categoryNames: ["Trabalho", "Hobby", "Esporte", "Estudo", "Descanso", "Sono", "Entretenimento", "Comida"],
            weekSeconds: 23_100
        ),
    ]

    private static let localizedCategorySeconds = [
        ScreenshotFixture.educationID: 8700,
        ScreenshotFixture.entertainmentID: 38_700,
        ScreenshotFixture.foodID: 41_400,
        ScreenshotFixture.hobbyID: 20_100,
        ScreenshotFixture.relaxID: 11_700,
        ScreenshotFixture.sportID: 42_300,
        ScreenshotFixture.workID: 51_000,
    ]

    private func verifyLocalizedDeck(_ expected: LocalizedDeckExpectation) async throws {
        let request = try parsedRequest(locale: expected.locale, region: expected.region, timezone: expected.timezone)
        let context = try await ScreenshotPreparation.prepare(request: request)
        let entries = try await context.store.entries()
        #expect(entries.count == 55, "entries \(expected.locale)")
        let categories = try await context.store.categories()
        #expect(categories.count == 8, "categories \(expected.locale)")
        #expect(Set(categories.map(\.name)) == expected.categoryNames, "names \(expected.locale)")
        #expect(Set(categories.map(\.id)).count == 8, "stable IDs \(expected.locale)")
        for entry in entries {
            for id in entry.categoryIDs {
                #expect(context.categoriesByID[id] != nil, "link \(expected.locale)")
            }
            #expect(entry.endedAt != nil, "committed \(expected.locale)")
        }
        // Ordered multi-category links survive at the same stable IDs.
        #expect(entries.first { $0.id == "shot-e07" }?.categoryIDs == [ScreenshotFixture.entertainmentID, ScreenshotFixture.hobbyID], "acl \(expected.locale)")
        #expect(entries.first { $0.id == "shot-e21" }?.categoryIDs == [ScreenshotFixture.sportID, ScreenshotFixture.entertainmentID], "football-1 \(expected.locale)")
        #expect(entries.first { $0.id == "shot-e47" }?.categoryIDs == [ScreenshotFixture.sportID, ScreenshotFixture.entertainmentID], "football-2 \(expected.locale)")
        // The single notes-bearing entry keeps its stable ID.
        #expect(entries.first { !$0.notes.isEmpty }?.id == "shot-e22", "notes position \(expected.locale)")
        // Duration totals are locale-invariant; the week total follows
        // locale-native week rules (ru starts Monday, the rest Sunday).
        let totals = context.totals
        #expect(totals.allSeconds == 198_600, "all \(expected.locale)")
        #expect(totals.todaySeconds == 4500, "today \(expected.locale)")
        #expect(totals.weekSeconds == expected.weekSeconds, "week \(expected.locale)")
        #expect(totals.categorySeconds == Self.localizedCategorySeconds, "categories \(expected.locale)")
        #expect(totals.textSeconds.count == 27, "texts \(expected.locale)")
        let draftTwin = ScreenshotFixture.draftText(for: expected.locale)
        #expect(totals.textSeconds[draftTwin] == 7500, "twin \(expected.locale)")
        #expect(totals.textSeconds[ScreenshotFixture.addEntryText(for: expected.locale)] == 27_000, "deep \(expected.locale)")
        // Running draft stays uncommitted with the localized twin text.
        let draft = try await context.store.timerDraft()
        #expect(draft?.activityText == draftTwin, "draft \(expected.locale)")
        #expect(draft?.categoryIDs == [ScreenshotFixture.sportID], "draft cats \(expected.locale)")
        #expect(draft?.startedAt == request.referenceDate.addingTimeInterval(-754), "draft anchor \(expected.locale)")
        // Add-entry sample validates through the real Log Time gate.
        let container = ScreenshotApp.makeContainer(
            store: context.store,
            sessionDirectory: context.sessionDirectory,
            liveActivities: NoopLiveActivityController()
        )
        try ScreenshotAddEntry.validate(request: request, container: container)
        let form = ScreenshotAddEntry.makeForm(service: container.timerService, request: request)
        #expect(form.trimmedName == ScreenshotFixture.addEntryText(for: expected.locale), "add text \(expected.locale)")
        #expect(form.notes == ScreenshotFixture.addEntryNotes(for: expected.locale), "add notes \(expected.locale)")
        #expect(form.isAddEnabled, "add gate \(expected.locale)")
        #expect(try await context.store.entries().count == 55, "add totals \(expected.locale)")
    }

    @Test("localized decks prepare with invariant duration totals")
    func localizedDecksTotals() async throws {
        for expected in Self.localizedDeckExpectations {
            try await verifyLocalizedDeck(expected)
        }
    }

    @Test("locale-native week contains the reference Tuesday from Sunday")
    func localeNativeWeek() throws {
        let request = try parsedRequest()
        let week = request.calendar.dateInterval(of: .weekOfYear, for: request.referenceDate)!
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = request.timeZone
        let start = chicago.dateComponents([.year, .month, .day, .weekday], from: week.start)
        // en_US weeks start Sunday: Oct 18, 2026.
        #expect(start.year == 2026 && start.month == 10 && start.day == 18 && start.weekday == 1)
        #expect(week.contains(request.referenceDate))
        // ru_RU weeks start Monday: Oct 19, 2026 (same local Tuesday).
        let ru = try parsedRequest(locale: "ru", region: "RU", timezone: "Europe/Moscow")
        let ruWeek = ru.calendar.dateInterval(of: .weekOfYear, for: ru.referenceDate)!
        var moscow = Calendar(identifier: .gregorian)
        moscow.timeZone = ru.timeZone
        let ruStart = moscow.dateComponents([.year, .month, .day, .weekday], from: ruWeek.start)
        #expect(ruStart.year == 2026 && ruStart.month == 10 && ruStart.day == 19 && ruStart.weekday == 2)
        #expect(ruWeek.contains(ru.referenceDate))
    }

    @Test("running draft anchors at reference minus elapsed and stays uncommitted")
    func draftAnchor() async throws {
        let request = try parsedRequest()
        let context = try await ScreenshotPreparation.prepare(request: request)
        let draft = try await context.store.timerDraft()
        #expect(draft?.activityText == ScreenshotFixture.draftText)
        #expect(draft?.categoryIDs == ScreenshotFixture.draftCategoryIDs)
        #expect(draft?.startedAt == request.referenceDate.addingTimeInterval(-754))
        // Committed totals exclude the draft (no in-progress entries).
        let entries = try await context.store.entries()
        #expect(entries.allSatisfy { $0.endedAt != nil })
    }

    @Test("restart replaces the dataset instead of accumulating")
    func cleanRestart() async throws {
        let request = try parsedRequest()
        _ = try await ScreenshotPreparation.prepare(request: request)
        let second = try await ScreenshotPreparation.prepare(request: request)
        #expect(try await second.store.entries().count == 55)
    }

    @Test("add-entry sample satisfies the Log Time gate with totals unchanged")
    func addEntrySample() async throws {
        let request = try parsedRequest()
        let context = try await ScreenshotPreparation.prepare(request: request)
        let interval = ScreenshotFixture.addEntryInterval(
            calendar: request.calendar,
            referenceDate: request.referenceDate
        )
        #expect(interval.end.timeIntervalSince(interval.start) == 3600)
        let container = ScreenshotApp.makeContainer(
            store: context.store,
            sessionDirectory: context.sessionDirectory,
            liveActivities: NoopLiveActivityController()
        )
        // The real validation path (same factory the sheet uses).
        try ScreenshotAddEntry.validate(request: request, container: container)
        let form = ScreenshotAddEntry.makeForm(service: container.timerService, request: request)
        #expect(form.trimmedName == ScreenshotFixture.addEntryText)
        #expect(form.categoryIDs == ScreenshotFixture.addEntryCategoryIDs)
        #expect(form.notes == ScreenshotFixture.addEntryNotes)
        #expect(form.isAddEnabled)
        // Draft-only: committed data still exactly the 55-entry manifest.
        #expect(try await context.store.entries().count == 55)
        #expect(context.totals.allSeconds == 198_600)
    }

    @Test("capture session lives outside the production App Group")
    func sessionIsolation() async throws {
        let context = try await ScreenshotPreparation.prepare(request: parsedRequest())
        let groupContainer = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.antonkosenko.timeoflifeapp")
        if let group = groupContainer {
            #expect(!context.sessionDirectory.path.hasPrefix(group.path))
        }
        // The isolated store URL is inside the session directory.
        #expect(context.sessionDirectory.path.contains("screenshot-capture"))
    }

    @Test("capture container never activates sync and signs in fictionally")
    func containerIsolation() async throws {
        let request = try parsedRequest()
        let context = try await ScreenshotPreparation.prepare(request: request)
        let container = ScreenshotApp.makeContainer(
            store: context.store,
            sessionDirectory: context.sessionDirectory,
            liveActivities: NoopLiveActivityController()
        )
        #expect(container.syncController.status == .inactive)
        guard case let .signedIn(session) = container.sessionStore.state else {
            Issue.record("capture session must be signed in")
            return
        }
        #expect(session.id == ScreenshotPreparation.fixtureUserID)
        #expect(session.email == ScreenshotApp.fixtureEmail)
    }

    @Test("pathological run IDs fail closed")
    func invalidRunID() {
        #expect(throws: ScreenshotRequestError.self) {
            _ = try ScreenshotPreparation.sessionDirectory(runID: "../escape")
        }
    }

    @Test("capture chrome follows the request locale in-process")
    func chromeFollowsRequestLocale() throws {
        // Regression: `applyProcessLocale` wrote AppleLanguages post-launch,
        // which never re-resolves `Bundle.main` in the same process, so
        // chrome lagged one run behind (ru showed English, zh showed
        // Russian) while the fixture already used the request locale.
        // Chrome must match the request in the same launch.
        let savedLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        let savedLocale = UserDefaults.standard.object(forKey: "AppleLocale")
        defer {
            if let value = savedLanguages {
                UserDefaults.standard.set(value, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            if let value = savedLocale {
                UserDefaults.standard.set(value, forKey: "AppleLocale")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLocale")
            }
            ScreenshotLocale.reset()
        }
        let expectations: [(locale: String, region: String, timezone: String, track: String, today: String, duration: String)] = [
            ("en", "US", "America/Chicago", "Track", "Today", "1h 12m"),
            ("ru", "RU", "Europe/Moscow", "Трек", "Сегодня", "1 ч 12 мин"),
            ("zh-Hans", "CN", "Asia/Shanghai", "记录", "今天", "1小时 12分钟"),
            ("es-419", "MX", "America/Mexico_City", "Registrar", "Hoy", "1 h 12 min"),
            ("pt-BR", "BR", "America/Sao_Paulo", "Registrar", "Hoje", "1h 12min"),
        ]
        for expected in expectations {
            let request = try parsedRequest(locale: expected.locale, region: expected.region, timezone: expected.timezone)
            ScreenshotApp.applyProcessLocale(request)
            #expect(L10n.tabTrack.text == expected.track, "chrome tab.track for \(expected.locale)")
            #expect(L10n.historyDayToday.text == expected.today, "chrome history.day.today for \(expected.locale)")
            #expect(String.localized("tab.track") == expected.track, "String.localized chrome for \(expected.locale)")
            // Duration/unit chrome follows the request through the default
            // locale (views pass no explicit locale).
            #expect(HistoryViewModel.naturalDuration(4320) == expected.duration, "duration chrome for \(expected.locale)")
            // The override resolves the request's own bundle …
            #expect(
                ScreenshotLocale.overrideBundle()?.bundlePath.contains("\(expected.locale).lproj") == true,
                "override bundle for \(expected.locale)"
            )
            // … while explicit locales always win (unit-test callers pass
            // explicit values and must not observe the override).
            #expect(
                HistoryViewModel.naturalDuration(4320, locale: Locale(identifier: "en")) == "1h 12m",
                "explicit locale wins under \(expected.locale) override"
            )
        }
    }

    @Test("live activity request locale follows the capture request")
    func liveActivityRequestLocaleFollowsRequest() throws {
        // Regression (pt-BR Stop showed es-419 "Detener"): the appex
        // process never sees `ScreenshotLocale`, so the request locale
        // must ride in the activity payload and faces must resolve from
        // it explicitly. The service supplies the payload locale; the
        // shared strings resolve it without touching system language.
        let savedLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        let savedLocale = UserDefaults.standard.object(forKey: "AppleLocale")
        defer {
            if let value = savedLanguages {
                UserDefaults.standard.set(value, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            if let value = savedLocale {
                UserDefaults.standard.set(value, forKey: "AppleLocale")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLocale")
            }
            ScreenshotLocale.reset()
        }
        for (locale, region, timezone, stop) in [
            ("en", "US", "America/Chicago", "Stop"),
            ("ru", "RU", "Europe/Moscow", "Стоп"),
            ("zh-Hans", "CN", "Asia/Shanghai", "停止"),
            ("es-419", "MX", "America/Mexico_City", "Detener"),
            ("pt-BR", "BR", "America/Sao_Paulo", "Parar"),
        ] as [(String, String, String, String)] {
            let request = try parsedRequest(locale: locale, region: region, timezone: timezone)
            ScreenshotApp.applyProcessLocale(request)
            #expect(LiveActivityService.requestLocaleIdentifier() == locale, "payload locale for \(locale)")
            #expect(LiveActivityStrings.stopTitle(localeIdentifier: LiveActivityService.requestLocaleIdentifier()) == stop, "face stop for \(locale)")
        }
        // pt-BR never resolves the Spanish title, even back-to-back after es-419.
        let es = try parsedRequest(locale: "es-419", region: "MX", timezone: "America/Mexico_City")
        ScreenshotApp.applyProcessLocale(es)
        #expect(LiveActivityService.requestLocaleIdentifier() == "es-419")
        let pt = try parsedRequest(locale: "pt-BR", region: "BR", timezone: "America/Sao_Paulo")
        ScreenshotApp.applyProcessLocale(pt)
        #expect(LiveActivityService.requestLocaleIdentifier() == "pt-BR")
        #expect(LiveActivityStrings.stopTitle(localeIdentifier: LiveActivityService.requestLocaleIdentifier()) == "Parar")
    }

    private func priorState(runID: String, sha256: String) -> CaptureState {
        CaptureState(
            status: "ready",
            requestSHA256: sha256,
            deckVersion: ScreenshotFixture.deckVersion,
            frame: ScreenshotFrame.trackRunning.rawValue,
            mode: ScreenshotMode.appClockPinned.rawValue,
            runID: runID,
            counts: CaptureStateCounts(entries: ScreenshotFixture.entryCount),
            expectedTotals: nil,
            build: nil,
            clocks: nil,
            liveActivity: nil,
            error: nil
        )
    }

    private func temporaryDocuments() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("cleanup with a mismatched SHA touches nothing")
    func cleanupMismatchTouchesNothing() async throws {
        let documents = try temporaryDocuments()
        try CaptureStateWriter.write(priorState(runID: "run-a", sha256: String(repeating: "a", count: 64)), to: documents)
        let ack = await ScreenshotCleanup.perform(
            documents: documents,
            invocation: ScreenshotCleanupInvocation(runID: "run-a", expectedSHA256: String(repeating: "b", count: 64))
        )
        #expect(ack.status == "mismatch")
        #expect(ack.endedActivityIDs.isEmpty)
        #expect(ack.removedSession == false)
        #expect(ack.error?.code == "cleanup-mismatch")
        // The acknowledgement itself is observable for the runner.
        #expect(try CaptureCleanupWriter.read(from: documents) == ack)
    }

    @Test("cleanup without a prior state fails closed")
    func cleanupWithoutPriorStateFailsClosed() async throws {
        let documents = try temporaryDocuments()
        let ack = await ScreenshotCleanup.perform(
            documents: documents,
            invocation: ScreenshotCleanupInvocation(runID: "run-a", expectedSHA256: String(repeating: "a", count: 64))
        )
        #expect(ack.status == "failure")
        #expect(ack.error?.code == "no-prior-state")
    }

    @Test("cleanup with a matching state removes only its session")
    func cleanupRemovesOwnSession() async throws {
        let runID = "test-cleanup-own"
        let sha = String(repeating: "c", count: 64)
        let documents = try temporaryDocuments()
        try CaptureStateWriter.write(priorState(runID: runID, sha256: sha), to: documents)
        let sessionDir = try ScreenshotPreparation.sessionDirectory(runID: runID)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let marker = sessionDir.appendingPathComponent("marker")
        FileManager.default.createFile(atPath: marker.path, contents: Data("x".utf8))
        #expect(FileManager.default.fileExists(atPath: marker.path))

        let ack = await ScreenshotCleanup.perform(
            documents: documents,
            invocation: ScreenshotCleanupInvocation(runID: runID, expectedSHA256: sha)
        )
        #expect(ack.status == "cleaned")
        #expect(ack.removedSession == true)
        #expect(!FileManager.default.fileExists(atPath: sessionDir.path))
        #expect(try CaptureCleanupWriter.read(from: documents) == ack)
    }
}
#endif
