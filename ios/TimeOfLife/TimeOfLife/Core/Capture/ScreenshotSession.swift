// swiftlint:disable file_length
#if DEBUG || SCREENSHOT_CAPTURE
import Foundation

/// Session command envelope (protocol freeze `evidence/protocol.md` v2).
///
/// The outer envelope carries `request_json` as an EXACT UTF-8 string: the
/// app hashes THOSE bytes (`sha256(request_json.utf8)`) and parses them
/// with the existing request loader. Swift never re-encodes the payload,
/// so Unicode/slashes/floats cannot drift between the Python canonical
/// bytes and the app hash. Outer metadata alone never changes the payload
/// hash; every ack binds the full tuple instead.
struct ScreenshotSessionEnvelope: Equatable {
    let runID: String
    let nonce: String
    let domain: ScreenshotSessionDomain
    let seq: Int
    let frame: ScreenshotFrame
    let mode: ScreenshotMode
    let requestSHA256: String
    let requestJSON: String
    let request: ScreenshotCaptureRequest
}

/// Capture clock domains for a session: pinned app screens vs the separate
/// real-time Live Activity session (design §3). Raw values are the exact
/// `session_domain` strings.
enum ScreenshotSessionDomain: String, Codable {
    case pinned
    case realtime

    var mode: ScreenshotMode {
        switch self {
        case .pinned: return .appClockPinned
        case .realtime: return .liveActivityRealtime
        }
    }

    /// Ordered story for the domain (spec: four pinned frames, then a
    /// separate real-time session for the three LA states).
    var storyFrames: [ScreenshotFrame] {
        switch self {
        case .pinned: return [.trackRunning, .insights, .history, .addEntry]
        case .realtime: return [.laLock, .laCompact, .laExpanded]
        }
    }
}

/// One accepted command, echoed in every state ack and the cleanup receipt
/// so a fresh process can re-verify the transcript (spec: session cleanup
/// gates every dependent frame). The semantic hash excludes volatile
/// payload fields (run_id) so r1/r2 comparison recognizes the same intended
/// frame across fresh volatile identities.
struct ScreenshotSessionTranscriptEntry: Codable, Equatable {
    var seq: Int
    var frame: String
    var requestSHA256: String
    var requestSemanticSHA256: String

    enum CodingKeys: String, CodingKey {
        case seq, frame
        case requestSHA256 = "request_sha256"
        case requestSemanticSHA256 = "request_semantic_sha256"
    }
}

/// Deterministic JSON canonicalization matching the runner builder exactly:
/// sorted keys (Unicode code-point order), compact separators, raw UTF-8
/// (no ASCII armoring), CPython string escaping, trailing newline. The
/// exact-hash rule still hashes the TRANSMITTED bytes; this canonicalizer
/// exists only for the semantic projection (volatile fields excluded),
/// which the golden fixture pins cross-language.
enum ScreenshotCanonicalJSON {
    /// Canonical bytes for a parsed JSON value (object/array/scalar).
    static func canonicalBytes(_ value: Any) throws -> Data {
        var out = Data()
        try appendCanonical(value, to: &out)
        out.append(0x0A)
        return out
    }

    /// Semantic bytes: the payload object minus volatile run_id.
    static func semanticBytes(_ payload: [String: Any]) throws -> Data {
        var projected = payload
        projected.removeValue(forKey: "run_id")
        return try canonicalBytes(projected)
    }

    static func semanticSHA256Hex(_ payload: [String: Any]) throws -> String {
        ScreenshotRequestLoader.sha256Hex(try semanticBytes(payload))
    }

    private static func appendCanonical(_ value: Any, to out: inout Data) throws {
        switch value {
        case let dict as [String: Any]:
            try appendObject(dict, to: &out)
        case let array as [Any]:
            try appendArray(array, to: &out)
        case let string as String:
            appendString(string, to: &out)
        case let number as NSNumber: // swiftlint:disable:this legacy_objc_type
            try appendNumber(number, to: &out)
        case is NSNull:
            out.append(contentsOf: "null".utf8)
        default:
            throw ScreenshotRequestError(code: "invalid-json", detail: "Canonicalization met an unsupported value.")
        }
    }

