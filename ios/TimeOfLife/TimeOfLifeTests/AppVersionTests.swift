import Testing
import Foundation
@testable import TimeOfLife

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Release formats marketing and commit SHA with v prefix and no suffix")
    func releaseFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "a1b2c3d", isDebug: false, debugSuffix: "Debug", internalSuffix: "Internal")
        #expect(text == "v0.1.0 (a1b2c3d)")
    }

    @Test("Debug appends the localized suffix after a bullet")
    func debugFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "a1b2c3d", isDebug: true, debugSuffix: "Debug", internalSuffix: "Internal")
        #expect(text == "v0.1.0 (a1b2c3d) • Debug")
    }

    @Test("missing bundle keys fall back to placeholders")
    func missingKeys() {
        let text = AppVersion.formatted(marketing: nil, build: nil, isDebug: false, debugSuffix: "Debug", internalSuffix: "Internal")
        #expect(text == "v? (?)")
    }

    @Test("internal channel appends the localized badge, public renders bare")
    func channelBadge() {
        #expect(
            AppVersion.formatted(
                marketing: "0.2.7", build: "a1b2c3d", isDebug: false,
                debugSuffix: "Debug", channel: "internal", internalSuffix: "Internal"
            ) == "v0.2.7 (a1b2c3d) • Internal"
        )
        #expect(
            AppVersion.formatted(
                marketing: "0.3.0", build: "a1b2c3d", isDebug: false,
                debugSuffix: "Debug", channel: "public", internalSuffix: "Internal"
            ) == "v0.3.0 (a1b2c3d)"
        )
    }

    @Test("empty or unknown channel renders bare like a local build")
    func nonInternalChannel() {
        for channel: String? in [nil, "", "beta"] {
            let text = AppVersion.formatted(
                marketing: "0.0.0-dev", build: "a1b2c3d", isDebug: false,
                debugSuffix: "Debug", channel: channel, internalSuffix: "Internal"
            )
            #expect(text == "v0.0.0-dev (a1b2c3d)")
        }
    }

    @Test("internal channel and debug suffix stack")
    func internalDebug() {
        let text = AppVersion.formatted(
            marketing: "0.2.7", build: "a1b2c3d", isDebug: true,
            debugSuffix: "Debug", channel: "internal", internalSuffix: "Internal"
        )
        #expect(text == "v0.2.7 (a1b2c3d) • Internal • Debug")
    }

    @Test("runtime text reflects the stamped commit SHA or the placeholder")
    func runtimeSHA() {
        let stamped = Bundle.main.object(forInfoDictionaryKey: "GIT_COMMIT_SHA") as? String
        if let stamped {
            #expect(AppVersion.text.contains("(\(stamped))"))
        } else {
            #expect(AppVersion.text.contains("(?)"))
        }
    }

    @Test("runtime text matches the running configuration")
    func runtimeText() {
        #if DEBUG
        #expect(AppVersion.text.hasSuffix("• \(L10n.profileVersionDebugSuffix.text)"))
        #else
        #expect(!AppVersion.text.contains("•"))
        #endif
    }

    @Test("text renders bundle values through the formatter")
    func textMatchesFormattedBundleValues() {
        // Asserts the wiring, not the values: text() must faithfully render
        // whatever the bundle carries (branching on the live key, as the old
        // version did, can only ever exercise the negative direction in a
        // Debug harness). The pure formatter's channel matrix is covered by
        // channelBadge() above.
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let sha = Bundle.main.object(forInfoDictionaryKey: "GIT_COMMIT_SHA") as? String
        let channel = Bundle.main.object(forInfoDictionaryKey: "RELEASE_CHANNEL") as? String
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        #expect(AppVersion.text == AppVersion.formatted(
            marketing: marketing,
            build: sha,
            isDebug: isDebug,
            debugSuffix: L10n.profileVersionDebugSuffix.text,
            channel: channel,
            internalSuffix: L10n.profileVersionInternalSuffix.text
        ))
    }

    @Test("internal badge renders from a crafted internal bundle")
    func internalBadgeFromCraftedBundle() throws {
        // The positive path is unreachable with the live test bundle (Debug
        // builds carry RELEASE_CHANNEL=""), so build a bundle carrying it.
        // If text(bundle:) ever stops passing channel/internalSuffix
        // through, this fails — unlike the live-key comparison above.
        var cleanup: [URL] = []
        defer { for dir in cleanup { try? FileManager.default.removeItem(at: dir) } }
        func bundle(channel: String) throws -> Bundle {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            cleanup.append(dir)
            let plist: [String: Any] = [
                "CFBundleShortVersionString": "0.9.9",
                "GIT_COMMIT_SHA": "abc1234",
                "RELEASE_CHANNEL": channel,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: dir.appendingPathComponent("Info.plist"))
            return try #require(Bundle(url: dir))
        }
        let internalText = AppVersion.text(bundle: try bundle(channel: "internal"))
        #expect(internalText.contains("• \(L10n.profileVersionInternalSuffix.text)"))
        #expect(internalText.contains("v0.9.9 (abc1234)"))
        let publicText = AppVersion.text(bundle: try bundle(channel: "public"))
        #expect(!publicText.contains("• \(L10n.profileVersionInternalSuffix.text)"))
    }
}
