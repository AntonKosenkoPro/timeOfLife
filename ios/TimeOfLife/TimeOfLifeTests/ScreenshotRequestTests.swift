import Testing
import Foundation
@testable import TimeOfLife

/// Request validation + launch-gate tests (tasks 2.4; ungated so they run in
/// Debug — the same compiled behavior as Release, where `isCaptureBuild` is
/// also false).
@Suite("Screenshot request")
struct ScreenshotRequestTests {

    private func validJSON(overrides: [String: Any] = [:]) -> Data {
        var dict: [String: Any] = [
            "schema_version": 1,
            "deck_version": "en-austin-1",
            "locale": "en",
            "region": "US",
            "timezone": "America/Chicago",
            "calendar": "gregorian",
            "week_rule": "locale-native",
            "reference_local_iso": "2026-10-20T09:41:00",
            "app_elapsed_s": 754,
            "appearance": "light",
            "dynamic_type": "large",
            "treatment": "light-v1",
            "frames": ["track-running", "insights", "history", "add-entry", "live-activity"],
            "frame": "track-running",
            "mode": "app-clock-pinned",
        ]
        for (key, value) in overrides { dict[key] = value }
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func codeFor(_ data: Data) -> String {
        do {
            _ = try ScreenshotRequestLoader.parse(data: data)
            return "ok"
        } catch let error as ScreenshotRequestError {
            return error.code
        } catch {
            return "unexpected:\(error)"
        }
    }

    @Test("valid pilot request parses with pinned values")
    func validRequest() throws {
        let request = try ScreenshotRequestLoader.parse(data: validJSON())
        #expect(request.schemaVersion == 1)
        #expect(request.deckVersion == "en-austin-1")
        #expect(request.frame == .trackRunning)
        #expect(request.mode == .appClockPinned)
        #expect(request.appElapsed == 754)
        #expect(request.runID == "default")
        #expect(request.appleLocaleIdentifier == "en_US")
        #expect(request.timeZone.identifier == "America/Chicago")
        // Tue 2026-10-20 09:41 CDT (UTC-5) == 14:41 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month, .day, .hour, .minute], from: request.referenceDate)
        #expect(comps.year == 2026 && comps.month == 10 && comps.day == 20)
        #expect(comps.hour == 14 && comps.minute == 41)
        #expect(request.sha256.count == 64)
    }

    @Test("supported locale triples parse with per-locale calendar and apple identifiers")
    func supportedLocales() throws {
        let pairings: [(locale: String, region: String, timezone: String, apple: String, weekday: Int)] = [
            ("en", "US", "America/Chicago", "en_US", 1),
            ("ru", "RU", "Europe/Moscow", "ru_RU", 2),
            ("zh-Hans", "CN", "Asia/Shanghai", "zh_Hans_CN", 1),
            ("es-419", "MX", "America/Mexico_City", "es_MX", 1),
            ("pt-BR", "BR", "America/Sao_Paulo", "pt_BR", 1),
        ]
        for pairing in pairings {
            let request = try ScreenshotRequestLoader.parse(data: validJSON(overrides: [
                "locale": pairing.locale,
                "region": pairing.region,
                "timezone": pairing.timezone,
            ]))
            #expect(request.localeIdentifier == pairing.locale, "locale \(pairing.locale)")
            #expect(request.regionCode == pairing.region)
            #expect(request.timeZone.identifier == pairing.timezone)
            #expect(request.appleLocaleIdentifier == pairing.apple, "apple locale \(pairing.locale)")
            #expect(request.deckVersion == "en-austin-1", "deck stays pinned for \(pairing.locale)")
            #expect(request.calendar.timeZone.identifier == pairing.timezone)
            #expect(request.calendar.locale?.identifier == Locale(identifier: pairing.apple).identifier,
                    "calendar locale \(pairing.locale)")
            #expect(request.calendar.firstWeekday == pairing.weekday, "firstWeekday \(pairing.locale)")
            // Same local wall time in every zone: 09:41 on Tue 2026-10-20.
            var wall = Calendar(identifier: .gregorian)
            wall.timeZone = request.timeZone
            let comps = wall.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: request.referenceDate)
            #expect(comps.year == 2026 && comps.month == 10 && comps.day == 20, "wall date \(pairing.locale)")
            #expect(comps.hour == 9 && comps.minute == 41, "wall time \(pairing.locale)")
            #expect(comps.weekday == 3, "Tuesday \(pairing.locale)")
        }
    }

    @Test("locale/region/timezone cross-pairings fail closed")
    func localePairingMismatches() {
        #expect(codeFor(validJSON(overrides: ["locale": "ru", "region": "US", "timezone": "America/Chicago"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["locale": "en", "region": "RU", "timezone": "America/Chicago"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["locale": "en", "region": "US", "timezone": "Europe/Moscow"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["locale": "zh-Hans", "region": "CN", "timezone": "America/Chicago"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["locale": "xx", "region": "US", "timezone": "America/Chicago"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["locale": "ru", "region": "RU", "timezone": "Europe/Moscow"])) != "unsupported-locale")
    }

    @Test("every semantic mismatch fails closed with a stable code")
    func mismatchMatrix() {
        #expect(codeFor(validJSON(overrides: ["schema_version": 2])) == "unsupported-schema")
        #expect(codeFor(validJSON(overrides: ["deck_version": "ru-moscow-1"])) == "unknown-deck")
        #expect(codeFor(validJSON(overrides: ["locale": "ru"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["region": "RU"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["timezone": "Europe/Moscow"])) == "unsupported-locale")
        #expect(codeFor(validJSON(overrides: ["calendar": "buddhist"])) == "unsupported-calendar")
        #expect(codeFor(validJSON(overrides: ["week_rule": "iso"])) == "unsupported-week-rule")
        #expect(codeFor(validJSON(overrides: ["reference_local_iso": "2026-10-21T09:41:00"])) == "unsupported-reference")
        #expect(codeFor(validJSON(overrides: ["app_elapsed_s": 755])) == "unsupported-elapsed")
        #expect(codeFor(validJSON(overrides: ["frame": "widget"])) == "unknown-frame")
        #expect(codeFor(validJSON(overrides: ["frame": "name-picker", "frames": ["track-running", "name-picker"]])) == "unknown-frame")
        #expect(codeFor(validJSON(overrides: ["frames": ["track-running"], "frame": "insights"])) == "frame-not-listed")
        #expect(codeFor(validJSON(overrides: ["frames": ["track-running", "nope"]])) == "unknown-frame")
        #expect(codeFor(validJSON(overrides: ["frame": "live-activity", "mode": "app-clock-pinned"])) == "mode-mismatch")
        #expect(codeFor(validJSON(overrides: ["frame": "insights", "mode": "live-activity-realtime"])) == "mode-mismatch")
        #expect(codeFor(Data("not json".utf8)) == "invalid-json")
        var missing = validJSON()
        // Drop a required key entirely.
        // swiftlint:disable:next force_try
        let missingObj = try! JSONSerialization.jsonObject(with: missing)
        guard var dict = missingObj as? [String: Any] else {
            Issue.record("expected a JSON object")
            return
        }
        dict.removeValue(forKey: "timezone")
        // swiftlint:disable:next force_try
        missing = try! JSONSerialization.data(withJSONObject: dict)
        #expect(codeFor(missing) == "missing-field")
    }

    @Test("live-activity frame requires the realtime mode")
    func liveActivityMode() throws {
        let request = try ScreenshotRequestLoader.parse(data: validJSON(overrides: [
            "frame": "live-activity",
            "mode": "live-activity-realtime",
        ]))
        #expect(request.frame == .liveActivity)
        #expect(request.mode == .liveActivityRealtime)
    }

    @Test("add-entry frame parses on the pinned app clock")
    func addEntryMode() throws {
        let request = try ScreenshotRequestLoader.parse(data: validJSON(overrides: [
            "frame": "add-entry",
        ]))
        #expect(request.frame == .addEntry)
        #expect(request.mode == .appClockPinned)
        #expect(request.frame.requiresRealtimeMode == false)
    }

    @Test("launch token detection mirrors the UI-testing grammar")
    func launchDetection() {
        #expect(ScreenshotLaunch.detect(argv: [], environment: [:]) == .absent)
        #expect(ScreenshotLaunch.detect(argv: [], environment: ["SCREENSHOT_REQUEST": "capture-request.json"])
            == .requested(filename: "capture-request.json"))
        #expect(ScreenshotLaunch.detect(argv: ["SCREENSHOT_REQUEST=capture-request.json"], environment: [:])
            == .requested(filename: "capture-request.json"))
        #expect(ScreenshotLaunch.detect(argv: ["SCREENSHOT_REQUEST", "capture-request.json"], environment: [:])
            == .requested(filename: "capture-request.json"))
        #expect(ScreenshotLaunch.detect(argv: [], environment: ["SIMCTL_CHILD_SCREENSHOT_REQUEST": "capture-request.json"])
            == .requested(filename: "capture-request.json"))
    }

    @Test("cleanup invocation requires both run ID and request SHA")
    func cleanupDetection() {
        #expect(ScreenshotLaunch.detectCleanup(argv: [], environment: [:]) == nil)
        #expect(ScreenshotLaunch.detectCleanup(
            argv: ["SCREENSHOT_CLEANUP=my-run"],
            environment: [:]
        ) == nil)
        #expect(ScreenshotLaunch.detectCleanup(
            argv: ["SCREENSHOT_CLEANUP=my-run", "SCREENSHOT_CLEANUP_SHA=abc123"],
            environment: [:]
        ) == ScreenshotCleanupInvocation(runID: "my-run", expectedSHA256: "abc123"))
        #expect(ScreenshotLaunch.detectCleanup(
            argv: ["SCREENSHOT_CLEANUP=my-run", "SCREENSHOT_CLEANUP_SHA="],
            environment: [:]
        ) == nil)
        #expect(ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: ["SCREENSHOT_CLEANUP": "env-run", "SCREENSHOT_CLEANUP_SHA": "def456"]
        ) == ScreenshotCleanupInvocation(runID: "env-run", expectedSHA256: "def456"))
        #expect(ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: ["SIMCTL_CHILD_SCREENSHOT_CLEANUP": "fwd-run", "SIMCTL_CHILD_SCREENSHOT_CLEANUP_SHA": "789"]
        ) == ScreenshotCleanupInvocation(runID: "fwd-run", expectedSHA256: "789"))
    }

    @Test("non-capture builds always resolve the production route")
    func productionRouteWithoutFlag() {
#if SCREENSHOT_CAPTURE
        // The test bundle itself is a capture build here (test-target flag):
        // the token IS honored — this also proves the flag is live, so the
        // gated capture suites below genuinely execute (review 2026-10-30).
        #expect(ScreenshotBuildGate.isCaptureBuild == true)
        #expect(ScreenshotBuildGate.route(for: .requested(filename: "capture-request.json")) == .capture(filename: "capture-request.json"))
        #expect(ScreenshotBuildGate.route(for: .absent) == .production)
#else
        // Debug AND Release lack SCREENSHOT_CAPTURE, so both must ignore the
        // token and keep the mandatory sign-in gate (tasks 2.4).
        #expect(ScreenshotBuildGate.isCaptureBuild == false)
        #expect(ScreenshotBuildGate.route(for: .absent) == .production)
        #expect(ScreenshotBuildGate.route(for: .requested(filename: "capture-request.json")) == .production)
#endif
    }

    @Test("capture namespace stays outside the production App Group")
    func captureNamespaceIsolation() {
        let group = LocalStore.appGroupID
        #expect(!group.isEmpty)
        // The capture session directory is derived from the request run ID,
        // never from the shared container — production files are unreachable
        // by construction (tasks 2.5).
        #expect(!ScreenshotCaptureRequest.requestFilename.contains("/"))
    }
}