    private static func appendObject(_ dict: [String: Any], to out: inout Data) throws {
        out.append(0x7B) // {
        for (index, key) in dict.keys.sorted(by: codePointOrdered).enumerated() {
            if index > 0 { out.append(0x2C) } // ,
            appendString(key, to: &out)
            out.append(0x3A) // :
            guard let element = dict[key] else {
                throw ScreenshotRequestError(code: "invalid-json", detail: "Canonicalization met a missing value.")
            }
            try appendCanonical(element, to: &out)
        }
        out.append(0x7D) // }
    }

    private static func appendArray(_ array: [Any], to out: inout Data) throws {
        out.append(0x5B) // [
        for (index, element) in array.enumerated() {
            if index > 0 { out.append(0x2C) }
            try appendCanonical(element, to: &out)
        }
        out.append(0x5D) // ]
    }

    /// Code-point order (Python `sorted` on str). Swift's default string
    /// ordering is canonical-equivalence-aware and MUST NOT be used here.
    static func codePointOrdered(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars)
    }

    /// CPython `ensure_ascii=False` escaping: `"`, `\`, short forms for
    /// \b \t \n \f \r, `\u00XX` for other C0 controls, raw UTF-8 otherwise.
    /// (ObjC types below are JSONSerialization interop: Bool/NSNull
    /// discrimination needs ObjC identity — Swift `as Bool` bridging would
    /// misclassify integers.)
    static func appendString(_ value: String, to out: inout Data) {
        out.append(0x22) // "
        for scalar in value.unicodeScalars {
            appendScalar(scalar, to: &out)
        }
        out.append(0x22) // "
    }

    private static func appendScalar(_ scalar: Unicode.Scalar, to out: inout Data) {
        switch scalar.value {
        case 0x22: out.append(contentsOf: "\\\"".utf8)
        case 0x5C: out.append(contentsOf: "\\\\".utf8)
        case 0x08: out.append(contentsOf: "\\b".utf8)
        case 0x09: out.append(contentsOf: "\\t".utf8)
        case 0x0A: out.append(contentsOf: "\\n".utf8)
        case 0x0C: out.append(contentsOf: "\\f".utf8)
        case 0x0D: out.append(contentsOf: "\\r".utf8)
        case 0x00...0x1F:
            out.append(contentsOf: "\\u00".utf8)
            let hex = String(scalar.value, radix: 16, uppercase: false)
            out.append(contentsOf: String(repeating: "0", count: 2 - hex.count).utf8)
            out.append(contentsOf: hex.utf8)
        default:
            out.append(contentsOf: String(scalar).utf8)
        }
    }

    // NSNumber is JSONSerialization interop (see appendCanonical): Bool
    // discrimination needs ObjC identity — Swift bridging would misclassify.
    private static func appendNumber(_ number: NSNumber, to out: inout Data) throws { // swiftlint:disable:this legacy_objc_type
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            out.append(contentsOf: (number.boolValue ? "true" : "false").utf8)
            return
        }
        // Schema payloads carry integers only (pins, counts, seconds).
        // Anything else fails closed here rather than emitting bytes that
        // could false-match across languages.
        switch CFNumberGetType(number) {
        case .charType, .shortType, .intType, .longType, .longLongType,
             .nsIntegerType, .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type:
            out.append(contentsOf: "\(number.int64Value)".utf8)
        default:
            throw ScreenshotRequestError(code: "invalid-json", detail: "Canonicalization met a non-integer number.")
        }
    }
}

enum ScreenshotSessionEnvelopeLoader {
    static let schemaVersion = 2

    struct Identity {
        let runID: String
        let nonce: String
        let domain: ScreenshotSessionDomain
        let seq: Int
    }

    struct FrameBinding {
        let frame: ScreenshotFrame
        let mode: ScreenshotMode
    }

