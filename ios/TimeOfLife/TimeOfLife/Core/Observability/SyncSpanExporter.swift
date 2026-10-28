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
        #if DEBUG
        let isEnabled = raw != "0"
        #else
        let isEnabled = raw == "1"
        #endif
        return SyncTelemetryConfig(isEnabled: isEnabled, endpoint: endpoint(apiBaseURL: apiBaseURL))
    }

    private static func endpoint(apiBaseURL: URL) -> URL {
        if let overrideRaw = Bundle.main.object(forInfoDictionaryKey: "OTEL_EXPORTER_OTLP_ENDPOINT") as? String,
           let overrideURL = URL(string: overrideRaw),
           overrideURL.scheme != nil, overrideURL.host != nil {
            return overrideURL
        }
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

/// `URLSession` OTLP/HTTP transport: POSTs `application/json`, treats any
/// non-2xx as failure (the buffer keeps the spans for the next flush).
struct URLSessionOTLPTransport: OTLPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func post(url: URL, body: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw SyncExportError.rejected
        }
    }
}

enum SyncExportError: Error, Equatable, Sendable {
    case rejected
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

    /// Sends everything buffered, in order. Returns true when there is
    /// nothing left to send (empty buffer counts as success and posts
    /// nothing). On failure the buffer is untouched for the next attempt.
    /// At-least-once: only the prefix read for this flush is removed.
    func flush(buffer: SyncSpanBuffer) async -> Bool {
        let spans = await buffer.spans()
        guard !spans.isEmpty else { return true }
        let dropped = await buffer.droppedSpans
        do {
            try await transport.post(url: config.endpoint, body: Self.otlpPayload(spans: spans, droppedSpans: dropped))
        } catch {
            logger.error("sync span export failed; spans stay buffered")
            return false
        }
        await buffer.dropFirst(spans.count)
        return true
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
