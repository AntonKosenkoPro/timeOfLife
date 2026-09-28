import Testing
import Foundation
@testable import TimeOfLife

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Release formats marketing and build with no suffix")
    func releaseFormat() {
        let text = AppVersion.formatted(marketing: "1.0.0", build: "3", isDebug: false, debugSuffix: "Debug")
        #expect(text == "1.0.0 (3)")
    }

    @Test("Debug appends the localized suffix after a bullet")
    func debugFormat() {
        let text = AppVersion.formatted(marketing: "1.0.0", build: "3", isDebug: true, debugSuffix: "Debug")
        #expect(text == "1.0.0 (3) • Debug")
    }

    @Test("missing bundle keys fall back to placeholders")
    func missingKeys() {
        let text = AppVersion.formatted(marketing: nil, build: nil, isDebug: false, debugSuffix: "Debug")
        #expect(text == "? (?)")
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
