import Testing
import Foundation
@testable import TimeOfLife

/// Expected-totals computation + atomic state writer tests (tasks 3.2/4.4
/// support; pure and ungated so they run in Debug).
@Suite("Capture state")
struct CaptureStateTests {

    private func category(id: String) -> Category {
        Category(id: id, name: id, icon: "tag")
    }

    private func entry(id: String, text: String, start: Date, minutes: Int, categories: [String] = []) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
            durationSeconds: minutes * 60,
            categoryIDs: categories
        )
    }

    @Test("totals attribute full credit per category and exact text")
    func totalsComputation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let day = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!)
        let today = DateInterval(start: day, duration: 86400)
        let weekStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18))!
        let week = DateInterval(start: weekStart, duration: 7 * 86400)
        let cats = ["c1": category(id: "c1"), "c2": category(id: "c2")]

        let entries = [
            entry(id: "a", text: "Gym", start: day.addingTimeInterval(3600), minutes: 60, categories: ["c1", "c2"]),
            entry(id: "b", text: "gym", start: day.addingTimeInterval(7200), minutes: 30, categories: ["c1"]),
            // In-progress entries never contribute (draft-exclusion rule).
            TimeEntry(id: "c", activityText: "Run", startedAt: day.addingTimeInterval(10800), endedAt: nil),
            entry(id: "d", text: "Old", start: weekStart.addingTimeInterval(-100), minutes: 10),
        ]

        let totals = CaptureExpectedTotals.compute(entries: entries, categoriesByID: cats, today: today, week: week)
        #expect(totals.allSeconds == 3600 + 1800 + 600)
        #expect(totals.todaySeconds == 3600 + 1800)
        #expect(totals.weekSeconds == 3600 + 1800)
        // Full credit: c1 gets both entries, c2 only the first.
        #expect(totals.categorySeconds == ["c1": 5400, "c2": 3600])
        // Exact-text identity: "Gym" and "gym" stay distinct.
        #expect(totals.textSeconds["Gym"] == 3600)
        #expect(totals.textSeconds["gym"] == 1800)
        #expect(totals.textSeconds["Run"] == nil)
    }

    @Test("state round-trips through the atomic writer")
    func stateWriterRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = CaptureState(
            status: "ready",
            requestSHA256: String(repeating: "a", count: 64),
            deckVersion: "en-austin-1",
            frame: "track-running",
            mode: "app-clock-pinned",
            runID: "default",
            counts: CaptureStateCounts(entries: 55),
            expectedTotals: CaptureExpectedTotals(
                allSeconds: 1, todaySeconds: 2, weekSeconds: 3,
                categorySeconds: ["c": 4], textSeconds: ["T": 5]
            ),
            build: CaptureStateBuild(configuration: "Screenshot", bundleID: "x", commit: nil),
            clocks: nil,
            liveActivity: nil,
            error: nil
        )
        try CaptureStateWriter.write(state, to: dir)
        #expect(try CaptureStateWriter.read(from: dir) == state)
        // Readers observe one complete file, never a half-written one.
        let raw = try Data(contentsOf: dir.appendingPathComponent(CaptureStateWriter.filename))
        #expect((try? JSONDecoder().decode(CaptureState.self, from: raw)) == state)
    }

    @Test("cleanup acknowledgement round-trips through its writer")
    func cleanupWriterRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ack = CaptureCleanupState(
            status: "cleaned",
            runID: "my-run",
            requestSHA256: String(repeating: "b", count: 64),
            endedActivityIDs: ["act-1"],
            removedSession: true,
            error: nil
        )
        try CaptureCleanupWriter.write(ack, to: dir)
        #expect(try CaptureCleanupWriter.read(from: dir) == ack)
        let mismatch = CaptureCleanupState(
            status: "mismatch",
            runID: "my-run",
            requestSHA256: String(repeating: "b", count: 64),
            endedActivityIDs: [],
            removedSession: false,
            error: CaptureStateFailure(code: "cleanup-mismatch", detail: "nope")
        )
        try CaptureCleanupWriter.write(mismatch, to: dir)
        #expect(try CaptureCleanupWriter.read(from: dir) == mismatch)
    }
}
