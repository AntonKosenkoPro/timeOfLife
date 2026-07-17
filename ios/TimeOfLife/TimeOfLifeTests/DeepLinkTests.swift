import Testing
import Foundation
@testable import TimeOfLife

@Suite("DeepLink parsing")
struct DeepLinkTests {
    @Test("verify magic link parses to .otpEntry")
    func verifyLink() {
        let url = URL(string: "timeoflife://verify?code=123456")!
        #expect(DeepLink.parse(url: url) == .otpEntry(email: ""))
        #expect(DeepLink.code(from: url) == "123456")
    }

    @Test("code extractor only matches the verify host")
    func codeExtractorHost() {
        #expect(DeepLink.code(from: URL(string: "timeoflife://verify?code=999999")!) == "999999")
        #expect(DeepLink.code(from: URL(string: "timeoflife://other?code=1")!) == nil)
        #expect(DeepLink.code(from: URL(string: "https://verify?code=1")!) == nil)
    }

    @Test("wrong scheme is ignored")
    func wrongScheme() {
        let url = URL(string: "https://verify?code=abc")!
        #expect(DeepLink.parse(url: url) == nil)
    }

    @Test("missing code is ignored")
    func missingCode() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify")!) == nil)
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify?code=")!) == nil)
    }

    @Test("unknown host is ignored")
    func unknownHost() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://unknown?code=123456")!) == nil)
    }

    @Test("AppRoute equality for otp-entry routes")
    func routeEquality() {
        #expect(AppRoute.otpEntry(email: "a") == .otpEntry(email: "a"))
        #expect(AppRoute.otpEntry(email: "a") != .otpEntry(email: "b"))
        #expect(AppRoute.otpEntry(email: "a") != .emailEntry)
        #expect(AppRoute.emailEntry != .signedIn)
    }
}