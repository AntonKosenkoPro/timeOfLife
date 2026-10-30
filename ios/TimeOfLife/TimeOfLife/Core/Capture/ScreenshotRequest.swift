#if DEBUG || SCREENSHOT_CAPTURE
import CryptoKit
import Foundation

/// The seven approved story frames, in capture order (screenshot-capture
/// spec). Raw values are the exact request strings.
enum ScreenshotFrame: String, Codable, CaseIterable {
    case trackRunning = "track-running"
    case insights
    case history
    case addEntry = "add-entry"
    case laLock = "la-lock"
    case laCompact = "la-compact"
    case laExpanded = "la-expanded"
    /// Legacy single live-activity frame (pre-7-frame story): still accepted
    /// so prior 5-frame requests validate, but the pilot uses the three la-*
    /// frames above.
    case liveActivity = "live-activity"

    /// Only the Live Activity frames use the real system timer; the first
    /// four pin the app-owned clock (design §3 vs §4).
    var requiresRealtimeMode: Bool {
        self == .liveActivity || self == .laLock || self == .laCompact || self == .laExpanded
    }
}

/// Capture clock domains (design §3 vs §4).
enum ScreenshotMode: String, Codable {
    case appClockPinned = "app-clock-pinned"
    case liveActivityRealtime = "live-activity-realtime"
}

/// A validated capture request: every semantic locale/state field checked,
/// cosmetic fields (appearance, dynamic type, keyboard, status bar,
/// treatment) deliberately not decoded — the runner owns them.
struct ScreenshotCaptureRequest: Equatable {
    let schemaVersion: Int
    let deckVersion: String
    let localeIdentifier: String
    let regionCode: String
    let timeZone: TimeZone
    let calendar: Calendar
    let weekRule: String
    let referenceDate: Date
    let appElapsed: TimeInterval
    let frame: ScreenshotFrame
    let mode: ScreenshotMode
    let runID: String
    /// Hex SHA-256 over the EXACT request file bytes (runner pins evidence).
    let sha256: String
    /// App-bundle locale identifier derived from locale+region (e.g. en_US).
    let appleLocaleIdentifier: String

    /// Pinned pilot inputs (proposal/design; task 1.4 manifest defaults).
    static let pinnedSchemaVersion = 1
    static let enAustinDeckVersion = "en-austin-1"
    static let pinnedLocale = "en"
    static let pinnedRegion = "US"
    static let pinnedTimeZoneID = "America/Chicago"
    static let pinnedAppleLocaleID = "en_US"
    static let pinnedCalendarID = "gregorian"
    static let pinnedWeekRule = "locale-native"
    static let pinnedReferenceISO = "2026-10-20T09:41:00"
    static let pinnedElapsed: TimeInterval = 754
    static let requestFilename = "capture-request.json"

    /// Supported locale/region/timezone pins (design §3) with the
    /// app-bundle locale identifier (language+region) used for
    /// `AppleLocale` and the calendar locale. The deck version stays
    /// `en-austin-1` across decks: the locale triple selects the deck.
    static let supportedLocalePairings: [String: (region: String, timeZoneID: String, appleLocaleID: String)] = [
        "en": ("US", "America/Chicago", "en_US"),
        "ru": ("RU", "Europe/Moscow", "ru_RU"),
        "zh-Hans": ("CN", "Asia/Shanghai", "zh_Hans_CN"),
        "es-419": ("MX", "America/Mexico_City", "es_MX"),
        "pt-BR": ("BR", "America/Sao_Paulo", "pt_BR"),
    ]

    static func appleLocaleIdentifier(for localeIdentifier: String) -> String? {
        supportedLocalePairings[localeIdentifier]?.appleLocaleID
    }
}

/// Fail-closed request validation (every mismatch is `.invalid`, never a
/// silent default substitution).
struct ScreenshotRequestError: Error, Equatable {
    /// Stable machine code for the state file (e.g. "unknown-deck").
    let code: String
    let detail: String
}

/// Launch-token detection: the app reads ONLY `Documents/capture-request.json`
/// when this token is present — never an arbitrary argv path.
enum ScreenshotLaunchDetection: Equatable {
    case absent
    case requested(filename: String)
}

/// A cleanup invocation: reset the named capture run after its frames are
/// exported. The runner reads both values from the last `capture-state.json`;
/// the app cross-checks them against that same file before touching
/// anything (fail closed — never a blind/global clear).
struct ScreenshotCleanupInvocation: Equatable {
    let runID: String
    let expectedSHA256: String
}

enum ScreenshotLaunch {
    static let token = "SCREENSHOT_REQUEST"
    static let forwardedToken = "SIMCTL_CHILD_SCREENSHOT_REQUEST"
    static let cleanupToken = "SCREENSHOT_CLEANUP"
    static let forwardedCleanupToken = "SIMCTL_CHILD_SCREENSHOT_CLEANUP"
    static let cleanupSHAToken = "SCREENSHOT_CLEANUP_SHA"
    static let forwardedCleanupSHAToken = "SIMCTL_CHILD_SCREENSHOT_CLEANUP_SHA"

