import Foundation
import OSLog

/// Resolved OTLP/HTTP endpoint + enable flag (observability Stage 1, 6.2).
///
/// - Default OFF in Release, default ON in Debug (simulator shares the host
///   network, so `localhost:4318` reaches a Collector on the dev machine).
/// - Runtime override via Info.plist `OTEL_ENABLED` (`"1"` forces on,
///   `"0"` forces off in any config); the key is optional and unread when
///   absent, so no plist/xcconfig change is needed.
/// - Endpoint override via Info.plist `OTEL_EXPORTER_OTLP_ENDPOINT`
///   (a full `…/v1/traces` URL); otherwise derived from the relay host:
///   same host as `API_BASE_URL`, port 4318, path `/v1/traces` (the Collector
///   rides next to the relay per D1, so the relay host config owns it).
struct SyncTelemetryConfig: Sendable, Equatable {
    var isEnabled: Bool
    var endpoint: URL

    static let otlpTracesPath = "/v1/traces"
    private static let collectorPort = 4_318

    static func resolved(apiBaseURL: URL = AppConfig.baseURL) -> SyncTelemetryConfig {
        let raw = Bundle.main.object(forInfoDictionaryKey: "OTEL_ENABLED") as? String
        let overrideRaw = Bundle.main.object(forInfoDictionaryKey: "OTEL_EXPORTER_OTLP_ENDPOINT") as? String
        let override = Self.parsedOverride(overrideRaw)
        #if DEBUG
        let isEnabled = enabled(raw: raw, override: override, debug: true)
        #else
        let isEnabled = enabled(raw: raw, override: override, debug: false)
        #endif
        return SyncTelemetryConfig(isEnabled: isEnabled, endpoint: override ?? derivedEndpoint(apiBaseURL: apiBaseURL))
    }

    /// Parses the `OTEL_EXPORTER_OTLP_ENDPOINT` override the same way the
    /// endpoint derivation does — nil unless it is a usable http(s) URL
    /// with a host. Single source of truth for "usable override", shared by
    /// derivation and the enablement rule below.
    static func parsedOverride(_ raw: String?) -> URL? {
        guard let raw,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    /// Pure enablement rule (testable without a bundle): Debug defaults on
    /// (simulator shares the host network); Release requires an explicit
    /// endpoint — deriving `https://<relay-host>:4318` would emit an
    /// unusable URL (the Collector only exposes plaintext 4318 on the
    /// compose network; TLS terminates at nginx on 443), so without a
    /// parseable override Release stays off rather than failing every
    /// flush silently.
    static func enabled(raw: String?, override: URL?, debug: Bool) -> Bool {
        if debug {
            return raw != "0"
        }
        return raw == "1" && override != nil
    }

    private static func derivedEndpoint(apiBaseURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = apiBaseURL.scheme
        components.host = apiBaseURL.host
        components.port = collectorPort
        components.path = otlpTracesPath
        return components.url ?? apiBaseURL.appendingPathComponent("v1/traces")
    }
}

/// Minimal OTLP/HTTP transport seam (task 6.2). The live implementation
/// POSTs JSON; tests inject a stub to prove offline soak without a network.
protocol OTLPTransport: Sendable {
    func post(url: URL, body: Data) async throws
}

/// `URLSession` OTLP/HTTP transport: POSTs `application/json`, mapping
/// permanent rejections (4xx) separately from transient failures so the
/// exporter can drop poison batches instead of retrying them forever.
/// Short request timeout: telemetry must never gate the sync cycle.
struct URLSessionOTLPTransport: OTLPTransport {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func post(url: URL, body: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SyncExportError.rejected
            }
            switch http.statusCode {
            case 200 ... 299:
                return
            case 400, 401, 403, 404, 405, 413, 415, 422:
                // Permanent payload/config rejections: re-POSTing the same batch
                // can never succeed (wrong path, rejected credential, oversize or
                // unprocessable body). Without these, a 404/401 wedges the buffer
                // forever and the counted loss can never be reported, since
                // reporting itself requires a successful flush. 408/425/429 stay
                // transient: timeouts and back-pressure must retry, not discard.
                throw SyncExportError.permanent(status: http.statusCode)
            default:
                throw SyncExportError.rejected
            }
        } catch {
            // Total contract: every failure out of this transport is a
            // `SyncExportError`. Session-thrown errors (offline, timeouts,
            // TLS) mean the batch was never evaluated — transient by
            // definition, so they must retry, never quarantine.
            throw (error as? SyncExportError) ?? SyncExportError.rejected
        }
    }
}

enum SyncExportError: Error, Equatable, Sendable {
    /// Transient: timeouts, 5xx, transport failures — keep buffering, retry.
    case rejected
    /// Permanent: the batch itself is unacceptable (4xx) — retrying forever
    /// wedges the buffer, so the caller drops/quarantines it instead.
    case permanent(status: Int)
}

/// Forwards buffered `sync.session` spans to the Collector over OTLP/HTTP
/// (JSON). Spans stay buffered until a flush succeeds (offline soak); the
/// buffer cap still bounds growth while offline.
final class SyncSpanExporter: Sendable {
    private static let serviceName = "lifio-ios"
    private static let scopeName = "lifio-sync"