    /// Validates an envelope file's exact bytes. Outer/inner run, frame,
    /// and mode must agree; the 7-frame story list stays immutable.
    static func parse(data: Data) throws -> ScreenshotSessionEnvelope {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any]
        else {
            throw ScreenshotRequestError(code: "invalid-json", detail: "Session envelope is not a JSON object.")
        }
        let schema = try integral(dict, key: "schema_version")
        guard schema == schemaVersion else {
            throw ScreenshotRequestError(code: "unsupported-schema", detail: "schema_version must be 2.")
        }
        let identity = try parseIdentity(dict)
        let binding = try parseFrameBinding(dict, domain: identity.domain)
        let (requestJSON, digest) = try parseHashBinding(dict)
        let request = try ScreenshotRequestLoader.parse(data: Data(requestJSON.utf8))
        guard request.runID == identity.runID, request.frame == binding.frame, request.mode == binding.mode else {
            throw ScreenshotRequestError(code: "outer-inner-mismatch", detail: "Envelope run/frame/mode differ from the embedded request.")
        }
        return ScreenshotSessionEnvelope(
            runID: identity.runID,
            nonce: identity.nonce,
            domain: identity.domain,
            seq: identity.seq,
            frame: binding.frame,
            mode: binding.mode,
            requestSHA256: digest,
            requestJSON: requestJSON,
            request: request
        )
    }

    private static func parseIdentity(_ dict: [String: Any]) throws -> Identity {
        let runID = try string(dict, key: "run_id")
        try ScreenshotSessionPaths.validateRunID(runID)
        let nonce = try string(dict, key: "session_nonce")
        try ScreenshotSessionPaths.validateNonce(nonce)
        let domainRaw = try string(dict, key: "session_domain")
        guard let domain = ScreenshotSessionDomain(rawValue: domainRaw) else {
            throw ScreenshotRequestError(code: "unknown-domain", detail: "Unknown session_domain '\(domainRaw)'.")
        }
        let seq = try integral(dict, key: "seq")
        guard seq >= 0 else {
            throw ScreenshotRequestError(code: "bad-seq", detail: "seq must be a non-negative integer.")
        }
        return Identity(runID: runID, nonce: nonce, domain: domain, seq: seq)
    }

    private static func parseFrameBinding(_ dict: [String: Any], domain: ScreenshotSessionDomain) throws -> FrameBinding {
        let frameRaw = try string(dict, key: "frame")
        guard let frame = ScreenshotFrame(rawValue: frameRaw) else {
            throw ScreenshotRequestError(code: "unknown-frame", detail: "Unknown frame '\(frameRaw)'.")
        }
        let modeRaw = try string(dict, key: "mode")
        guard let mode = ScreenshotMode(rawValue: modeRaw) else {
            throw ScreenshotRequestError(code: "unknown-mode", detail: "Unknown mode '\(modeRaw)'.")
        }
        guard (mode == .liveActivityRealtime) == frame.requiresRealtimeMode else {
            throw ScreenshotRequestError(code: "mode-mismatch", detail: "Mode '\(modeRaw)' does not match frame '\(frameRaw)'.")
        }
        guard domain.mode == mode, domain.storyFrames.contains(frame) else {
            throw ScreenshotRequestError(code: "wrong-domain", detail: "Frame '\(frameRaw)' does not belong to the '\(domain.rawValue)' session domain.")
        }
        return FrameBinding(frame: frame, mode: mode)
    }

    private static func parseHashBinding(_ dict: [String: Any]) throws -> (String, String) {
        let requestJSON = try string(dict, key: "request_json")
        let digest = try string(dict, key: "request_sha256")
        guard isLowerHex64(digest) else {
            throw ScreenshotRequestError(code: "sha-mismatch", detail: "request_sha256 must be 64 lower-hex characters.")
        }
        let computed = ScreenshotRequestLoader.sha256Hex(Data(requestJSON.utf8))
        guard computed == digest else {
            throw ScreenshotRequestError(code: "sha-mismatch", detail: "request_sha256 does not match the exact request_json bytes.")
        }
        return (requestJSON, digest)
    }

    /// Builds an outer envelope around canonical payload bytes (test helper
    /// mirroring the runner builder: same sorted-keys + trailing-NL bytes).
    /// Strict: the payload must already validate and agree with the envelope.
    static func makeOuter(
        payload: Data,
        runID: String,
        nonce: String,
        domain: ScreenshotSessionDomain,
        seq: Int
    ) throws -> Data {
        try ScreenshotSessionPaths.validateRunID(runID)
        try ScreenshotSessionPaths.validateNonce(nonce)
        guard seq >= 0 else {
            throw ScreenshotRequestError(code: "bad-seq", detail: "seq must be a non-negative integer.")
        }
        guard let payloadString = String(data: payload, encoding: .utf8), !payloadString.isEmpty else {
            throw ScreenshotRequestError(code: "invalid-json", detail: "Payload is not UTF-8 text.")
        }
        let inner = try ScreenshotRequestLoader.parse(data: payload)
        guard inner.runID == runID else {
            throw ScreenshotRequestError(code: "outer-inner-mismatch", detail: "Payload run_id differs from the envelope run_id.")
        }
        guard domain.mode == inner.mode, domain.storyFrames.contains(inner.frame) else {
            throw ScreenshotRequestError(code: "wrong-domain", detail: "Payload frame does not belong to the envelope domain.")
        }
        let outer: [String: Any] = [
            "schema_version": schemaVersion,
            "run_id": runID,
            "session_nonce": nonce,
            "session_domain": domain.rawValue,
            "seq": seq,
            "frame": inner.frame.rawValue,
            "mode": inner.mode.rawValue,
            "request_sha256": ScreenshotRequestLoader.sha256Hex(payload),
            "request_json": payloadString,
        ]
        let bytes = try JSONSerialization.data(withJSONObject: outer, options: [.sortedKeys])
        return bytes + Data("\n".utf8)
    }

    private static func string(_ dict: [String: Any], key: String) throws -> String {
        guard let value = dict[key] as? String, !value.isEmpty else {
            throw ScreenshotRequestError(code: "missing-field", detail: "Missing or empty required field '\(key)'.")
        }
        return value
    }

    private static func integral(_ dict: [String: Any], key: String) throws -> Int {
        if let value = dict[key] as? Int { return value }
        if let value = dict[key] as? Double, value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) {
            return Int(value)
        }
        throw ScreenshotRequestError(code: "missing-field", detail: "Missing or non-integer required field '\(key)'.")
    }

    static func isLowerHex64(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.allSatisfy { $0.isHexDigit && ($0.isNumber || "abcdef".contains($0)) }
    }
}

