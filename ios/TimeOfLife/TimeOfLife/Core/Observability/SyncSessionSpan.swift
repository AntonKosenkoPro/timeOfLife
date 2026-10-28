import Foundation

/// Outcome of one `SyncController` cycle (the `sync.session` span).
enum SyncSessionOutcome: String, Codable, Sendable {
    /// The cycle drained and pulled cleanly.
    case success
    /// The cycle ran and failed (relay error, push conflict unresolvable, …).
    case failed
    /// The cycle never ran: no connectivity at cycle entry.
    case offline
    /// The cycle never completed: account change, fence, or cancellation.
    case aborted
}

/// Counter snapshot for one finished cycle (input to `SyncSessionSpan.build`).
/// Counts and depths only — this type has no field that could hold user
/// content, which is what makes the span builder PII-safe by construction.
struct SyncSessionSpanCounts: Sendable, Equatable {
    var offlineDurationMs = 0
    var pushed = 0
    var pulled = 0
    var conflicts = 0
    var depthBefore = 0
    var depthAfter = 0
}
/// One session-level sync span (observability Stage 1, D5: hand-rolled over
/// OTLP/HTTP, no OTel Swift SDK).
///
/// Counts and durations ONLY — never entry text, category names, user ids,
/// tokens, or error details (server messages can echo user content, so even
/// failure reasons stay out; the outcome enum is the whole error signal).
struct SyncSessionSpan: Codable, Sendable, Equatable {
    static let spanName = "sync.session"

    var traceID: String
    var spanID: String
    var name: String
    var startNanos: UInt64
    var endNanos: UInt64
    var outcome: SyncSessionOutcome
    var wallDurationMs: Int
    var offlineDurationMs: Int
    var pushedCount: Int
    var pulledCount: Int
    var conflictCount: Int
    var outboxDepthBefore: Int
    var outboxDepthAfter: Int

    /// Builds a span for a finished cycle. IDs are random per span (no
    /// propagation in Stage 1); `end` at or after `start` is assumed.
    static func build(
        start: Date,
        end: Date,
        outcome: SyncSessionOutcome,
        counts: SyncSessionSpanCounts
    ) -> SyncSessionSpan {
        let startNanos = nanos(start)
        let endNanos = max(nanos(end), startNanos)
        return SyncSessionSpan(
            traceID: hexID(byteCount: 16),
            spanID: hexID(byteCount: 8),
            name: spanName,
            startNanos: startNanos,
            endNanos: endNanos,
            outcome: outcome,
            wallDurationMs: Int((endNanos - startNanos) / 1_000_000),
            offlineDurationMs: max(0, counts.offlineDurationMs),
            pushedCount: max(0, counts.pushed),
            pulledCount: max(0, counts.pulled),
            conflictCount: max(0, counts.conflicts),
            outboxDepthBefore: max(0, counts.depthBefore),
            outboxDepthAfter: max(0, counts.depthAfter)
        )
    }

    private static func nanos(_ date: Date) -> UInt64 {
        UInt64(date.timeIntervalSince1970 * 1_000_000_000)
    }

    private static func hexID(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0 ... 255)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
