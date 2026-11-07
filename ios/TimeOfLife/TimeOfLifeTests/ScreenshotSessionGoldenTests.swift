#if SCREENSHOT_CAPTURE
import Foundation
import Testing
@testable import TimeOfLife

private final class ScreenshotGoldenBundleAnchor: NSObject {}

/// Cross-language golden vectors, task 2.3 Swift side. Consumes the ACTUAL
/// runner-owned fixture file (mirrored byte-identical into the test bundle
/// resources at build time — never hand-copied literals): proves Swift
/// hashes the EXACT `request_json` bytes, computes the same semantic
/// projection (volatile run_id excluded), and parses the runner
/// full-schema payload with unknown keys ignored.
@Suite("Screenshot session golden")
struct ScreenshotSessionGoldenTests {
    private func fixture() throws -> [String: Any] {
        let bundle = Bundle(for: ScreenshotGoldenBundleAnchor.self)
        let url = try #require(bundle.url(
            forResource: "session_envelope_golden",
            withExtension: "json"
        ))
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func vectors() throws -> [[String: Any]] {
        let root = try fixture()
        return try #require(root["vectors"] as? [[String: Any]])
    }

    @Test("fixture contract pins the frozen envelope keys and domains")
    func contract() throws {
        let root = try fixture()
        let contract = try #require(root["contract"] as? [String: Any])
        let keys = try #require(contract["envelope_keys"] as? [String])
        #expect(Set(keys) == [
            "schema_version", "run_id", "session_nonce", "session_domain",
            "seq", "frame", "mode", "request_sha256", "request_json",
        ])
        #expect(Set(contract["domains"] as? [String] ?? []) == ["pinned", "realtime"])
        #expect((contract["sha_rule"] as? String)?.contains("request_json") == true)
    }

    @Test("every vector hashes exactly and parses with full runner schema")
    func vectorsParse() throws {
        let all = try vectors()
        #expect(!all.isEmpty)
        for vector in all {
            try checkVector(vector)
        }
    }

    private func checkVector(_ vector: [String: Any]) throws {
        let name = vector["name"] as? String ?? "(unnamed)"
        let envelope = try #require(vector["envelope"] as? [String: Any], "envelope \(name)")
        let requestJSON = try #require(envelope["request_json"] as? String, "request_json \(name)")
        let expectedSHA = try #require(envelope["request_sha256"] as? String, "sha \(name)")
        // The frozen rule: sha256 over the raw transmitted bytes.
        #expect(
            ScreenshotRequestLoader.sha256Hex(Data(requestJSON.utf8)) == expectedSHA,
            "exact sha \(name)"
        )
        // The semantic projection matches Python across languages.
        let expectedSemantic = try #require(
            vector["request_semantic_sha256"] as? String,
            "semantic \(name)"
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any],
            "payload \(name)"
        )
        #expect(
            try ScreenshotCanonicalJSON.semanticSHA256Hex(payload) == expectedSemantic,
            "semantic sha \(name)"
        )
        let runID = try #require(envelope["run_id"] as? String, "run_id \(name)")
        let nonce = try #require(envelope["session_nonce"] as? String, "nonce \(name)")
        let domainRaw = try #require(envelope["session_domain"] as? String, "domain \(name)")
        let domain = try #require(ScreenshotSessionDomain(rawValue: domainRaw), "domain value \(name)")
        let seq = try #require(envelope["seq"] as? Int, "seq \(name)")
        let outer = try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: Data(requestJSON.utf8),
            runID: runID,
            nonce: nonce,
            domain: domain,
            seq: seq
        )
        let env = try ScreenshotSessionEnvelopeLoader.parse(data: outer)
        #expect(env.runID == runID)
        #expect(env.nonce == nonce)
        #expect(env.domain == domain)
        #expect(env.seq == seq)
        #expect(env.frame.rawValue == (envelope["frame"] as? String))
        #expect(env.mode.rawValue == (envelope["mode"] as? String))
        #expect(env.requestSHA256 == expectedSHA)
        #expect(env.requestJSON == requestJSON)
        // Outer metadata independence on real runner bytes: a fresh
        // nonce never changes the payload hash.
        let other = try ScreenshotSessionEnvelopeLoader.makeOuter(
            payload: Data(requestJSON.utf8),
            runID: runID,
            nonce: "fedcba9876543210fedcba9876543210",
            domain: domain,
            seq: seq
        )
        let rehashed = try ScreenshotSessionEnvelopeLoader.parse(data: other)
        #expect(rehashed.requestSHA256 == expectedSHA)
    }

    @Test("semantic projection excludes only the volatile run_id")
    func semanticExcludesRunID() throws {
        let all = try vectors()
        let first = try #require(all.first)
        let envelope = try #require(first["envelope"] as? [String: Any])
        let requestJSON = try #require(envelope["request_json"] as? String)
        var payload = try #require(
            JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any]
        )
        let baseline = try ScreenshotCanonicalJSON.semanticSHA256Hex(payload)
        payload["run_id"] = "other-pass-run"
        #expect(try ScreenshotCanonicalJSON.semanticSHA256Hex(payload) == baseline)
        payload["frame"] = "insights"
        #expect(try ScreenshotCanonicalJSON.semanticSHA256Hex(payload) != baseline)
    }
}
#endif