/// Owned queue paths under Documents (no sockets/schemes/entitlements).
/// The app derives the session directory from its ACTIVE nonce — never
/// from an arbitrary path — and rejects traversal/symlink escape.
enum ScreenshotSessionPaths {
    static let rootName = "capture-sessions"
    static let queueFilename = "command.json"

    static func consumedFilename(seq: Int) -> String {
        "consumed-\(seq).json"
    }

    static func validateNonce(_ nonce: String) throws {
        guard nonce.count == 32, nonce.allSatisfy({ $0.isHexDigit && ($0.isNumber || "abcdef".contains($0)) }) else {
            throw ScreenshotRequestError(code: "unsupported-nonce", detail: "session_nonce must be 32 lower-hex characters.")
        }
    }

    static func validateRunID(_ runID: String) throws {
        let sanitized = runID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !sanitized.isEmpty, sanitized == runID else {
            throw ScreenshotRequestError(code: "invalid-run-id", detail: "run_id '\(runID)' has unsupported characters.")
        }
    }

    static func sessionDirectory(documents: URL, nonce: String) throws -> URL {
        try validateNonce(nonce)
        let dir = documents
            .appendingPathComponent(rootName, isDirectory: true)
            .appendingPathComponent(nonce, isDirectory: true)
        if isSymbolicLink(dir) {
            throw ScreenshotRequestError(code: "traversal", detail: "Session directory is a symlink; refusing escape.")
        }
        return dir
    }

    static func queueURL(documents: URL, nonce: String) throws -> URL {
        try validateNonce(nonce)
        let dir = try sessionDirectory(documents: documents, nonce: nonce)
        let queue = dir.appendingPathComponent(queueFilename)
        if isSymbolicLink(queue) {
            throw ScreenshotRequestError(code: "traversal", detail: "Queue file is a symlink; refusing escape.")
        }
        return queue
    }

