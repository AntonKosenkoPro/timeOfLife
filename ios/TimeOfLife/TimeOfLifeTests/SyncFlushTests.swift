import Foundation
import Testing
@testable import TimeOfLife

/// Flush behavior: the transport status mapping the exporter's whole
/// poison-vs-retry policy keys off, the single-flight serialization, and the
/// re-kick on proven removal (observability Stage 1, AI review round 4).
@MainActor
@Suite("SyncFlush")
struct SyncFlushTests {
    private static let endpoint = URL(string: "http://127.0.0.1:4318/v1/traces")!

    /// The exporter's data-loss policy lives here: these statuses quarantine
    /// the whole buffered batch, so the mapping needs a direct test — a
    /// future edit must not silently turn transient back-pressure into
    /// discarded telemetry (or vice versa).
    @Test("URLSession transport maps permanent vs transient statuses")
    func transportStatusMapping() async throws {
        let endpoint = Self.endpoint
        let session = URLProtocolStub.makeSession()
        defer { URLProtocolStub.clear() }
        for status in [400, 401, 403, 404, 405, 413, 415, 422] {
            URLProtocolStub.stub(statusCode: status, for: endpoint)
            let transport = URLSessionOTLPTransport(session: session)
            do {
                try await transport.post(url: endpoint, body: Data("{}".utf8))
                Issue.record("status \(status): expected .permanent, posted clean")
            } catch let SyncExportError.permanent(code) {
                #expect(code == status)
            } catch {
                Issue.record("status \(status): expected .permanent, got \(error)")
            }
        }
        for status in [408, 425, 429, 500, 502, 503] {
            URLProtocolStub.stub(statusCode: status, for: endpoint)
            let transport = URLSessionOTLPTransport(session: session)
            do {
                try await transport.post(url: endpoint, body: Data("{}".utf8))
                Issue.record("status \(status): expected .rejected, posted clean")
            } catch SyncExportError.rejected {
                // Expected: timeouts, back-pressure, and server errors retry.
            } catch {
                Issue.record("status \(status): expected .rejected, got \(error)")
            }
        }
        URLProtocolStub.stub(statusCode: 200, for: endpoint)
        try await URLSessionOTLPTransport(session: session).post(url: endpoint, body: Data("{}".utf8))
        URLProtocolStub.stub(error: URLError(.notConnectedToInternet), for: endpoint)
        do {
            try await URLSessionOTLPTransport(session: session).post(url: endpoint, body: Data("{}".utf8))
            Issue.record("transport error: expected .rejected, posted clean")
        } catch SyncExportError.rejected {
            // Expected: no response is transient, never poison.
        } catch {
            Issue.record("transport error: expected .rejected, got \(error)")
        }
    }

    @Test("overlapping flushes serialize: one in flight at a time")
    func overlappingFlushesSerialize() async throws {
        let transport = GatedTransport()
        defer { transport.open() }
        let endpoint = Self.endpoint
        let buffer = SyncSpanBuffer(directory: temporaryDirectory())
        let telemetry = SyncTelemetry(
            buffer: buffer,
            exporter: SyncSpanExporter(
                config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
                transport: transport
            )
        )
        // First span starts a flush that blocks inside post; the second span
        // must not start another POST while it is in flight (re-POSTing the
        // same head prefix would let the tails drop each other's spans).
        await telemetry.recordSpan(makeSpan(outcome: .success, pushed: 0, pulled: 0, conflicts: 0))
        await telemetry.recordSpan(makeSpan(outcome: .success, pushed: 1, pulled: 0, conflicts: 0))
        // Poll for the single in-flight POST (detached flush runs
        // concurrently with the test task).
        let deadline = Date().addingTimeInterval(5)
        while transport.posts < 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(transport.posts == 1)
        // Settle the held flush first: `posts` proves it started, but the
        // count below is only meaningful once it has returned. A failed
        // flush removes nothing, so no re-kick may fire — still exactly one
        // POST with both spans retained (failed flushes wait for the next
        // cycle instead of re-POSTing).
        transport.open()
        while transport.completedPosts < 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(transport.posts == 1)
        #expect(await buffer.bufferedCount == 2)
        // A later cycle drains normally through the open gate.
        transport.shouldThrow = false
        await telemetry.recordSpan(makeSpan(outcome: .success, pushed: 2, pulled: 0, conflicts: 0))
        while transport.completedPosts < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(transport.posts == 2)
        #expect(await buffer.bufferedCount == 0)
    }

    @Test("drain progress with remainder re-kicks exactly once")
    func drainProgressRekicksOnce() async throws {
        let endpoint = Self.endpoint
        let buffer = SyncSpanBuffer(directory: temporaryDirectory())
        let transport = MidFlushAppendTransport(
            buffer: buffer,
            extra: makeSpan(outcome: .success, pushed: 9, pulled: 0, conflicts: 0)
        )
        let telemetry = SyncTelemetry(
            buffer: buffer,
            exporter: SyncSpanExporter(
                config: SyncTelemetryConfig(isEnabled: true, endpoint: endpoint),
                transport: transport
            )
        )
        await telemetry.recordSpan(makeSpan(outcome: .success, pushed: 1, pulled: 0, conflicts: 0))
        // First flush reads 1 span; the extra lands mid-POST; the prefix is
        // dropped (proven removal) with 1 span remaining → exactly one
        // follow-up flush forwards it, then quiet (no re-POST loop: the
        // second flush drains everything and stops on the empty buffer).
        let deadline = Date().addingTimeInterval(5)
        while transport.posts < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(transport.posts == 2)
        #expect(await buffer.bufferedCount == 0)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(transport.posts == 2)
    }
}
