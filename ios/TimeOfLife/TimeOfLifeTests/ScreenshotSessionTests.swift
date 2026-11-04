// swiftlint:disable file_length
#if SCREENSHOT_CAPTURE
import Foundation
import Testing
@testable import TimeOfLife

/// Session-protocol regression foundation (tasks 2.1/2.2/2.4 Swift, 3.4/3.5,
/// 4.3/4.5/4.7 Swift). Protocol freeze `evidence/protocol.md` v2: outer envelope
/// carries `request_json` as an exact UTF-8 string; the app hashes THOSE
/// bytes (never a Swift re-encoding) and parses them with the existing
/// request loader. Claim = atomic rename of the queue file before execution;
/// any new publication with an old seq is a replay even when bytes are
/// identical (no mtime/inode heuristics).
@MainActor
@Suite("Screenshot session protocol")
struct ScreenshotSessionTests {
    private let nonce = "abcdef0123456789abcdef0123456789"
    private let otherNonce = "0123456789abcdef0123456789abcdef"
    private let runID = "iphone69-en-r1"

    private func payload(
        frame: String = "track-running",
        mode: String = "app-clock-pinned",
        locale: String = "en",
        region: String = "US",
        timezone: String = "America/Chicago",
        runID: String? = nil
    ) throws -> Data {
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
            "mode": mode,
            "run_id": runID ?? self.runID,
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func envelope(
        frame: String = "track-running",
        mode: String = "app-clock-pinned",
        domain: ScreenshotSessionDomain = .pinned,
        seq: Int = 0,
        nonce: String? = nil,
        runID: String? = nil,
        locale: String = "en",
        region: String = "US",
        timezone: String = "America/Chicago"
    ) throws -> Data {
        try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: payload(frame: frame, mode: mode, locale: locale, region: region, timezone: timezone, runID: runID),
            runID: runID ?? self.runID,
            nonce: nonce ?? self.nonce,
            domain: domain,
            seq: seq
        )
    }

    private func codeFor(_ data: Data) -> String {
        do {
            _ = try ScreenshotSessionEnvelopeLoader.parse(data: data)
            return "ok"
        } catch let error as ScreenshotRequestError {
            return error.code
        } catch {
            return "unexpected:\(error)"
        }
    }

    private func mutate(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        guard var outer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("envelope must be a JSON object")
            return data
        }
        change(&outer)
        return try JSONSerialization.data(withJSONObject: outer)
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

    private func publish(_ documents: URL, frame: String, seq: Int, mode: String = "app-clock-pinned") throws {
        let queue = try ScreenshotSessionPaths.queueURL(documents: documents, nonce: nonce)
        try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
        try envelope(frame: frame, mode: mode, seq: seq).write(to: queue)
    }

    private func builderCode(
        frame: String = "track-running",
        mode: String = "app-clock-pinned",
        seq: Int = 0,
        nonce: String? = nil
    ) -> String {
        do {
            _ = try envelope(frame: frame, mode: mode, seq: seq, nonce: nonce)
            return "ok"
        } catch let error as ScreenshotRequestError {
            return error.code
        } catch {
            return "unexpected:\(error)"
        }
    }

    // MARK: - 2.2 envelope parsing

    @Test("valid seq-0 pinned envelope parses with exact payload hash")
    func validEnvelope() throws {
        let env = try ScreenshotSessionEnvelopeLoader.parse(data: envelope())
        #expect(env.runID == runID)
        #expect(env.nonce == nonce)
        #expect(env.domain == .pinned)
        #expect(env.seq == 0)
        #expect(env.frame == .trackRunning)
        #expect(env.mode == .appClockPinned)
        #expect(env.requestSHA256.count == 64)
        #expect(env.requestSHA256 == ScreenshotRequestLoader.sha256Hex(Data(env.requestJSON.utf8)))
        #expect(env.request.runID == runID)
    }

    @Test("schema-1 root without envelope is rejected for runtime")
    func legacyRootRejected() throws {
        #expect(codeFor(try payload()) == "unsupported-schema")
    }