    /// Mirrors `TimeOfLifeApp.uiTestingScreen` parsing (env first, then argv;
    /// both the plain and `SIMCTL_CHILD_`-forwarded forms).
    static func detect(argv: [String], environment: [String: String]) -> ScreenshotLaunchDetection {
        for key in [token, forwardedToken] {
            if let value = environment[key], !value.isEmpty {
                return .requested(filename: value)
            }
        }
        for (index, arg) in argv.enumerated() {
            for key in [token, forwardedToken] {
                if arg == key {
                    let next = index + 1
                    guard next < argv.count, !argv[next].isEmpty else { continue }
                    return .requested(filename: argv[next])
                }
                let prefix = key + "="
                if arg.hasPrefix(prefix) {
                    let value = String(arg.dropFirst(prefix.count))
                    if !value.isEmpty {
                        return .requested(filename: value)
                    }
                }
            }
        }
        return .absent
    }

    /// Cleanup invocation parsing (same grammar as capture detection). Both
    /// values are required: a run ID without its request SHA never cleans
    /// (fail closed — the SHA proves which run the runner means).
    static func detectCleanup(argv: [String], environment: [String: String]) -> ScreenshotCleanupInvocation? {
        guard let runID = value(for: [cleanupToken, forwardedCleanupToken], argv: argv, environment: environment),
              let sha = value(for: [cleanupSHAToken, forwardedCleanupSHAToken], argv: argv, environment: environment)
        else {
            return nil
        }
        return ScreenshotCleanupInvocation(runID: runID, expectedSHA256: sha)
    }

    private static func value(for keys: [String], argv: [String], environment: [String: String]) -> String? {
        for key in keys {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }
        for (index, arg) in argv.enumerated() {
            for key in keys {
                if arg == key {
                    let next = index + 1
                    guard next < argv.count, !argv[next].isEmpty else { continue }
                    return argv[next]
                }
                let prefix = key + "="
                if arg.hasPrefix(prefix) {
                    let value = String(arg.dropFirst(prefix.count))
                    if !value.isEmpty {
                        return value
                    }
                }
            }
        }
        return nil
    }
}

/// Whether this build honors capture requests. Only the Screenshot
/// configuration defines `SCREENSHOT_CAPTURE`, so ordinary Debug/Release
/// (and their archives) always resolve `.production` here — verified by
/// `ScreenshotGateTests` (tasks 2.4).
enum ScreenshotBuildGate {
    static var isCaptureBuild: Bool {
        #if SCREENSHOT_CAPTURE
        return true
        #else
        return false
        #endif
    }

    enum Route: Equatable {
        case production
        case capture(filename: String)
    }

    static func route(for detection: ScreenshotLaunchDetection) -> Route {
        guard isCaptureBuild, case let .requested(filename) = detection else {
            return .production
        }
        return .capture(filename: filename)
    }
}