    private let config: SyncTelemetryConfig
    private let transport: any OTLPTransport
    private let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "SyncSpanExporter"
    )

    init(config: SyncTelemetryConfig, transport: any OTLPTransport = URLSessionOTLPTransport()) {
        self.config = config
        self.transport = transport
    }

    var isEnabled: Bool {
        config.isEnabled
    }

    var endpoint: URL {
        config.endpoint
    }

    /// Sends everything buffered, in order. On transient failure the buffer is
    /// untouched for the next attempt. On permanent rejection the batch is
    /// quarantined with a log line: re-POSTing poison forever would wedge
    /// the buffer at the cap and hide every later span behind an
    /// un-exportable `dropped_spans` count.
    /// At-least-once: only the prefix read for this flush is removed.
    ///
    /// Returns how many buffered spans this flush removed. The re-kick
    /// decision keys off *proven removal* (removed > 0): spans appended
    /// mid-flight are picked up by the re-kick instead of waiting for the
    /// next cycle, while a POST that removed nothing (transient failure, or
    /// a failed file write behind the drop) never triggers an immediate
    /// re-POST loop. An append landing exactly between the pre-drop and
    /// post-drop reads undercounts by one; that span waits for the next
    /// recordSpan (bounded staleness, never loss).
    func flush(buffer: SyncSpanBuffer) async -> Int {
        let spans = await buffer.spans()
        guard !spans.isEmpty else { return 0 }
        let dropped = await buffer.droppedSpans
        var quarantined = 0
        do {
            try await transport.post(url: config.endpoint, body: Self.otlpPayload(spans: spans, droppedSpans: dropped))
        } catch let SyncExportError.permanent(status) {
            logger.error("sync span export permanently rejected (status \(status)); quarantining batch")
            quarantined = spans.count
        } catch {
            logger.error("sync span export failed; spans stay buffered")
            return 0
        }
        // Count AFTER the POST: appends that landed mid-flight are part of
        // the file now, so `beforeDrop - after` measures proven removal —
        // unlike `spans.count - after`, which reads 0 when an append exactly
        // offsets the drained prefix and would strand that span.
        let beforeDrop = await buffer.bufferedCount
        await buffer.dropFirst(spans.count)
        if quarantined > 0 {
            // Count the dropped batch as loss: it was never observed by the
            // backend, so the next successful flush must still report it.
            // (Acknowledging here would erase the only loss signal for data
            // the SaaS never saw.)
            await buffer.addDropped(quarantined)
        } else {
            // Delta semantics: only loss the SaaS never saw stays counted.
            // Drops concurrent with this flush (appended while POSTing) survive.
            await buffer.acknowledgeDropped(dropped)
        }
        let after = await buffer.bufferedCount
        return max(0, beforeDrop - after)
    }

    /// Builds the OTLP/HTTP JSON body. Attribute keys are a fixed allowlist
    /// (counts/durations only — the cardinality rule); no identifiers, tokens,
    /// entry text, or category names anywhere in the payload.
    static func otlpPayload(spans: [SyncSessionSpan], droppedSpans: Int) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let resource = EncodedResource(
            resource: EncodedResourceInner(attributes: [
                EncodedAttribute(key: "service.name", value: .string(serviceName)),
                EncodedAttribute(key: "dropped_spans", value: .int(droppedSpans)),
            ]),
            scopeSpans: [
                EncodedScopeSpans(
                    scope: EncodedScope(name: scopeName),
                    spans: spans.map(EncodedSpan.init)
                ),
            ]
        )
        // The shape is fixed and encoder-built; a failed encode means a
        // programmer error, and an empty body must never be posted.
        guard let data = try? encoder.encode(EncodedTracePayload(resourceSpans: [resource])),
              !data.isEmpty
        else {
            return Data("{\"resourceSpans\":[]}".utf8)
        }
        return data
    }
}

private struct EncodedTracePayload: Encodable {
    var resourceSpans: [EncodedResource]
}

private struct EncodedResource: Encodable {
    var resource: EncodedResourceInner
    var scopeSpans: [EncodedScopeSpans]
}

private struct EncodedResourceInner: Encodable {
    var attributes: [EncodedAttribute]
}

private struct EncodedScopeSpans: Encodable {
    var scope: EncodedScope
    var spans: [EncodedSpan]
}

private struct EncodedScope: Encodable {
    var name: String
}

private struct EncodedSpan: Encodable {
    var traceId: String
    var spanId: String
    var name: String
    var kind: Int
    var startTimeUnixNano: String
    var endTimeUnixNano: String
    var attributes: [EncodedAttribute]
    var status: EncodedStatus

    init(_ span: SyncSessionSpan) {
        self.traceId = span.traceID
        self.spanId = span.spanID
        self.name = SyncSessionSpan.spanName
        self.kind = 1
        self.startTimeUnixNano = String(span.startNanos)
        self.endTimeUnixNano = String(span.endNanos)
        self.attributes = [
            EncodedAttribute(key: "sync.outcome", value: .string(span.outcome.rawValue)),
            EncodedAttribute(key: "sync.wall_duration_ms", value: .int(span.wallDurationMs)),
            EncodedAttribute(key: "sync.offline_duration_ms", value: .int(span.offlineDurationMs)),
            EncodedAttribute(key: "sync.pushed", value: .int(span.pushedCount)),
            EncodedAttribute(key: "sync.pulled", value: .int(span.pulledCount)),
            EncodedAttribute(key: "sync.conflicts", value: .int(span.conflictCount)),
            EncodedAttribute(key: "sync.outbox_depth_before", value: .int(span.outboxDepthBefore)),
            EncodedAttribute(key: "sync.outbox_depth_after", value: .int(span.outboxDepthAfter)),
        ]
        switch span.outcome {
        case .failed:
            self.status = EncodedStatus(code: 2)
        case .success, .offline, .aborted:
            self.status = EncodedStatus(code: 0)
        }
    }
}

private struct EncodedStatus: Encodable {
    var code: Int
}

private struct EncodedAttribute: Encodable {
    var key: String
    var value: EncodedAttributeValue
}

private enum EncodedAttributeValue: Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(value, forKey: .stringValue)
        case let .int(value):
            try container.encode(String(value), forKey: .intValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case stringValue
        case intValue
    }
}
