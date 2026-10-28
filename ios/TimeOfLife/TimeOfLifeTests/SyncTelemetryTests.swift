import Foundation
import Testing
@testable import TimeOfLife

/// Stage-1 iOS telemetry: OTLP export shape, offline soak, and the
/// distress/volume separation (spec: relay down ⇒ volume fails 100% AND
/// distress still arrives on the Sentry channel, never on `/v1/sync`).
@MainActor
@Suite("SyncTelemetry")
struct SyncTelemetryTests {
    @Test("Debug defaults: enabled with a localhost Collector endpoint")
    func debugDefaults() {
        let config = SyncTelemetryConfig.resolved()
        #expect(config.isEnabled)
        #expect(config.endpoint.host == "127.0.0.1")
        #expect(config.endpoint.port == 4_318)
        #expect(config.endpoint.path == "/v1/traces")
    }

    @Test("endpoint derives from the relay host")
    func endpointDerivesFromRelayHost() throws {
        let api = try #require(URL(string: "https://relay.example:8443/api"))
        let config = SyncTelemetryConfig.resolved(apiBaseURL: api)
        #expect(config.endpoint.absoluteString == "https://relay.example:4318/v1/traces")
    }

    @Test("payload is OTLP/HTTP JSON with the allowlisted attributes only")
    func payloadShape() async throws {
        let stub = StubTransport()
        let endpoint = try #require(URL(string: "http://127.0.0.1:4318/v1/traces"))
        let exporter = SyncSpanExporter(
            config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
            transport: stub
        )
        let buffer = SyncSpanBuffer(directory: temporaryDirectory())
        await buffer.append(makeSpan(outcome: .success, pushed: 2, pulled: 9, conflicts: 1))
        #expect(await exporter.flush(buffer: buffer))
        #expect(await buffer.bufferedCount == 0)
        let body = try #require(stub.bodies.first)
        let text = String(data: body, encoding: .utf8) ?? ""
        for forbidden in ["user_id", "token", "email", "activity_text"] {
            #expect(!text.contains(forbidden))
        }
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let resource = try #require((json["resourceSpans"] as? [[String: Any]])?.first)
        let attributes = resource["resource"] as? [String: Any]
        let resourceAttrs = attributes?["attributes"] as? [[String: Any]]
        #expect(resourceAttrs?.contains { $0["key"] as? String == "service.name" } == true)
        #expect(resourceAttrs?.contains { $0["key"] as? String == "dropped_spans" } == true)
        let scopeSpans = try #require((resource["scopeSpans"] as? [[String: Any]])?.first)
        let span = try #require((scopeSpans["spans"] as? [[String: Any]])?.first)
        #expect(span["name"] as? String == "sync.session")
        let spanAttrs = (span["attributes"] as? [[String: Any]]) ?? []
        let keys = Set(spanAttrs.compactMap { $0["key"] as? String })
        #expect(keys == [
            "sync.outcome", "sync.wall_duration_ms", "sync.offline_duration_ms",
            "sync.pushed", "sync.pulled", "sync.conflicts",
            "sync.outbox_depth_before", "sync.outbox_depth_after",
        ])
        let outcome = spanAttrs.first { $0["key"] as? String == "sync.outcome" }
        let outcomeValue = (outcome?["value"] as? [String: Any])?["stringValue"] as? String
        #expect(outcomeValue == "success")
    }

    @Test("empty buffer flushes without posting")
    func emptyFlushPostsNothing() async throws {
        let stub = StubTransport()
        let endpoint = try #require(URL(string: "http://127.0.0.1:4318/v1/traces"))
        let exporter = SyncSpanExporter(
            config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
            transport: stub
        )
        #expect(await exporter.flush(buffer: SyncSpanBuffer(directory: temporaryDirectory())))
        #expect(stub.bodies.isEmpty)
    }

    @Test("disabled export buffers without posting")
    func disabledExportBuffersOnly() async throws {
        let stub = StubTransport()
        let endpoint = try #require(URL(string: "http://127.0.0.1:4318/v1/traces"))
        let buffer = SyncSpanBuffer(directory: temporaryDirectory())
        let telemetry = SyncTelemetry(
            buffer: buffer,
            exporter: SyncSpanExporter(
                config: SyncTelemetryConfig(isEnabled: false, endpoint: endpoint),
                transport: stub
            )
        )
        await telemetry.recordSpan(makeSpan(outcome: .success, pushed: 1, pulled: 0, conflicts: 0))
        #expect(stub.bodies.isEmpty)
        #expect(await buffer.bufferedCount == 1)
    }

    @Test("offline soak: failures keep order, recovery forwards, growth bounded")
    func offlineSoak() async throws {
        let stub = StubTransport()
        stub.shouldThrow = true
        let endpoint = try #require(URL(string: "http://127.0.0.1:4318/v1/traces"))
        let exporter = SyncSpanExporter(
            config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
            transport: stub
        )
        let buffer = SyncSpanBuffer(directory: temporaryDirectory(), maxSpans: 200)
        for index in 0 ..< 3 {
            await buffer.append(makeSpan(outcome: .failed, pushed: index, pulled: 0, conflicts: 0))
        }
        #expect(await exporter.flush(buffer: buffer) == false)
        #expect(stub.bodies.isEmpty)
        #expect(await buffer.bufferedCount == 3)
        stub.shouldThrow = false
        #expect(await exporter.flush(buffer: buffer))
        #expect(await buffer.bufferedCount == 0)
        let body = try #require(stub.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let resource = try #require((json["resourceSpans"] as? [[String: Any]])?.first)
        let scopeSpans = try #require((resource["scopeSpans"] as? [[String: Any]])?.first)
        let spans = try #require(scopeSpans["spans"] as? [[String: Any]])
        #expect(spans.count == 3)
        let pushed = spans.map { (($0["attributes"] as? [[String: Any]])?.first { $0["key"] as? String == "sync.pushed" }).flatMap { ($0["value"] as? [String: Any])?["intValue"] as? String } }
        #expect(pushed == ["0", "1", "2"])
    }

    @Test("relay down: volume fails 100% AND distress still fires")
    func distressSeparation() async throws {
        let context = try makeFailingContext()
        context.controller.activate(userID: "u1")
        await waitForCycle(context.controller)
        await context.controller.syncNow(userID: "u1")
        await context.controller.syncNow(userID: "u1")
        // Every cycle attempted the relay pull and failed (volume 0%).
        #expect(context.mock.fetchedEntryPageCursors.count == 3)
        if case .error = context.controller.status {} else {
            Issue.record("expected error status, got \(context.controller.status)")
        }
        // Distress fired exactly once — on the Sentry channel, while the
        // OTLP export kept failing (never piggybacked on the relay path).
        #expect(await context.recorder.count == 1)
        #expect(context.telemetry.failureStreak == 3)
        // Volume was still buffered (not dropped, not smuggled into distress).
        let spans = await context.buffer.spans()
        #expect(spans.count == 3)
        #expect(spans.allSatisfy { $0.outcome == .failed })
    }

    @Test("a success resets the distress streak")
    func successResetsStreak() async throws {
        let context = try makeFailingContext()
        context.controller.activate(userID: "u1")
        await waitForCycle(context.controller)
        await context.controller.syncNow(userID: "u1")
        #expect(context.telemetry.failureStreak == 2)
        // Recovery: the relay answers again, the streak resets.
        context.mock.fetchEntryPageHandler = nil
        await context.controller.syncNow(userID: "u1")
        #expect(context.telemetry.failureStreak == 0)
        #expect(await context.recorder.isEmpty)
        // Two more failures stay below the threshold; the third fires.
        context.mock.fetchEntryPageHandler = { _, _ in throw APIError.transport(underlying: "relay down") }
        await context.controller.syncNow(userID: "u1")
        await context.controller.syncNow(userID: "u1")
        #expect(await context.recorder.isEmpty)
        await context.controller.syncNow(userID: "u1")
        #expect(await context.recorder.count == 1)
    }

    // MARK: - Helpers

    private struct FailingContext {
        var store: LocalStore
        var mock: MockCatalogRepository
        var controller: SyncController
        var buffer: SyncSpanBuffer
        var telemetry: SyncTelemetry
        var recorder: DistressRecorder
    }

    private func makeFailingContext() throws -> FailingContext {
        let store = try LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        mock.fetchEntryPageHandler = { _, _ in throw APIError.transport(underlying: "relay down") }
        let buffer = SyncSpanBuffer(directory: temporaryDirectory())
        let stub = StubTransport()
        stub.shouldThrow = true
        let endpoint = try #require(URL(string: "http://127.0.0.1:4318/v1/traces"))
        let recorder = DistressRecorder()
        let telemetry = SyncTelemetry(
            buffer: buffer,
            exporter: SyncSpanExporter(
                config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
                transport: stub
            )
        ) { Task { await recorder.note() } }
        let controller = SyncController(
            store: store,
            remote: mock,
            connectivity: MockConnectivity(),
            telemetry: telemetry
        ) { "u1" }
        return FailingContext(
            store: store, mock: mock, controller: controller,
            buffer: buffer, telemetry: telemetry, recorder: recorder
        )
    }

    private func makeSpan(outcome: SyncSessionOutcome, pushed: Int, pulled: Int, conflicts: Int) -> SyncSessionSpan {
        SyncSessionSpan.build(
            start: Date(), end: Date(), outcome: outcome,
            counts: SyncSessionSpanCounts(pushed: pushed, pulled: pulled, conflicts: conflicts)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func waitForCycle(_ controller: SyncController) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if case .syncing = controller.status {
                try? await Task.sleep(nanoseconds: 10_000_000)
            } else {
                return
            }
        }
    }
}

final class StubTransport: OTLPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBodies: [Data] = []
    private var storedShouldThrow = false

    var bodies: [Data] {
        lock.withLock { storedBodies }
    }

    var shouldThrow: Bool {
        get {
            lock.withLock { storedShouldThrow }
        }
        set {
            lock.withLock { storedShouldThrow = newValue }
        }
    }

    func post(url: URL, body: Data) async throws {
        let fail = lock.withLock { () -> Bool in
            if !storedShouldThrow {
                storedBodies.append(body)
            }
            return storedShouldThrow
        }
        if fail {
            throw SyncExportError.rejected
        }
    }
}

actor DistressRecorder {
    private(set) var count = 0

    var isEmpty: Bool {
        count < 1
    }

    func note() {
        count += 1
    }
}