enum ScreenshotRequestLoader {
    /// Validates exact request file bytes. Unknown extra keys are ignored;
    /// every missing/invalid REQUIRED semantic field throws fail-closed.
    static func parse(data: Data) throws -> ScreenshotCaptureRequest {
        let sha = sha256Hex(data)
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any]
        else {
            throw ScreenshotRequestError(code: "invalid-json", detail: "Request is not a JSON object.")
        }
        let schema = try schemaVersion(dict)
        let deck = try deckVersion(dict)
        let locale = try localeTriple(dict)
        try requireField(dict, key: "calendar", equalTo: ScreenshotCaptureRequest.pinnedCalendarID, code: "unsupported-calendar", detail: "Only the gregorian calendar is accepted.")
        try requireField(dict, key: "week_rule", equalTo: ScreenshotCaptureRequest.pinnedWeekRule, code: "unsupported-week-rule", detail: "Only locale-native week rules are accepted.")
        let referenceDate = try referenceDate(dict, timeZone: locale.timeZone)
        let elapsed = try elapsed(dict)
        let frame = try frameAndMode(dict)
        let runID = (dict["run_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = locale.timeZone
        calendar.locale = Locale(identifier: locale.appleLocaleID)
        return ScreenshotCaptureRequest(
            schemaVersion: schema,
            deckVersion: deck,
            localeIdentifier: locale.id,
            regionCode: locale.region,
            timeZone: locale.timeZone,
            calendar: calendar,
            weekRule: ScreenshotCaptureRequest.pinnedWeekRule,
            referenceDate: referenceDate,
            appElapsed: elapsed,
            frame: frame.frame,
            mode: frame.mode,
            runID: runID,
            sha256: sha,
            appleLocaleIdentifier: locale.appleLocaleID
        )
    }

    private static func object(_ dict: [String: Any], key: String) throws -> String {
        guard let value = dict[key] as? String, !value.isEmpty else {
            throw ScreenshotRequestError(code: "missing-field", detail: "Missing or empty required field '\(key)'.")
        }
        return value
    }

    private static func schemaVersion(_ dict: [String: Any]) throws -> Int {
        guard let schema = dict["schema_version"] as? Int,
              schema == ScreenshotCaptureRequest.pinnedSchemaVersion
        else {
            throw ScreenshotRequestError(code: "unsupported-schema", detail: "schema_version must be 1.")
        }
        return schema
    }

    private static func deckVersion(_ dict: [String: Any]) throws -> String {
        let deck = try object(dict, key: "deck_version")
        guard deck == ScreenshotCaptureRequest.enAustinDeckVersion else {
            throw ScreenshotRequestError(code: "unknown-deck", detail: "Unknown deck_version '\(deck)'.")
        }
        return deck
    }

    private struct LocaleTriple {
        let id: String
        let region: String
        let timeZone: TimeZone
        let appleLocaleID: String
    }

    private static func localeTriple(_ dict: [String: Any]) throws -> LocaleTriple {
        let id = try object(dict, key: "locale")
        let region = try object(dict, key: "region")
        let timeZoneID = try object(dict, key: "timezone")
        guard let pairing = ScreenshotCaptureRequest.supportedLocalePairings[id],
              pairing.region == region,
              pairing.timeZoneID == timeZoneID,
              let timeZone = TimeZone(identifier: timeZoneID)
        else {
            throw ScreenshotRequestError(code: "unsupported-locale", detail: "Unsupported locale triple \(id)/\(region)/\(timeZoneID). Supported: en/US/America-Chicago, ru/RU/Europe-Moscow, zh-Hans/CN/Asia-Shanghai, es-419/MX/America-Mexico_City, pt-BR/BR/America-Sao_Paulo.")
        }
        return LocaleTriple(id: id, region: region, timeZone: timeZone, appleLocaleID: pairing.appleLocaleID)
    }

    private static func requireField(_ dict: [String: Any], key: String, equalTo: String, code: String, detail: String) throws {
        guard (try object(dict, key: key)) == equalTo else {
            throw ScreenshotRequestError(code: code, detail: detail)
        }
    }

    private static func referenceDate(_ dict: [String: Any], timeZone: TimeZone) throws -> Date {
        let iso = try object(dict, key: "reference_local_iso")
        guard iso == ScreenshotCaptureRequest.pinnedReferenceISO,
              let date = referenceDate(iso: iso, timeZone: timeZone)
        else {
            throw ScreenshotRequestError(code: "unsupported-reference", detail: "reference_local_iso must be the pinned pilot reference.")
        }
        return date
    }

    private static func elapsed(_ dict: [String: Any]) throws -> TimeInterval {
        guard let seconds = dict["app_elapsed_s"] as? Int,
              TimeInterval(seconds) == ScreenshotCaptureRequest.pinnedElapsed
        else {
            throw ScreenshotRequestError(code: "unsupported-elapsed", detail: "app_elapsed_s must be the pinned pilot elapsed (754).")
        }
        return TimeInterval(seconds)
    }

    private static func frameAndMode(_ dict: [String: Any]) throws -> (frame: ScreenshotFrame, mode: ScreenshotMode) {
        let frameRaw = try object(dict, key: "frame")
        guard let frame = ScreenshotFrame(rawValue: frameRaw) else {
            throw ScreenshotRequestError(code: "unknown-frame", detail: "Unknown frame '\(frameRaw)'.")
        }
        guard let frames = dict["frames"] as? [String], !frames.isEmpty else {
            throw ScreenshotRequestError(code: "missing-field", detail: "Missing or empty required field 'frames'.")
        }
        for listed in frames {
            guard ScreenshotFrame(rawValue: listed) != nil else {
                throw ScreenshotRequestError(code: "unknown-frame", detail: "Unknown listed frame '\(listed)'.")
            }
        }
        guard frames.contains(frameRaw) else {
            throw ScreenshotRequestError(code: "frame-not-listed", detail: "Requested frame '\(frameRaw)' is not in frames.")
        }
        let modeRaw = try object(dict, key: "mode")
        guard let mode = ScreenshotMode(rawValue: modeRaw) else {
            throw ScreenshotRequestError(code: "unknown-mode", detail: "Unknown mode '\(modeRaw)'.")
        }
        let matches = (mode == .liveActivityRealtime) == frame.requiresRealtimeMode
        guard matches else {
            throw ScreenshotRequestError(code: "mode-mismatch", detail: "Mode '\(modeRaw)' does not match frame '\(frameRaw)'.")
        }
        return (frame, mode)
    }

    /// Parses a `yyyy-MM-dd'T'HH:mm:ss` wall time in the declared time zone.
    static func referenceDate(iso: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: iso)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
