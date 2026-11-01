import Testing
import Foundation
@testable import TimeOfLife

/// Session-marker helpers (account-bound-store): the shared-session user id
/// is mirrored file-first by `SessionCache` on every sign-in/out and read
/// back here for deletion-cleanup ownership checks. Signed-out reads nil —
/// never anon or dormant-account data — and no file is ever created as a
/// side effect of reading.
@Suite("ActiveAccountFileResolver")
struct ActiveAccountFileResolverTests {

    private func temporaryBaseDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
    }

    private func makeDefaults(userID: String?) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        if let userID {
            defaults.set(userID, forKey: "com.timeoflife.session.id")
        }
        return defaults
    }

    @Test("no shared-session user id reads nil (signed out at the gate)")
    func signedOutReadsNil() {
        let base = temporaryBaseDirectory()
        let resolver = ActiveAccountFileResolver(
            sessionDefaults: makeDefaults(userID: nil)
        )
        #expect(resolver.readSessionUserID(base: base) == nil)
    }

    @Test("defaults user id reads back without a sidecar file")
    func defaultsIDReadsBack() {
        let base = temporaryBaseDirectory()
        let resolver = ActiveAccountFileResolver(
            sessionDefaults: makeDefaults(userID: "u1")
        )
        #expect(resolver.readSessionUserID(base: base) == "u1")
        // Reading creates nothing.
        #expect(!FileManager.default.fileExists(atPath: base.path))
    }

    @Test("reading never creates a file for another account's id")
    func readingCreatesNothing() throws {
        let base = temporaryBaseDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let resolver = ActiveAccountFileResolver(
            sessionDefaults: makeDefaults(userID: "user-b")
        )
        #expect(resolver.readSessionUserID(base: base) == "user-b")
        // No anonymous or dormant file was created by the read.
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
    }

    @Test("sidecar file id reads back with empty defaults (extension case)")
    func sidecarFileReadsWithoutDefaults() throws {
        let base = temporaryBaseDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try "u9".write(
            to: base.appendingPathComponent(ActiveAccountFileResolver.sessionFileName),
            atomically: true,
            encoding: .utf8
        )
        let resolver = ActiveAccountFileResolver(
            sessionDefaults: makeDefaults(userID: nil)
        )
        #expect(resolver.readSessionUserID(base: base) == "u9")
    }

    @Test("sidecar file takes precedence over defaults")
    func sidecarFileBeatsDefaults() throws {
        let base = temporaryBaseDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try "u9".write(
            to: base.appendingPathComponent(ActiveAccountFileResolver.sessionFileName),
            atomically: true,
            encoding: .utf8
        )
        let resolver = ActiveAccountFileResolver(
            sessionDefaults: makeDefaults(userID: "u1")
        )
        #expect(resolver.readSessionUserID(base: base) == "u9")
    }
}
