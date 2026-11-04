#if SCREENSHOT_CAPTURE
import Foundation
import Testing
@testable import TimeOfLife

/// Negative coverage for tasks 3.1–3.4 that the session suite does not yet
/// pin: isolation-guard injection, deterministic presentation resets,
/// fixture-mutation rejection, and bounded mount failure. Real stores,
/// real view models, no mocks.
@MainActor
@Suite("Screenshot session resets")
struct ScreenshotSessionResetTests {
    private let nonce = "abcdef0123456789abcdef0123456789"
    // Distinct from the protocol suite's run ID: prepare() deletes and
    // recreates one shared ApplicationSupport session directory per run ID,
    // so sharing it would let the two suites collide on disk.
    private let runID = "iphone69-en-r2"

    private func payload(frame: String = "track-running", locale: String = "en", region: String = "US", timezone: String = "America/Chicago") throws -> Data {
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
            "frames": ["track-running", "insights", "history", "add-entry", "la-lock", "la-compact", "la-expanded"],
            "frame": frame,
            "mode": "app-clock-pinned",
            "run_id": runID,
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func envelope(frame: String = "track-running", seq: Int = 0) throws -> Data {
        try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: payload(frame: frame),
            runID: runID,
            nonce: nonce,
            domain: .pinned,
            seq: seq
        )
    }

    private func temporaryDocuments() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fastController(documents: URL) -> ScreenshotSessionController {
        let controller = ScreenshotSessionController(documents: documents)
        controller.settleGraceProvider = { _ in 0.01 }
        controller.autoMountInTests = true
        return controller
    }

