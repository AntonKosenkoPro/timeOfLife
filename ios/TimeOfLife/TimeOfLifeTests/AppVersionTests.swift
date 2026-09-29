import Testing
import Foundation
@testable import TimeOfLife

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Release formats marketing and build with v prefix and no suffix")
    func releaseFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "1", isDebug: false, debugSuffix: "Debug")
        #expect(text == "v0.1.0 (1)")
    }

    @Test("Debug appends the localized suffix after a bullet")
    func debugFormat() {
        let text = AppVersion.formatted(marketing: "0.1.0", build: "1", isDebug: true, debugSuffix: "Debug")
        #expect(text == "v0.1.0 (1) • Debug")
    }

    @Test("missing bundle keys fall back to placeholders")
    func missingKeys() {
        let text = AppVersion.formatted(marketing: nil, build: nil, isDebug: false, debugSuffix: "Debug")
        #expect(text == "v? (?)")
    }

    @Test("runtime text matches the running configuration")
    func runtimeText() {
        #if DEBUG
        #expect(AppVersion.text.hasSuffix("• \(L10n.profileVersionDebugSuffix.text)"))
        #else
        #expect(!AppVersion.text.contains("•"))
        #endif
    }
}
