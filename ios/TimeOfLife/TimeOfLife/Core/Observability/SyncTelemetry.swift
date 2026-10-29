import Foundation

/// Owns the iOS side of Stage-1 telemetry (tasks 6.1–6.3): the span buffer,
/// the OTLP exporter, and the consecutive-failure distress streak.
///
/// - Recording a span always buffers first and forwards best-effort when the
///   export flag is on; a failed flush keeps the spans (offline soak).
/// - Distress is separate from volume: `recordFailure` counts consecutive
///   failed cycles and fires `onDistress` (Sentry — the channel that does
///   not depend on the relay) when the streak reaches `distressThreshold`.
///   The streak resets on any success, and distress fires once per streak.
/// - No user-facing surface and no `LocalStore` writes: telemetry reads only.
@MainActor
final class SyncTelemetry {
    /// Consecutive failed cycles that raise distress (spec: "N consecutive
    /// sync failures" — N is this threshold).
    static let distressThreshold = 3

    private let buffer: SyncSpanBuffer
    private let exporter: SyncSpanExporter?
    private let onDistress: @Sendable () -> Void
    private var consecutiveFailures = 0
    private var flushing = false

    init(
        buffer: SyncSpanBuffer,
        exporter: SyncSpanExporter?,
        onDistress: (@Sendable () -> Void)? = nil
    ) {
        self.buffer = buffer
        self.exporter = exporter
        self.onDistress = onDistress ?? { SentryReporter.captureSyncDistress() }
    }

    /// Live wiring: app-support buffer, resolved config, Sentry distress.
    convenience init() {
        self.init(
            buffer: SyncSpanBuffer(directory: SyncSpanBuffer.defaultDirectory()),
            exporter: SyncSpanExporter(config: SyncTelemetryConfig.resolved())
        )
    }

    /// Current consecutive-failure streak (test observability).
    var failureStreak: Int {
        consecutiveFailures
    }

    /// Buffers one finished-cycle span and flushes best-effort when export
    /// is enabled. A failed flush is silent: the spans stay buffered.
    /// Gated on export: when the exporter is off (Release default) nothing
    /// is buffered at all — no disk/battery cost for telemetry that can
    /// never drain. Distress (recordFailure/recordOffline) is ungated: it
    /// travels Sentry, never the buffer.
    func recordSpan(_ span: SyncSessionSpan) async {
        guard exporter?.isEnabled == true else { return }
        await buffer.append(span)
        // Detached: a slow/blackholed Collector must never hold the sync
        // cycle's single-flight flag or delay the user-visible status.
        flushSoon()
    }

    /// Best-effort forward with a single-flush guarantee: overlapping
    /// flushes would re-POST the same head prefix and then drop spans
    /// appended after the slower read — silent, unreported loss. At most
    /// one flush runs at a time; a completed flush that left spans behind
    /// (appended mid-flight) re-kicks while the buffer is non-empty, and a
    /// failed flush waits for the next cycle.
    private func flushSoon() {
        guard !flushing, let exporter, exporter.isEnabled else { return }
        flushing = true
        Task.detached { [exporter, buffer] in
            let ok = await exporter.flush(buffer: buffer)
            await self.didFinishFlush(flushed: ok, buffer: buffer)
        }
    }

    private func didFinishFlush(flushed: Bool, buffer: SyncSpanBuffer) async {
        flushing = false
        guard flushed, await buffer.bufferedCount > 0 else { return }
        flushSoon()
    }

    /// A cycle succeeded: the distress streak resets.
    func recordSuccess() {
        consecutiveFailures = 0
    }

    /// A cycle was skipped for lack of connectivity: expected for a
    /// local-first app, never distress. The span still records the gap;
    /// the Sentry streak (relay-outage signal) stays untouched.
    func recordOffline() {}

    /// A cycle failed: the streak grows, firing distress once per streak.
    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures == Self.distressThreshold {
            onDistress()
        }
    }

    /// Flushes the buffer when export is on (serialized: one flush at a
    /// time; a skipped flush is safe because the buffer persists).
    func flushIfEnabled() async {
        guard let exporter, exporter.isEnabled, !flushing else { return }
        flushing = true
        defer { flushing = false }
        _ = await exporter.flush(buffer: buffer)
    }
}
