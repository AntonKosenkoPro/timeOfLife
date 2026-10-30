#if SCREENSHOT_CAPTURE
import Foundation

/// The awaited capture preparation pipeline (screenshot-capture design §2).
///
/// Ordered: fresh session directory → isolated store → stable-ID categories →
/// committed entries → running draft → read-back validation. Any unknown
/// input, `.invalid`/`.failure` mutation, missing link, wrong count, or
/// mismatched total is FATAL — never a silent fallback to an empty store,
/// production services, or another language. Gated: absent from shipping
/// builds (tasks 2.4).
@MainActor
struct ScreenshotPreparedContext {
    let request: ScreenshotCaptureRequest
    let sessionDirectory: URL
    let store: LocalStore
    let categoriesByID: [String: Category]
    let totals: CaptureExpectedTotals
    let draftStartedAt: Date
}

@MainActor
enum ScreenshotPreparation {
    /// Fictional capture account (review 2.3.9: never real-person data).
    static let fixtureUserID = "screenshot-pilot"

    /// The capture-only session directory (never the production App Group).
    static func sessionDirectory(runID: String) throws -> URL {
        let sanitized = runID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !sanitized.isEmpty, sanitized == runID else {
            throw ScreenshotRequestError(code: "invalid-run-id", detail: "run_id '\(runID)' has unsupported characters.")
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ScreenshotRequestError(code: "session-unavailable", detail: "No application-support directory.")
        }
        return base
            .appendingPathComponent("screenshot-capture", isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
    }

    /// Runs the full pipeline and validates the result. A fresh
    /// session-specific dataset on every run: an existing session directory
    /// is removed first, so restarts never accumulate records.
    static func prepare(request: ScreenshotCaptureRequest) async throws -> ScreenshotPreparedContext {
        let sessionDir = try sessionDirectory(runID: request.runID)
        if FileManager.default.fileExists(atPath: sessionDir.path) {
            try FileManager.default.removeItem(at: sessionDir)
        }
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let store: LocalStore
        do {
            store = try LocalStore(
                url: sessionDir.appendingPathComponent(LocalStore.databaseFileName(userID: fixtureUserID)),
                userID: fixtureUserID
            )
        } catch {
            throw ScreenshotRequestError(code: "store-open-failed", detail: "Isolated capture store failed to open: \(error).")
        }

        let stamp = request.referenceDate
        try await seedCategories(store: store, stamp: stamp, localeIdentifier: request.localeIdentifier)
        try await seedEntries(store: store, calendar: request.calendar, stamp: stamp, localeIdentifier: request.localeIdentifier)
        let draftStartedAt = request.referenceDate.addingTimeInterval(-request.appElapsed)
        do {
            try await store.saveTimerDraft(
                activityText: ScreenshotFixture.draftText(for: request.localeIdentifier),
                categoryIDs: ScreenshotFixture.draftCategoryIDs(for: request.localeIdentifier),
                startedAt: draftStartedAt,
                notes: ScreenshotFixture.draftNotes(for: request.localeIdentifier)
            )
        } catch {
            throw ScreenshotRequestError(code: "draft-failed", detail: "Running draft failed: \(error).")
        }

        return try await validate(request: request, store: store, sessionDirectory: sessionDir, draftStartedAt: draftStartedAt)
    }

    /// Single producer for categories: stable fixture IDs resolve
    /// relationships — no name-based race with gate seeding (which never
    /// runs in capture).
    private static func seedCategories(store: LocalStore, stamp: Date, localeIdentifier: String) async throws {
        let expected = ScreenshotFixture.categories(for: localeIdentifier, stamp: stamp)
        for category in expected {
            do {
                try await store.createCategory(category)
            } catch {
                throw ScreenshotRequestError(code: "category-seed-failed", detail: "Category \(category.id) failed: \(error).")
            }
        }
        let seeded = try await store.categories()
        guard seeded.count == expected.count else {
            throw ScreenshotRequestError(code: "category-seed-failed", detail: "Expected 8 fixture categories, found \(seeded.count).")
        }
    }

    /// Committed entries only: every `.invalid`/`.failure`/association error
    /// is fatal (design §2 — never a silent partial dataset).
    private static func seedEntries(store: LocalStore, calendar: Calendar, stamp: Date, localeIdentifier: String) async throws {
        for entry in ScreenshotFixture.buildEntries(calendar: calendar, stamp: stamp, localeIdentifier: localeIdentifier) {
            let mutation: LocalStore.EntryMutation
            do {
                mutation = try await store.createEntry(entry)
            } catch {
                throw ScreenshotRequestError(code: "entry-association-failed", detail: "Entry \(entry.id) failed: \(error).")
            }
            switch mutation {
            case .created:
                break
            case .invalid(let validation):
                throw ScreenshotRequestError(code: "entry-invalid", detail: "Entry \(entry.id) invalid: \(validation).")
            case .restorableDeletion(let existing):
                throw ScreenshotRequestError(code: "entry-failed", detail: "Entry \(entry.id) collided with buffered deletion \(existing.id).")
            case .failure:
                throw ScreenshotRequestError(code: "entry-failed", detail: "Entry \(entry.id) failed to persist.")
            }
        }
    }

    /// Reads back and validates: exact counts, resolvable links, computed
    /// totals, and draft exclusion from committed data.
    static func validate(
        request: ScreenshotCaptureRequest,
        store: LocalStore,
        sessionDirectory: URL,
        draftStartedAt: Date
    ) async throws -> ScreenshotPreparedContext {
        let entries = try await store.entries()
        guard entries.count == ScreenshotFixture.entryCount else {
            throw ScreenshotRequestError(code: "count-mismatch", detail: "Expected 55 committed entries, found \(entries.count).")
        }
        let categories = try await store.categories()
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for entry in entries {
            for id in entry.categoryIDs {
                guard categoriesByID[id] != nil else {
                    throw ScreenshotRequestError(code: "link-mismatch", detail: "Entry \(entry.id) links unknown category \(id).")
                }
            }
            guard entry.endedAt != nil else {
                throw ScreenshotRequestError(code: "draft-leak", detail: "In-progress entry \(entry.id) in committed data.")
            }
        }
        let calendar = request.calendar
        let dayStart = calendar.startOfDay(for: request.referenceDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let week = calendar.dateInterval(of: .weekOfYear, for: request.referenceDate)
        else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Reference intervals unresolvable.")
        }
        let totals = CaptureExpectedTotals.compute(
            entries: entries,
            categoriesByID: categoriesByID,
            today: DateInterval(start: dayStart, end: dayEnd),
            week: week
        )
        guard totals.allSeconds > 0, totals.todaySeconds > 0, totals.weekSeconds > 0 else {
            throw ScreenshotRequestError(code: "totals-invalid", detail: "Degenerate totals (all=\(totals.allSeconds) today=\(totals.todaySeconds) week=\(totals.weekSeconds)).")
        }
        guard try await store.timerDraft() != nil else {
            throw ScreenshotRequestError(code: "draft-missing", detail: "Running draft absent after preparation.")
        }
        return ScreenshotPreparedContext(
            request: request,
            sessionDirectory: sessionDirectory,
            store: store,
            categoriesByID: categoriesByID,
            totals: totals,
            draftStartedAt: draftStartedAt
        )
    }
}
#endif