    static func consumedURL(documents: URL, nonce: String, seq: Int) throws -> URL {
        let dir = try sessionDirectory(documents: documents, nonce: nonce)
        return dir.appendingPathComponent(consumedFilename(seq: seq))
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
}

/// Atomic claim: the queue file is RENAMED to its consumed record BEFORE
/// execution, so readers never observe a half-written command and a crash
/// leaves evidence. Absent queue = no-op. A new publication with an
/// already-consumed seq is a replay (even byte-identical) — no mtime/inode
/// heuristics. Staging temp files (`command.json.tmp-*`) are ignored.
enum ScreenshotSessionClaim {
    enum PollResult: Equatable {
        case empty
        case claimed(ScreenshotSessionEnvelope)
    }

    static func poll(
        documents: URL,
        nonce: String,
        consumedSeqs: Set<Int>
    ) throws -> PollResult {
        let dir: URL
        do {
            dir = try ScreenshotSessionPaths.sessionDirectory(documents: documents, nonce: nonce)
        } catch {
            return .empty
        }
        guard FileManager.default.fileExists(atPath: dir.path) else { return .empty }
        let queue = dir.appendingPathComponent(ScreenshotSessionPaths.queueFilename)
        guard FileManager.default.fileExists(atPath: queue.path) else { return .empty }
        if ScreenshotSessionPaths.isSymbolicLink(queue) {
            throw ScreenshotRequestError(code: "traversal", detail: "Queue file is a symlink; refusing escape.")
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: queue)
        } catch {
            // Read errors keep the file: it may be a transient I/O failure,
            // not a corrupt publication (mirrors the runner claim model).
            throw ScreenshotRequestError(code: "unreadable-command", detail: "Queue file unreadable: \(error).")
        }
        let envelope: ScreenshotSessionEnvelope
        do {
            envelope = try ScreenshotSessionEnvelopeLoader.parse(data: bytes)
        } catch {
            // Malformed/partial publications are removed so the session does
            // not wedge on garbage; the seq stays unconsumed and the runner
            // must republish explicitly (mirrors the runner claim model).
            try? FileManager.default.removeItem(at: queue)
            throw error
        }
        guard envelope.nonce == nonce else {
            try? FileManager.default.removeItem(at: queue)
            throw ScreenshotRequestError(code: "stale-session", detail: "Command targets another session; refusing cross-session execution.")
        }
        let consumedPath = dir.appendingPathComponent(ScreenshotSessionPaths.consumedFilename(seq: envelope.seq))
        if consumedSeqs.contains(envelope.seq) || FileManager.default.fileExists(atPath: consumedPath.path) {
            // A retained record already exists for this seq: the queue file
            // is a NEW publication of an old seq — explicit replay. The
            // retained record keeps the accepted command; the replay copy is
            // removed and the session fails closed.
            try? FileManager.default.removeItem(at: queue)
            throw ScreenshotRequestError(code: "replay", detail: "Command seq \(envelope.seq) was already consumed; refusing replay.")
        }
        do {
            try FileManager.default.moveItem(at: queue, to: consumedPath)
        } catch {
            // Lost a race with another claimer (only this session claims):
            // treat a vanished queue as nothing new, an occupied consumed
            // record as a replay.
            if FileManager.default.fileExists(atPath: consumedPath.path) {
                throw ScreenshotRequestError(code: "replay", detail: "Command seq \(envelope.seq) was already consumed; refusing replay.")
            }
            return .empty
        }
        return .claimed(envelope)
    }
}

/// In-session ordering + immutability gate. Tracks accepted commands; the
/// transcript seeds with the initial envelope and grows per validated
/// command. Only the next story frame advances; locale/fixture/clock/run
/// changes, cross-session nonces, gaps, and replays fail closed.
final class ScreenshotSessionValidator {
    let initial: ScreenshotSessionEnvelope
    private(set) var transcript: [ScreenshotSessionTranscriptEntry]
    private var lastSeq: Int
    private var lastFrame: ScreenshotFrame