    private func publish(_ documents: URL, frame: String, seq: Int) throws {
        let queue = try ScreenshotSessionPaths.queueURL(documents: documents, nonce: nonce)
        try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
        let framePayload: [String: Any] = [
            "schema_version": 1,
            "deck_version": "en-austin-1",
            "locale": "en",
            "region": "US",
            "timezone": "America/Chicago",
            "calendar": "gregorian",
            "week_rule": "locale-native",
            "reference_local_iso": "2026-10-20T09:41:00",
            "app_elapsed_s": 754,
            "frames": ["track-running", "insights", "history", "add-entry", "la-lock", "la-compact", "la-expanded"],
            "frame": frame,
            "mode": "app-clock-pinned",
            "run_id": runID,
        ]
        let raw = try JSONSerialization.data(withJSONObject: framePayload)
        try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: raw,
            runID: runID,
            nonce: nonce,
            domain: .pinned,
            seq: seq
        ).write(to: queue)
    }

    // MARK: - 3.1 isolation guards

    @Test("envelope helper honors the frame parameter")
    func envelopeHelperHonorsFrame() throws {
        let env = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "history", seq: 2))
        #expect(env.frame == .history)
        #expect(env.seq == 2)
    }

    @Test("activated sync is rejected before any capture work")
    func syncActiveRejected() async throws {
        let request = try ScreenshotRequestLoader.parse(data: payload())
        let prepared = try await ScreenshotPreparation.prepare(request: request)
        let container = ScreenshotApp.makeContainer(
            store: prepared.store,
            sessionDirectory: prepared.sessionDirectory,
            liveActivities: NoopLiveActivityController()
        )
        try ScreenshotSessionController.verifyIsolation(container: container)
        container.syncController.activate(userID: ScreenshotPreparation.fixtureUserID)
        #expect(container.syncController.status != .inactive)
        #expect(throws: ScreenshotRequestError.self) {
            try ScreenshotSessionController.verifyIsolation(container: container)
        }
        container.syncController.deactivate()
    }

    @Test("seed runs once: store identity and session dir survive commands")
    func seedOnceIdentity() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        let first = controller.testStore()
        let dir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        _ = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        #expect(controller.testStore() === first)
        #expect(controller.transcript.count == 2)
        #expect(controller.timings.samples.filter { $0.phase == "seed" }.count == 1)
    }

    @Test("request locale is applied before the first mount")
    func localeOrderAtMount() async throws {
        // Process-global hygiene (ScreenshotCaptureTests pattern): start()
        // applies AppleLanguages/AppleLocale/TZ plus the ScreenshotLocale
        // override for the request. Snapshot all of it and restore in defer
        // so sibling suites never observe this test's locale (the override
        // has no identifier re-apply, so it restores to nil like the
        // established pattern).
        let savedLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        let savedLocale = UserDefaults.standard.object(forKey: "AppleLocale")
        let savedTZ = getenv("TZ").map { String(cString: $0) }
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
            if let value = savedTZ {
                setenv("TZ", value, 1)
            } else {
                unsetenv("TZ")
            }
            ScreenshotLocale.reset()
        }
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        let ack = await controller.start(initial: initial)
        #expect(ack.status == "ready")
        #expect(controller.viewClock?.calendar.locale?.identifier == Locale(identifier: "en_US").identifier)
        #expect(ScreenshotLocale.overrideIdentifier == "en")
    }

    // MARK: - 3.2 deterministic presentation resets

    @Test("every command mounts a fresh shell with the story tab")
    func shellResetsPerCommand() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        let first = try #require(controller.shellVM)
        #expect(first.selectedTab == .track)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        let second = try #require(controller.shellVM)
        #expect(second.selectedTab == .insights)
        #expect(second !== first)
        try publish(docs, frame: "history", seq: 2)
        _ = await controller.drainOne()
        let third = try #require(controller.shellVM)
        #expect(third.selectedTab == .history)
        #expect(third !== second)
    }

    @Test("pushed navigation state does not survive the next command")
    func navigationPathReset() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        let container = controller.sessionContainer!
        container.navigation.path.append(.emailEntry)
        #expect(!container.navigation.path.isEmpty)
        try publish(docs, frame: "insights", seq: 1)
        let drained = await controller.drainOne()
        guard case .ready = drained else {
            Issue.record("expected ready, got \(drained)")
            return
        }
        #expect(container.navigation.path.isEmpty)
    }

    @Test("history derivation loads the full fixture after story commands")
    func historyLoadsFullFixture() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        try publish(docs, frame: "history", seq: 2)
        _ = await controller.drainOne()
        // Search state is view-local (a fresh view model per mount), so the
        // session-level regression is the shared store: every command must
        // leave the committed fixture complete and loadable unfiltered.
        let store = controller.testStore()
        let historyVM = HistoryViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            now: { initial.request.referenceDate },
            calendar: initial.request.calendar
        )
        await historyVM.load()
        #expect(historyVM.dayGroups.reduce(0) { $0 + $1.entries.count } == 55)
    }

    @Test("add-entry command mounts with a gate-valid form from its own request")
    func addEntryFormFromMountedCommand() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        try publish(docs, frame: "history", seq: 2)
        _ = await controller.drainOne()
        try publish(docs, frame: "add-entry", seq: 3)
        let drained = await controller.drainOne()
        guard case .ready = drained else {
            Issue.record("expected ready, got \(drained)")
            return
        }
        // Mounted-state proof: the add-entry revision is the active,
        // mount-confirmed revision — not merely a locally built form.
        #expect(controller.activeFrame == .addEntry)
        #expect(controller.mountedFrame == .addEntry)
        // The form derives from the ACCEPTED seq-3 command's own request
        // and passes the Log Time validity gate.
        let command = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "add-entry", seq: 3))
        let container = controller.sessionContainer!
        let form = try ScreenshotAddEntry.makeForm(service: container.timerService, request: command.request)
        #expect(!form.timesTouched)
        #expect(form.trimmedName == ScreenshotFixture.addEntryText)
        #expect(form.notes == ScreenshotFixture.addEntryNotes)
        #expect(form.categoryIDs == ScreenshotFixture.addEntryCategoryIDs)
        #expect(form.isAddEnabled)
    }

    // MARK: - 3.3 fixture mutation rejection

    @Test("a deleted fixture entry rejects the next command as failed")
    func mutatedFixtureRejectsReady() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        let store = controller.testStore()
        let before = try await store.entries()
        #expect(before.count == 55)
        try await store.deleteEntry(id: before[0].id)
        try publish(docs, frame: "insights", seq: 1)
        let drained = await controller.drainOne()
        guard case let .failed(code) = drained else {
            Issue.record("expected failure, got \(drained)")
            return
        }
        #expect(code == "totals-invalid")
        let state = try CaptureStateWriter.read(from: docs)
        #expect(state.status == "failure")
        // Terminal: a further command is refused without file touches.
        try envelope(frame: "history", seq: 2).write(
            to: ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        )
        let refused = await controller.drainOne()
        guard case .failed = refused else {
            Issue.record("expected refusal, got \(refused)")
            return
        }
    }

    @Test("add-entry snapshots are identical before and after")
    func addEntrySnapshotsIdentical() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        _ = await controller.start(initial: initial)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        try publish(docs, frame: "history", seq: 2)
        _ = await controller.drainOne()
        let store = controller.testStore()
        let beforeEntries = try await store.entries()
        let beforeDraft = try await store.timerDraft()
        try publish(docs, frame: "add-entry", seq: 3)
        let drained = await controller.drainOne()
        guard case .ready = drained else {
            Issue.record("expected ready, got \(drained)")
            return
        }
        #expect(try await store.entries() == beforeEntries)
        let afterDraft = try await store.timerDraft()
        #expect(afterDraft?.activityText == beforeDraft?.activityText)
        #expect(afterDraft?.startedAt == beforeDraft?.startedAt)
    }

    // MARK: - 3.4 bounded mount failure

    @Test("an unmounted root fails bounded with mount-timeout")
    func unmountedBoundsFailure() async throws {
        let docs = try temporaryDocuments()
        let controller = ScreenshotSessionController(documents: docs)
        controller.settleGraceProvider = { _ in 0.01 }
        // No auto-mount: nothing ever confirms the revision.
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        let start = ScreenshotSessionClock.nowNanos()
        let ack = await controller.start(initial: initial)
        let elapsedNanos = ScreenshotSessionClock.nowNanos() - start
        #expect(ack.status == "failure")
        #expect(ack.error?.code == "mount-timeout")
        // Bounded: the 10s mount deadline trips, never an open wait.
        #expect(elapsedNanos < 15_000_000_000)
        #expect(controller.mountedFrame == nil)
    }
}
#endif