    @Test("malformed nonces fail closed")
    func badNonces() throws {
        // Builder and parser both reject with the same stable code.
        #expect(builderCode(nonce: "ABCDEF0123456789ABCDEF0123456789") == "unsupported-nonce")
        #expect(builderCode(nonce: "short") == "unsupported-nonce")
        #expect(builderCode(nonce: "../capture-sessions/evil..........") == "unsupported-nonce")
        let mutated = try mutate(envelope()) { $0["session_nonce"] = "short" }
        #expect(codeFor(mutated) == "unsupported-nonce")
    }

    @Test("negative sequence fails closed")
    func negativeSeq() throws {
        #expect(builderCode(seq: -1) == "bad-seq")
        let mutated = try mutate(envelope()) { $0["seq"] = -1 }
        #expect(codeFor(mutated) == "bad-seq")
    }

    @Test("tampered payload bytes fail the exact hash")
    func tamperedPayload() throws {
        let tampered = try mutate(envelope()) {
            let original = $0["request_json"] as? String ?? ""
            $0["request_json"] = original.replacingOccurrences(of: "track-running", with: "insights")
        }
        #expect(codeFor(tampered) == "sha-mismatch")
    }

    @Test("outer metadata alone never changes the payload hash")
    func outerMetadataDoesNotChangePayloadHash() throws {
        let a = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(seq: 0, nonce: nonce))
        let b = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(seq: 0, nonce: otherNonce))
        #expect(a.requestSHA256 == b.requestSHA256)
        #expect(a.nonce != b.nonce)
    }

    @Test("outer/inner frame and run mismatches fail closed")
    func outerInnerMismatch() throws {
        let frameChanged = try mutate(envelope(frame: "track-running")) { $0["frame"] = "insights" }
        #expect(codeFor(frameChanged) == "outer-inner-mismatch")
        let runChanged = try mutate(envelope()) { $0["run_id"] = "iphone69-en-r2" }
        #expect(codeFor(runChanged) == "outer-inner-mismatch")
    }

    @Test("unknown frames and domains fail closed")
    func unknownFrameDomain() throws {
        let badFrame = try mutate(envelope()) { $0["frame"] = "widget" }
        #expect(codeFor(badFrame) == "unknown-frame")
        let badDomain = try mutate(envelope()) { $0["session_domain"] = "frozen" }
        #expect(codeFor(badDomain) == "unknown-domain")
    }

    @Test("realtime frames are rejected in a pinned domain at build time")
    func domainFrameBinding() throws {
        do {
            _ = try envelope(frame: "la-lock", mode: "live-activity-realtime", domain: .pinned, seq: 0)
            Issue.record("pinned builder must reject la-lock")
        } catch let error as ScreenshotRequestError {
            #expect(error.code == "wrong-domain")
        }
    }

    // MARK: - 2.2 ordering / replay (validator)

    @Test("validator accepts the next story frame and rejects gaps")
    func validatorOrdering() throws {
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let validator = try ScreenshotSessionValidator(initial: initial)
        let next = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "insights", seq: 1))
        try validator.validate(next)
        #expect(validator.transcript.count == 2)
        let skipping = try ScreenshotSessionValidator(initial: initial)
        let gap = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "history", seq: 2))
        #expect(throws: ScreenshotRequestError.self) { try skipping.validate(gap) }
    }

    @Test("replayed sequences fail closed even with identical bytes")
    func validatorReplay() throws {
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let validator = try ScreenshotSessionValidator(initial: initial)
        let replay = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        #expect(throws: ScreenshotRequestError.self) { try validator.validate(replay) }
    }

    @Test("locale changes mid-session fail closed")
    func validatorImmutable() throws {
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let validator = try ScreenshotSessionValidator(initial: initial)
        let ru = try ScreenshotSessionEnvelopeLoader.parse(
            data: envelope(frame: "insights", seq: 1, locale: "ru", region: "RU", timezone: "Europe/Moscow")
        )
        #expect(throws: ScreenshotRequestError.self) { try validator.validate(ru) }
    }

    @Test("cross-session nonces fail closed")
    func validatorCrossSession() throws {
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let validator = try ScreenshotSessionValidator(initial: initial)
        let foreign = try ScreenshotSessionEnvelopeLoader.parse(
            data: envelope(frame: "insights", seq: 1, nonce: otherNonce)
        )
        #expect(throws: ScreenshotRequestError.self) { try validator.validate(foreign) }
    }

    // MARK: - 2.3 canonicalizer edge cases (Python-compatible bytes)

    @Test("canonicalizer matches Python escaping and code-point key order")
    func canonicalEdgeCases() throws {
        let dict: [String: Any] = [
            "b": 1,
            "a": ["x": true, "y": "a\"b\\c\né中"],
            "中": 2,
        ]
        let bytes = try ScreenshotCanonicalJSON.canonicalBytes(dict)
        #expect(String(data: bytes, encoding: .utf8) == "{\"a\":{\"x\":true,\"y\":\"a\\\"b\\\\c\\né中\"},\"b\":1,\"中\":2}\n")
        // Trailing newline is part of the hashed bytes.
        #expect(bytes.last == 0x0A)
    }

    // MARK: - 3.x locale-accurate day headers (predecessor-lag regression)

    @Test("absolute day headers follow the request locale, never ambient")
    func dayHeadersFollowRequestLocale() throws {
        // Regression (sequence proof ru-r1 EN / zh-r1 RU / es-r1 ZH /
        // pt-r1 ES): dayLabel's DateFormatter set the calendar but never
        // the locale, so absolute headers rendered the ambient/predecessor
        // locale while override-driven chrome stayed correct.
        //
        // Hermetic by construction: the locale under test travels as an
        // explicit parameter, never through process-global override state,
        // so this suite cannot interleave with ambient-assuming suites
        // running on other threads. The global wiring itself
        // (`?? ScreenshotLocale.appLocale`) is proven on device, where the
        // same override fixed every locale's headers in-session.
        let pairings: [(locale: String, region: String, timezone: String, apple: String)] = [
            ("ru", "RU", "Europe/Moscow", "ru_RU"),
            ("zh-Hans", "CN", "Asia/Shanghai", "zh_Hans_CN"),
            ("es-419", "MX", "America/Mexico_City", "es_MX"),
            ("pt-BR", "BR", "America/Sao_Paulo", "pt_BR"),
        ]
        for pairing in pairings {
            let request = try ScreenshotRequestLoader.parse(data: payload(
                frame: "history",
                locale: pairing.locale,
                region: pairing.region,
                timezone: pairing.timezone
            ))
            // A non-recent day in the request calendar (Oct 18 vs Oct 20
            // reference): forces the absolute formatter path everywhere.
            var wall = Calendar(identifier: .gregorian)
            wall.timeZone = request.timeZone
            let noonToday = try #require(wall.date(bySettingHour: 12, minute: 0, second: 0, of: request.referenceDate))
            let noon = noonToday.addingTimeInterval(-2 * 24 * 3600)
            let requestLocale = Locale(identifier: pairing.apple)
            var oracleCalendar = Calendar(identifier: .gregorian)
            oracleCalendar.timeZone = request.timeZone
            oracleCalendar.locale = requestLocale
            let oracle = DateFormatter()
            oracle.dateStyle = .medium
            oracle.timeStyle = .none
            oracle.calendar = oracleCalendar
            oracle.locale = requestLocale
            let expected = oracle.string(from: noon)
            let ambient = DateFormatter()
            ambient.dateStyle = .medium
            ambient.timeStyle = .none
            ambient.locale = Locale(identifier: "en_US")
            let ambientRendering = ambient.string(from: noon)
            // One-shot overload.
            #expect(
                HistoryViewModel.dayLabel(for: noon, now: request.referenceDate, calendar: request.calendar, locale: requestLocale) == expected,
                "one-shot header \(pairing.locale)"
            )
            // Reusable-formatter overload (History list derivation path).
            var box: DateFormatter?
            #expect(
                HistoryViewModel.dayLabel(for: noon, now: request.referenceDate, calendar: request.calendar, formatter: &box, locale: requestLocale) == expected,
                "reused header \(pairing.locale)"
            )
            // The bug class, pinned: must not echo the ambient rendering
            // when the request locale differs from it.
            if expected != ambientRendering {
                #expect(
                    HistoryViewModel.dayLabel(for: noon, now: request.referenceDate, calendar: request.calendar, locale: requestLocale) != ambientRendering,
                    "no ambient echo \(pairing.locale)"
                )
            }
        }
        // The runtime default path (no explicit locale, no override) is
        // untouched: ambient rendering still flows through. (No assertion
        // on global override state here by design: sibling suites share
        // this process and may hold their own request override while this
        // test runs. Hermeticity of THIS test comes from never setting
        // globals itself — verifiable by inspection, not by sampling them.)
    }

    // MARK: - 2.4 atomic claim

    @Test("empty queue is a no-op, claimed file is consumed once")
    func claimEmptyAndOnce() throws {
        let docs = try temporaryDocuments()
        #expect(try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: []) == .empty)
        let queue = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
        try envelope(frame: "track-running", seq: 0).write(to: queue)
        let claimed = try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: [])
        guard case let .claimed(first) = claimed else {
            Issue.record("expected a claim")
            return
        }
        #expect(first.seq == 0)
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        // Re-observing without a new publication is a no-op.
        #expect(try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: [first.seq]) == .empty)
    }

    @Test("explicit duplicate publication of a consumed seq is a replay")
    func claimReplay() throws {
        let docs = try temporaryDocuments()
        let queue = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
        try envelope(frame: "track-running", seq: 0).write(to: queue)
        let claimed = try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: [])
        guard case let .claimed(first) = claimed else {
            Issue.record("expected a claim")
            return
        }
        // A new publication of the identical bytes for the same seq.
        try envelope(frame: "track-running", seq: 0).write(to: queue)
        do {
            _ = try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: [first.seq])
            Issue.record("replay must fail closed")
        } catch let error as ScreenshotRequestError {
            #expect(error.code == "replay")
        }
    }

    @Test("staging temp files are never claimed and partial writes fail bounded")
    func claimTempAndPartial() throws {
        let docs = try temporaryDocuments()
        let dir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"schema_version\":".utf8).write(to: dir.appendingPathComponent("command.json.tmp-publish"))
        #expect(try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: []) == .empty)
        let queue = dir.appendingPathComponent("command.json")
        try Data("not json".utf8).write(to: queue)
        do {
            _ = try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: [])
            Issue.record("partial write must fail")
        } catch let error as ScreenshotRequestError {
            #expect(!error.code.isEmpty)
        }
        // The corrupt publication is removed so the session does not wedge;
        // the seq stays unconsumed and the runner must republish explicitly.
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        #expect(try ScreenshotSessionClaim.poll(documents: docs, nonce: nonce, consumedSeqs: []) == .empty)
    }

    @Test("traversal nonces and symlink escapes are rejected")
    func claimPathGuards() throws {
        let docs = try temporaryDocuments()
        #expect(throws: ScreenshotRequestError.self) {
            _ = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: "../escape")
        }
        #expect(throws: ScreenshotRequestError.self) {
            _ = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: "")
        }
        // A symlinked session directory must not be trusted.
        let real = try temporaryDocuments()
        let link = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(throws: ScreenshotRequestError.self) {
            _ = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        }
    }

    // MARK: - 2.1 timings (monotonic, no cross-clock math)

    @Test("timing samples are non-negative and counting")
    func timingsMonotonic() async throws {
        var timings = ScreenshotSessionTimings()
        let start = ScreenshotSessionClock.nowNanos()
        try await Task.sleep(nanoseconds: 1_000_000)
        timings.add(phase: "seed", elapsedNanos: ScreenshotSessionClock.nowNanos() - start, count: 55)
        #expect(timings.samples.count == 1)
        #expect(timings.samples[0].milliseconds >= 0)
        #expect(timings.samples[0].count == 55)
        let round = try JSONDecoder().decode(ScreenshotSessionTimings.self, from: JSONEncoder().encode(timings))
        #expect(round == timings)
    }

    // MARK: - 3.4 revision-tagged mounting

    @Test("stale mount callbacks never authorize a newer revision")
    func lateCallbackIgnored() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let ack = await controller.start(initial: initial)
        #expect(ack.status == "ready")
        let stale = try #require(controller.revision)
        controller.testOnlyBumpRevision()
        #expect(controller.noteMounted(revision: stale) == false)
        #expect(controller.mountedFrame == .trackRunning)
        #expect(controller.noteMounted(revision: controller.revision!) == true)
    }

    // MARK: - 3.x session batching (real store, real view models)

    @Test("two pinned commands share one seeded store with transcript")
    func pinnedBatching() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let ack0 = await controller.start(initial: initial)
        #expect(ack0.status == "ready")
        #expect(ack0.sessionNonce == nonce)
        #expect(ack0.seq == 0)
        #expect(ack0.transcript?.count == 1)
        try publish(docs, frame: "insights", seq: 1)
        let drained = await controller.drainOne()
        guard case let .ready(frame, seq) = drained else {
            Issue.record("expected ready, got \(drained)")
            return
        }
        #expect(frame == .insights)
        #expect(seq == 1)
        // Fixture untouched: still 55 committed entries.
        #expect(try await controller.testStore().entries().count == 55)
        // The live ack binds the new seq/hash — a stale seq-0 ack cannot
        // authorize the seq-1 export.
        let state = try CaptureStateWriter.read(from: docs)
        #expect(state.seq == 1)
        #expect(state.sessionNonce == nonce)
        #expect(state.sessionDomain == "pinned")
        #expect(state.requestSHA256 == controller.transcript.last?.requestSHA256)
        #expect(state.transcript?.count == 2)
        // App-clock durations ride the ack for the runner phase breakdown.
        #expect((state.appDurationsMS?["seed"] ?? -1) >= 0)
        #expect((state.appDurationsMS?["validation"] ?? -1) >= 0)
        // Phase timings ride the ack for the runner phase breakdown
        // (per-command app_durations_ms, archived separately from the
        // runner's own monotonic phases — the clocks never mix).
        #expect((state.appDurationsMS?["seed"] ?? -1) >= 0)
        #expect((state.appDurationsMS?["validation"] ?? -1) >= 0)
        #expect((state.appDurationsMS?["mount_wait"] ?? -1) >= 0)
        #expect((state.appDurationsMS?["settle"] ?? -1) >= 0)
        // Seed evidence: committed counts + pinned totals in the ack.
        #expect(state.counts?.entries == 55)
        #expect(state.expectedTotals?.allSeconds == 198_600)
    }

    @Test("add-entry command never commits and keeps totals")
    func addEntryNoWrite() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        for (frame, seq) in [("insights", 1), ("history", 2), ("add-entry", 3)] {
            try publish(docs, frame: frame, seq: seq)
            let drained = await controller.drainOne()
            guard case .ready = drained else {
                Issue.record("expected ready for \(frame)")
                return
            }
        }
        #expect(try await controller.testStore().entries().count == 55)
        #expect(controller.transcript.count == 4)
    }

    @Test("terminal state refuses further end-of-session commands untouched")
    func terminalRefusesFurtherCommands() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        // Bounded failure: garbage bytes fail the session promptly and the
        // corrupt publication is removed (no wedge on garbage).
        let queue = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: queue)
        let failed = await controller.drainOne()
        guard case let .failed(code) = failed else {
            Issue.record("expected failure, got \(failed)")
            return
        }
        #expect(!code.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        #expect(try CaptureStateWriter.read(from: docs).status != "ready" || controller.transcript.count == 1)
        // End-of-session: a later valid command is refused without a file touch.
        try envelope(frame: "insights", seq: 1).write(to: queue)
        let refused = await controller.drainOne()
        guard case let .failed(refusedCode) = refused else {
            Issue.record("expected refusal, got \(refused)")
            return
        }
        #expect(refusedCode == code)
        #expect(FileManager.default.fileExists(atPath: queue.path))
        #expect(controller.transcript.count == 1)
    }

    @Test("cancellation stops the watcher without further commands")
    func cancellationStopsWatcher() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        let task = Task { await controller.runUntilTerminal(initial: initial) }
        var spins = 0
        while controller.transcript.isEmpty, spins < 400 {
            try await Task.sleep(nanoseconds: 50_000_000)
            spins += 1
        }
        #expect(controller.transcript.count == 1)
        task.cancel()
        await task.value
        // Published after cancellation: never drained.
        try publish(docs, frame: "insights", seq: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(controller.transcript.count == 1)
    }

    // MARK: - 4.5 one real-time anchor per session

    @Test("real-time session shares one activity anchor across states")
    func realtimeAnchorShared() async throws {
        let docs = try temporaryDocuments()
        var starts = 0
        let anchor = CaptureStateLiveActivity(
            activityID: "live-anchor-1",
            startedAt: "2026-10-20T14:41:00Z",
            requestAcknowledgedAt: "2026-10-20T14:41:01Z"
        )
        let controller = ScreenshotSessionController(documents: docs) { _, _ in
            starts += 1
            return anchor
        }
        controller.settleGraceProvider = { _ in 0.01 }
        controller.autoMountInTests = true
        let initial = try ScreenshotSessionEnvelopeLoader.parse(
            data: envelope(frame: "la-lock", mode: "live-activity-realtime", domain: .realtime, seq: 0)
        )
        let ack0 = await controller.start(initial: initial)
        #expect(ack0.status == "ready")
        #expect(starts == 1)
        for (frame, seq) in [("la-compact", 1), ("la-expanded", 2)] {
            let queue = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
            try FileManager.default.createDirectory(at: queue.deletingLastPathComponent(), withIntermediateDirectories: true)
            try envelope(frame: frame, mode: "live-activity-realtime", domain: .realtime, seq: seq).write(to: queue)
            let drained = await controller.drainOne()
            guard case .ready = drained else {
                Issue.record("expected ready for \(frame)")
                return
            }
        }
        #expect(starts == 1)
        let state = try CaptureStateWriter.read(from: docs)
        #expect(state.liveActivity?.activityID == "live-anchor-1")
        #expect(state.transcript?.count == 3)
    }

    @Test("terminal state writes the end-of-session marker")
    func sessionEndedMarker() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        // Force a terminal state with a bad command.
        let queue = try ScreenshotSessionPaths.queueURL(documents: docs, nonce: nonce)
        try Data("not json".utf8).write(to: queue)
        _ = await controller.drainOne()
        let markerURL = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
            .appendingPathComponent("session-ended.json")
        let marker = try JSONSerialization.jsonObject(with: Data(contentsOf: markerURL)) as? [String: Any]
        #expect(marker?["final_seq"] as? Int == 1)
        #expect(marker?["session_nonce"] as? String == nonce)
    }

    @Test("cleanup with an orphaned consumed record fails as interrupted")
    func cleanupInterruptedCommand() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        // A consumed-but-unacked command (crash between claim and ack).
        let dir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("consumed-1.json"))
        let state = try CaptureStateWriter.read(from: docs)
        let ack = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(
                runID: runID,
                expectedSHA256: state.requestSHA256 ?? "",
                sessionNonce: nonce,
                sessionDomain: "pinned",
                finalSeq: 0
            )
        )
        #expect(ack.status == "failure")
        #expect(ack.error?.code == "interrupted-command")
    }

    @Test("cleanup removes its owned queue directory and nothing else")
    func cleanupRemovesOwnedQueueDir() async throws {
        // Queue-dir leftovers are session evidence debt, not hygiene: every
        // cleaned session must leave no queue/transcript files behind, while
        // foreign nonces and the runner-read fixed acks stay untouched.
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        try publish(docs, frame: "insights", seq: 1)
        _ = await controller.drainOne()
        let ownDir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        #expect(FileManager.default.fileExists(atPath: ownDir.appendingPathComponent("consumed-1.json").path))
        // Foreign session debris beside the owned directory.
        let foreignDir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: otherNonce)
        try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
        let foreignMarker = foreignDir.appendingPathComponent("consumed-0.json")
        try Data("{}".utf8).write(to: foreignMarker)
        let state = try CaptureStateWriter.read(from: docs)
        let ack = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(
                runID: runID,
                expectedSHA256: state.requestSHA256 ?? "",
                sessionNonce: nonce,
                sessionDomain: "pinned",
                finalSeq: 1
            )
        )
        #expect(ack.status == "cleaned")
        #expect(ack.removedSessionQueue == true)
        // No queue/transcript files left for the cleaned session.
        #expect(!FileManager.default.fileExists(atPath: ownDir.path))
        // Foreign nonce files are never touched.
        #expect(FileManager.default.fileExists(atPath: foreignMarker.path))
        // Fixed acks stay for the runner read (state + cleanup receipts are
        // cleared only by the next session stage, never by cleanup).
        #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent("capture-state.json").path))
        #expect(try CaptureCleanupWriter.read(from: docs) == ack)
    }

    @Test("unbound cleanup invocation is rejected without touching anything")
    func unboundCleanupRejected() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        let ownDir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        #expect(FileManager.default.fileExists(atPath: ownDir.appendingPathComponent("consumed-0.json").path))
        let state = try CaptureStateWriter.read(from: docs)
        let sessionDir = try ScreenshotPreparation.sessionDirectory(runID: runID)
        // No session tokens: rejected before verification, deleting nothing —
        // neither the fixture store nor any queue directory.
        let ack = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(runID: runID, expectedSHA256: state.requestSHA256 ?? "")
        )
        #expect(ack.status == "mismatch")
        #expect(ack.error?.code == "cleanup-mismatch")
        #expect(ack.removedSessionQueue == false)
        #expect(FileManager.default.fileExists(atPath: sessionDir.path))
        #expect(FileManager.default.fileExists(atPath: ownDir.path))
        try? FileManager.default.removeItem(at: sessionDir)
    }

    // MARK: - 4.3 transcript-bound cleanup

    @Test("cleanup binds nonce, final seq, and transcript")
    func cleanupTranscriptBound() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        let state = try CaptureStateWriter.read(from: docs)
        let ack = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(
                runID: runID,
                expectedSHA256: state.requestSHA256 ?? "",
                sessionNonce: nonce,
                sessionDomain: "pinned",
                finalSeq: 0
            )
        )
        #expect(ack.status == "cleaned")
        #expect(ack.sessionNonce == nonce)
        #expect(ack.sessionDomain == "pinned")
        #expect(ack.finalSeq == 0)
        #expect(ack.transcript?.count == 1)
    }

    @Test("cleanup with a foreign nonce or short transcript fails closed")
    func cleanupTranscriptMismatch() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        let state = try CaptureStateWriter.read(from: docs)
        let foreign = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(
                runID: runID,
                expectedSHA256: state.requestSHA256 ?? "",
                sessionNonce: otherNonce,
                sessionDomain: "pinned",
                finalSeq: 0
            )
        )
        #expect(foreign.status != "cleaned")
        let short = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(
                runID: runID,
                expectedSHA256: state.requestSHA256 ?? "",
                sessionNonce: nonce,
                sessionDomain: "pinned",
                finalSeq: 4
            )
        )
        #expect(short.status != "cleaned")
    }

    // MARK: - 8.5 strict runtime routing (no legacy fallback)

    @Test("v1 root without envelope is explicitly rejected, never legacy")
    func routeRejectsV1Root() throws {
        let docs = try temporaryDocuments()
        try payload().write(to: docs.appendingPathComponent(ScreenshotCaptureRequest.requestFilename))
        let route = ScreenshotSessionRoute.resolve(documents: docs)
        guard case let .invalid(error) = route else {
            Issue.record("v1 root must reject, got \(route)")
            return
        }
        #expect(error.code == "unsupported-schema")
    }

    @Test("missing root file is explicitly rejected")
    func routeRejectsMissingFile() throws {
        let docs = try temporaryDocuments()
        let route = ScreenshotSessionRoute.resolve(documents: docs)
        guard case let .invalid(error) = route else {
            Issue.record("missing root must reject, got \(route)")
            return
        }
        #expect(error.code == "missing-file")
    }

    @Test("v2 envelope routes to the session controller")
    func routeAcceptsV2() throws {
        let docs = try temporaryDocuments()
        try envelope().write(to: docs.appendingPathComponent(ScreenshotCaptureRequest.requestFilename))
        let route = ScreenshotSessionRoute.resolve(documents: docs)
        guard case let .session(env) = route else {
            Issue.record("v2 envelope must route to session, got \(route)")
            return
        }
        #expect(env.seq == 0)
    }

    @Test("legacy single live-activity frame is rejected")
    func legacyFrameRejected() throws {
        guard var dict = try JSONSerialization.jsonObject(with: payload()) as? [String: Any] else {
            Issue.record("expected a JSON object")
            return
        }
        dict["frame"] = "live-activity"
        dict["mode"] = "live-activity-realtime"
        let data = try JSONSerialization.data(withJSONObject: dict)
        do {
            _ = try ScreenshotRequestLoader.parse(data: data)
            Issue.record("legacy frame must fail closed")
        } catch let error as ScreenshotRequestError {
            #expect(error.code == "unknown-frame")
        }
    }

    @Test("cleanup invocation without session tokens parses as nothing")
    func cleanupRejectsTwoTokens() throws {
        #expect(ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: ["SCREENSHOT_CLEANUP": "run-a", "SCREENSHOT_CLEANUP_SHA": "abc"]
        ) == nil)
    }

    @Test("cleanup without session binding refuses without touching")
    func cleanupRequiresSessionBinding() async throws {
        let docs = try temporaryDocuments()
        let controller = fastController(documents: docs)
        let initial = try ScreenshotSessionEnvelopeLoader.parse(data: envelope(frame: "track-running", seq: 0))
        _ = await controller.start(initial: initial)
        let state = try CaptureStateWriter.read(from: docs)
        let sessionDir = try ScreenshotPreparation.sessionDirectory(runID: runID)
        #expect(FileManager.default.fileExists(atPath: sessionDir.path))
        // A two-token invocation is no longer a valid session cleanup, even
        // with a matching run and SHA: it must fail closed, deleting nothing.
        let ack = await ScreenshotCleanup.perform(
            documents: docs,
            invocation: ScreenshotCleanupInvocation(runID: runID, expectedSHA256: state.requestSHA256 ?? "")
        )
        #expect(ack.status == "mismatch")
        #expect(ack.error?.code == "cleanup-mismatch")
        #expect(FileManager.default.fileExists(atPath: sessionDir.path))
        #expect(ack.removedSessionQueue == false)
        try? FileManager.default.removeItem(at: sessionDir)
    }

    @Test("no-context terminal state can never authorize readiness")
    func noContextStateNeverReady() throws {
        let docs = try temporaryDocuments()
        let state = CaptureState(
            status: "invalid",
            requestSHA256: nil,
            deckVersion: nil,
            frame: nil,
            mode: nil,
            runID: nil,
            counts: nil,
            expectedTotals: nil,
            build: nil,
            clocks: nil,
            liveActivity: nil,
            error: CaptureStateFailure(code: "unsupported-schema", detail: "runtime root is not a v2 envelope"),
            sessionNonce: nil,
            sessionDomain: nil,
            seq: nil,
            transcript: nil,
            appDurationsMS: nil
        )
        try CaptureStateWriter.write(state, to: docs)
        let read = try CaptureStateWriter.read(from: docs)
        #expect(read.status != "ready")
        #expect(read.sessionNonce == nil && read.seq == nil && read.transcript == nil)
        #expect(read.error?.code == "unsupported-schema")
    }

    // MARK: - 4.7 capture transport stays out of shipping builds

    @Test("session files live outside the production App Group")
    func sessionNamespaceIsolation() throws {
        let docs = try temporaryDocuments()
        let dir = try ScreenshotSessionPaths.sessionDirectory(documents: docs, nonce: nonce)
        #expect(!dir.path.contains("group.com.antonkosenko.timeoflifeapp"))
        #expect(dir.lastPathComponent == nonce)
    }

    @Test("session cleanup tokens parse atomically or not at all")
    func sessionCleanupTokens() throws {
        let full = ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: [
                "SCREENSHOT_CLEANUP": "run-a",
                "SCREENSHOT_CLEANUP_SHA": "abc",
                "SCREENSHOT_SESSION_NONCE": nonce,
                "SCREENSHOT_SESSION_DOMAIN": "pinned",
                "SCREENSHOT_FINAL_SEQ": "3",
            ]
        )
        #expect(full == ScreenshotCleanupInvocation(
            runID: "run-a",
            expectedSHA256: "abc",
            sessionNonce: nonce,
            sessionDomain: "pinned",
            finalSeq: 3
        ))
        // Partial session tokens parse as no invocation (never half-bound).
        #expect(ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: [
                "SCREENSHOT_CLEANUP": "run-a",
                "SCREENSHOT_CLEANUP_SHA": "abc",
                "SCREENSHOT_SESSION_NONCE": nonce,
            ]
        ) == nil)
        // Legacy two-token invocations parse as nothing: session binding is
        // mandatory, with no per-frame fallback.
        #expect(ScreenshotLaunch.detectCleanup(
            argv: [],
            environment: ["SCREENSHOT_CLEANUP": "run-a", "SCREENSHOT_CLEANUP_SHA": "abc"]
        ) == nil)
    }
}
#endif