    init(initial: ScreenshotSessionEnvelope) throws {
        self.initial = initial
        self.transcript = [try Self.entry(initial)]
        self.lastSeq = initial.seq
        self.lastFrame = initial.frame
    }

    static func entry(_ envelope: ScreenshotSessionEnvelope) throws -> ScreenshotSessionTranscriptEntry {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(envelope.requestJSON.utf8)),
              let dict = payload as? [String: Any]
        else {
            throw ScreenshotRequestError(code: "invalid-json", detail: "Transcript needs the parsed payload.")
        }
        return ScreenshotSessionTranscriptEntry(
            seq: envelope.seq,
            frame: envelope.frame.rawValue,
            requestSHA256: envelope.requestSHA256,
            requestSemanticSHA256: try ScreenshotCanonicalJSON.semanticSHA256Hex(dict)
        )
    }

    func validate(_ next: ScreenshotSessionEnvelope) throws {
        guard next.seq > lastSeq else {
            throw ScreenshotRequestError(code: "replay", detail: "Command seq \(next.seq) is not newer than \(lastSeq); refusing replay.")
        }
        guard next.seq == lastSeq + 1 else {
            throw ScreenshotRequestError(code: "bad-seq", detail: "Expected seq \(lastSeq + 1), got \(next.seq).")
        }
        guard next.nonce == initial.nonce else {
            throw ScreenshotRequestError(code: "stale-session", detail: "Command targets another session; refusing cross-session execution.")
        }
        guard next.domain == initial.domain else {
            throw ScreenshotRequestError(code: "wrong-domain", detail: "Command switches clock domains mid-session.")
        }
        guard next.runID == initial.runID else {
            throw ScreenshotRequestError(code: "immutable-change", detail: "Command changes the session run identity.")
        }
        let story = initial.domain.storyFrames
        guard let prevIdx = story.firstIndex(of: lastFrame),
              let nextIdx = story.firstIndex(of: next.frame),
              nextIdx == prevIdx + 1
        else {
            throw ScreenshotRequestError(code: "out-of-order", detail: "Frame '\(next.frame.rawValue)' does not follow '\(lastFrame.rawValue)'.")
        }
        guard Self.immutableMatches(initial.request, next.request) else {
            throw ScreenshotRequestError(code: "immutable-change", detail: "Command changes immutable session inputs (locale/fixture/clock).")
        }
        lastSeq = next.seq
        lastFrame = next.frame
        transcript.append(try Self.entry(next))
    }

    /// Session-immutable inputs: everything but the story frame (mode is
    /// fixed per domain and already bound by the envelope parser).
    static func immutableMatches(_ a: ScreenshotCaptureRequest, _ b: ScreenshotCaptureRequest) -> Bool {
        a.runID == b.runID
            && a.localeIdentifier == b.localeIdentifier
            && a.regionCode == b.regionCode
            && a.timeZone.identifier == b.timeZone.identifier
            && a.weekRule == b.weekRule
            && a.referenceDate == b.referenceDate
            && a.appElapsed == b.appElapsed
            && a.deckVersion == b.deckVersion
            && a.schemaVersion == b.schemaVersion
    }
}

/// Monotonic clock for capture timings. `CLOCK_MONOTONIC` never observes
/// wall-clock steps; durations here are never mixed with `Date` math and
/// never leave the capture evidence files.
enum ScreenshotSessionClock {
    static func nowNanos() -> UInt64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
    }
}

/// Phase timings + evidence counters for one session (task 2.1). Written to
/// `Documents/capture-timings.json` alongside the state ack; the runner
/// reads it for the phase breakdown. No timestamps from different clock
/// domains are ever subtracted; no request contents are logged.
struct ScreenshotSessionTimings: Codable, Equatable {
    struct Sample: Codable, Equatable {
        var phase: String
        var milliseconds: Double
        var count: Int
    }

    var samples: [Sample] = []

    mutating func add(phase: String, elapsedNanos: UInt64, count: Int = 1) {
        samples.append(Sample(phase: phase, milliseconds: Double(elapsedNanos) / 1_000_000.0, count: count))
    }
}
#endif
