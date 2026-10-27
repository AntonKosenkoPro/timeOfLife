import Testing
import Foundation
@testable import TimeOfLife

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Release formats marketing and commit SHA with v prefix and no suffix")
    func releaseFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "a1b2c3d", isDebug: false, debugSuffix: "Debug")
        #expect(text == "v0.1.0 (a1b2c3d)")
    }

    @Test("Debug appends the localized suffix after a bullet")
    func debugFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "a1b2c3d", isDebug: true, debugSuffix: "Debug")
        #expect(text == "v0.1.0 (a1b2c3d) • Debug")
    }

    @Test("missing bundle keys fall back to placeholders")
    func missingKeys() {
        let text = AppVersion.formatted(marketing: nil, build: nil, isDebug: false, debugSuffix: "Debug")
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

    @Test("internal badge follows the bundle RELEASE_CHANNEL key when present")
    func channelBadgeFollowsBundleKey() {
        // Deliberately not a literal key-presence assert: Bundle.main is the
        // test host app under Xcode but isn't guaranteed to carry built-plist
        // keys in every harness (see runtimeSHA's conditional pattern). What
        // this guards is the wiring — text() must agree with the key.
        let channel = Bundle.main.object(forInfoDictionaryKey: "RELEASE_CHANNEL") as? String
        let badge = "• \(L10n.profileVersionInternalSuffix.text)"
        if channel == "internal" {
            #expect(AppVersion.text.contains(badge))
        } else {
            #expect(!AppVersion.text.contains(badge))
        }
    }
}
