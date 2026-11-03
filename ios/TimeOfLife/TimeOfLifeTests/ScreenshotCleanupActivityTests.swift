#if SCREENSHOT_CAPTURE
@preconcurrency import ActivityKit
import Foundation
import Testing
@testable import TimeOfLife

/// Regression tests for the cleanup live-miss: `endFixtureActivities` ended
/// older (already `.active`) strays but missed the currently-live activity —
/// a just-requested anchor reads as `.pending` in a fresh cleanup process
/// (iOS 26+: request accepted, not yet presented), and the text-only sweep
/// never targets the known `live_activity.activity_id` from
/// capture-state.json. Runner retries stayed `partial` (the real id never
/// landed in `ended_activity_ids`) and a reboot never clears the persisted
/// banner — only an explicit end does.
@MainActor
@Suite("Screenshot cleanup activities")
struct ScreenshotCleanupActivityTests {
    private func snapshot(id: String, text: String, state: ActivityState) -> ScreenshotApp.FixtureActivitySnapshot {
        ScreenshotApp.FixtureActivitySnapshot(id: id, entryText: text, state: state)
    }

    @Test("active fixture-text stray is endable")
    func activeStrayEndable() {
        let snaps = [snapshot(id: "stray-1", text: ScreenshotFixture.draftText, state: .active)]
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: nil).map(\.id) == ["stray-1"])
    }

    @Test("foreign activities are never endable")
    func foreignExcluded() {
        let snaps = [snapshot(id: "user-1", text: "Gym", state: .active)]
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: nil).isEmpty)
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: "other-id").isEmpty)
    }

    @Test("pending live anchor is endable by id")
    func pendingLiveAnchorEndable() {
        if #available(iOS 26, *) {
            let snaps = [snapshot(id: "live-123", text: ScreenshotFixture.draftText, state: .pending)]
            #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: "live-123").map(\.id) == ["live-123"])
        } else {
            Issue.record("requires the iOS 26 runtime")
        }
    }

    @Test("live anchor is endable even when its text drifted")
    func liveAnchorEndableDespiteTextDrift() {
        let snaps = [snapshot(id: "live-123", text: "Renamed draft", state: .active)]
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: "live-123").map(\.id) == ["live-123"])
    }

    @Test("stale fixture banner is endable")
    func staleFixtureEndable() {
        let snaps = [snapshot(id: "stray-2", text: ScreenshotFixture.draftText, state: .stale)]
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: nil).map(\.id) == ["stray-2"])
    }

    @Test("ended and dismissed activities are already gone")
    func endedDismissedExcluded() {
        let snaps = [
            snapshot(id: "e1", text: ScreenshotFixture.draftText, state: .ended),
            snapshot(id: "e2", text: ScreenshotFixture.draftText, state: .dismissed),
        ]
        #expect(ScreenshotApp.endableFixtureSnapshots(snaps, expectedActivityID: nil).isEmpty)
    }

    private func temporaryDocuments() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("cleanup threads the known live anchor into the ending pass")
    func cleanupThreadsLiveAnchor() async throws {
        let documents = try temporaryDocuments()
        let runID = "test-cleanup-anchor"
        let sha = String(repeating: "d", count: 64)
        try CaptureStateWriter.write(CaptureState(
            status: "ready",
            requestSHA256: sha,
            deckVersion: ScreenshotFixture.deckVersion,
            frame: ScreenshotFrame.trackRunning.rawValue,
            mode: ScreenshotMode.liveActivityRealtime.rawValue,
            runID: runID,
            counts: CaptureStateCounts(entries: ScreenshotFixture.entryCount),
            expectedTotals: nil,
            build: nil,
            clocks: nil,
            liveActivity: CaptureStateLiveActivity(
                activityID: "live-anchor-1",
                startedAt: "2026-10-20T09:41:00",
                requestAcknowledgedAt: "2026-10-20T09:41:01"
            ),
            error: nil
        ), to: documents)
        // The test host has no live activities, so the ack records none
        // ended — but the verified anchor must flow through without failure
        // (a zero poll timeout keeps the suite fast; the device path polls
        // for the anchor to hydrate).
        let ack = await ScreenshotCleanup.perform(
            documents: documents,
            invocation: ScreenshotCleanupInvocation(runID: runID, expectedSHA256: sha),
            activityPollTimeout: 0
        )
        #expect(ack.status == "cleaned")
        #expect(ack.endedActivityIDs.isEmpty)
        #expect(ack.error == nil)
        #expect(try CaptureCleanupWriter.read(from: documents) == ack)
    }
}
#endif
