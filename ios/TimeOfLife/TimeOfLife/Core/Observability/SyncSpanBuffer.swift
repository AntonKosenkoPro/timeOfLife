import Foundation
import OSLog

/// File-backed, bounded, order-preserving buffer for `SyncSessionSpan`s
/// (observability Stage 1, task 6.1: buffer-and-forward).
///
/// - Format: JSON-lines, one span per line (append-only; drained in order).
/// - Location: `<Application Support>/telemetry/sync-spans.jsonl` — OUTSIDE
///   the per-account database file. Telemetry is not user data: `LocalStore`
///   stays the only mutation chokepoint and this buffer never touches it.
/// - Bound: `maxSpans` lines (default 200). Past the cap the INCOMING span
///   drops (classic tail-drop: the oldest buffered spans are the ones most
///   likely to still forward) and the persisted `droppedSpans` counter
///   increments, so loss is visible instead of silent.
/// - Errors are swallowed with a log line: telemetry must never fail sync.
actor SyncSpanBuffer {
    static let defaultMaxSpans = 200
    private static let fileName = "sync-spans.jsonl"
    private static let counterFileName = "sync-spans.dropped"

    private let fileURL: URL
    private let counterURL: URL
    private let maxSpans: Int
    private let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "SyncSpanBuffer"
    )

    init(directory: URL, maxSpans: Int = defaultMaxSpans) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        self.counterURL = directory.appendingPathComponent(Self.counterFileName)
        self.maxSpans = max(1, maxSpans)
    }

    /// App-wide buffer location (outside the account DB — see above).
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("telemetry", isDirectory: true)
    }

    /// Appends one span; tail-drops (with counting) past the cap.
    func append(_ span: SyncSessionSpan) {
        var spans = storedSpans()
        guard spans.count < maxSpans else {
            setDroppedSpans(droppedSpans + 1)
            logger.info("sync span buffer full; tail-dropped span (total dropped=\(self.droppedSpans, privacy: .public))")
            return
        }
        spans.append(span)
        writeLines(spans)
    }

    /// Spans in append order (oldest first — the forward order).
    func spans() -> [SyncSessionSpan] {
        storedSpans()
    }

    /// Number of lines currently buffered.
    var bufferedCount: Int {
        storedSpans().count
    }

    /// Cumulative tail-dropped spans (persisted in a sidecar file so the
    /// count survives restarts; the exporter ships it as `dropped_spans`).
    var droppedSpans: Int {
        guard let raw = try? String(contentsOf: counterURL, encoding: .utf8) else { return 0 }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Removes the first `count` lines (what a successful flush just sent).
    /// At-least-once: concurrent appends during a flush land after the
    /// removed prefix, so nothing unsent is ever cleared.
    func dropFirst(_ count: Int) {
        guard count > 0 else { return }
        let remaining = Array(storedSpans().dropFirst(count))
        writeLines(remaining)
    }

    /// Records spans lost without ever being reported (e.g. a permanently
    /// rejected batch): they join the dropped total the next successful
    /// flush reports, so loss stays visible instead of silent.
    func addDropped(_ count: Int) {
        guard count > 0 else { return }
        setDroppedSpans(droppedSpans + count)
    }

    /// Delta-acknowledges exported loss: call after a flush reported
    /// `count` dropped spans to the Collector. Drops that happened
    /// concurrently with the flush survive (they were never reported).
    func acknowledgeDropped(_ count: Int) {
        guard count > 0 else { return }
        setDroppedSpans(max(0, droppedSpans - count))
    }

    /// Clears the whole buffer (used after a fully-sent flush).
    func clear() {
        writeLines([])
    }

    private func setDroppedSpans(_ count: Int) {
        ensureDirectory()
        do {
            try String(count).write(to: counterURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("sync span buffer: dropped-counter write failed")
        }
    }

    private func storedSpans() -> [SyncSessionSpan] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        var spans: [SyncSessionSpan] = []
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let span = try? decoder.decode(SyncSessionSpan.self, from: lineData)
            else {
                logger.error("sync span buffer: skipping undecodable line")
                continue
            }
            spans.append(span)
        }
        return spans
    }

    private func writeLines(_ spans: [SyncSessionSpan]) {
        ensureDirectory()
        let encoder = JSONEncoder()
        var text = ""
        for span in spans {
            guard let data = try? encoder.encode(span),
                  let line = String(data: data, encoding: .utf8)
            else {
                logger.error("sync span buffer: span encode failed; dropping it")
                continue
            }
            text.append(line)
            text.append("\n")
        }
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("sync span buffer: write failed")
        }
    }

    private func ensureDirectory() {
        let directory = fileURL.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
