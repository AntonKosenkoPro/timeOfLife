#if DEBUG || SCREENSHOT_CAPTURE
import Foundation

/// Expected committed totals for a capture run, computed from the fixture and
/// validated against store reads before `ready` (design §2: fatal on
/// mismatched totals). Category rows use full-credit attribution (every
/// attached category gets the full duration — the Insights lens rule); text
/// rows group by exact text.
struct CaptureExpectedTotals: Codable, Equatable {
    var allSeconds: Int
    var todaySeconds: Int
    var weekSeconds: Int
    /// Stable category-ID → full-credit seconds.
    var categorySeconds: [String: Int]
    /// Exact entry text → summed seconds.
    var textSeconds: [String: Int]

    enum CodingKeys: String, CodingKey {
        case allSeconds = "all_seconds"
        case todaySeconds = "today_seconds"
        case weekSeconds = "week_seconds"
        case categorySeconds = "category_seconds"
        case textSeconds = "text_seconds"
    }

    /// Pure computation over committed entries (`endedAt != nil`; NULL
    /// durations count zero — History/Insights D8 precedent). The running
    /// draft never appears here (it is not a committed entry).
    static func compute(
        entries: [TimeEntry],
        categoriesByID: [String: Category],
        today: DateInterval,
        week: DateInterval
    ) -> CaptureExpectedTotals {
        let committed = entries.filter { $0.endedAt != nil }
        func seconds(_ entry: TimeEntry) -> Int { entry.durationSeconds ?? 0 }
        var categories: [String: Int] = [:]
        var texts: [String: Int] = [:]
        for entry in committed {
            let duration = seconds(entry)
            texts[entry.activityText, default: 0] += duration
            for id in entry.categoryIDs {
                guard categoriesByID[id] != nil else { continue }
                categories[id, default: 0] += duration
            }
        }
        func sum(_ entries: [TimeEntry]) -> Int { entries.reduce(0) { $0 + seconds($1) } }
        return CaptureExpectedTotals(
            allSeconds: sum(committed),
            todaySeconds: sum(committed.filter { today.contains($0.startedAt) }),
            weekSeconds: sum(committed.filter { week.contains($0.startedAt) }),
            categorySeconds: categories,
            textSeconds: texts
        )
    }
}

/// Build provenance for a capture state file.
struct CaptureStateBuild: Codable, Equatable {
    var configuration: String
    var bundleID: String
    var commit: String?

    enum CodingKeys: String, CodingKey {
        case configuration
        case bundleID = "bundle_id"
        case commit
    }
}

/// Logical clock domains for a capture state file.
struct CaptureStateClocks: Codable, Equatable {
    /// Pinned wall reference in the declared zone (e.g. 2026-10-20T09:41:00).
    var referenceLocalISO: String
    /// Absolute instant of the logical reference (ISO-8601, Chicago offset).
    var referenceDate: String
    var timeZone: String

    enum CodingKeys: String, CodingKey {
        case referenceLocalISO = "reference_local_iso"
        case referenceDate = "reference_date"
        case timeZone = "timezone"
    }
}

/// Committed-entry counts (canonical contract: `counts.entries`).
struct CaptureStateCounts: Codable, Equatable {
    var entries: Int
}

/// Real Live Activity provenance (realtime mode only): the actual request
/// acknowledgement and wall-clock anchor — never the historical reference.
/// Key names are the canonical runner contract (`started_at`,
/// `request_acknowledged_at`).
struct CaptureStateLiveActivity: Codable, Equatable {
    var activityID: String
    var startedAt: String
    var requestAcknowledgedAt: String

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case startedAt = "started_at"
        case requestAcknowledgedAt = "request_acknowledged_at"
    }
}

struct CaptureStateFailure: Codable, Equatable {
    var code: String
    var detail: String
}

/// Machine-readable capture state, written atomically to
/// `Documents/capture-state.json` (spec: evidence requirement). `ready` means
/// the requested NATIVE view is loaded and settled — never just "seed
/// finished". Binaries stay outside git; this text file is committable.
struct CaptureState: Codable, Equatable {
    /// preparing | ready | invalid | failure
    var status: String
    var requestSHA256: String?
    var deckVersion: String?
    var frame: String?
    var mode: String?
    var runID: String?
    var counts: CaptureStateCounts?
    var expectedTotals: CaptureExpectedTotals?
    var build: CaptureStateBuild?
    var clocks: CaptureStateClocks?
    var liveActivity: CaptureStateLiveActivity?
    var error: CaptureStateFailure?

    enum CodingKeys: String, CodingKey {
        case status
        case requestSHA256 = "request_sha256"
        case deckVersion = "deck_version"
        case frame, mode
        case runID = "run_id"
        case counts
        case expectedTotals = "expected_totals"
        case build, clocks
        case liveActivity = "live_activity"
        case error
    }
}

/// Cleanup acknowledgement (`Documents/capture-cleanup.json`): the runner's
/// proof that a capture run's session was reset. Statuses: `cleaned` (ended
/// capture-owned activities, if any, and removed the session directory),
/// `mismatch` (run ID/SHA did not match the last capture state — nothing
/// touched), `failure` (no verifiable prior state or environment error).
/// Key names follow the same canonical contract as `CaptureState`.
struct CaptureCleanupState: Codable, Equatable {
    var status: String
    var runID: String?
    var requestSHA256: String?
    var endedActivityIDs: [String]
    var removedSession: Bool
    var error: CaptureStateFailure?

    enum CodingKeys: String, CodingKey {
        case status
        case runID = "run_id"
        case requestSHA256 = "request_sha256"
        case endedActivityIDs = "ended_activity_ids"
        case removedSession = "removed_session"
        case error
    }
}

enum CaptureAtomicFile {
    /// Atomic write (temp file + rename in the same directory): readers never
    /// observe a half-written file.
    static func write(_ data: Data, filename: String, to directory: URL) throws {
        let final = directory.appendingPathComponent(filename)
        let tmp = directory.appendingPathComponent("\(filename).tmp.\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: final.path) {
            try FileManager.default.removeItem(at: final)
        }
        try FileManager.default.moveItem(at: tmp, to: final)
    }
}

enum CaptureStateWriter {
    static let filename = "capture-state.json"

    static func write(_ state: CaptureState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try CaptureAtomicFile.write(encoder.encode(state), filename: filename, to: directory)
    }

    static func read(from directory: URL) throws -> CaptureState {
        let data = try Data(contentsOf: directory.appendingPathComponent(filename))
        return try JSONDecoder().decode(CaptureState.self, from: data)
    }
}

enum CaptureCleanupWriter {
    static let filename = "capture-cleanup.json"

    static func write(_ state: CaptureCleanupState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try CaptureAtomicFile.write(encoder.encode(state), filename: filename, to: directory)
    }

    static func read(from directory: URL) throws -> CaptureCleanupState {
        let data = try Data(contentsOf: directory.appendingPathComponent(filename))
        return try JSONDecoder().decode(CaptureCleanupState.self, from: data)
    }
}
#endif
