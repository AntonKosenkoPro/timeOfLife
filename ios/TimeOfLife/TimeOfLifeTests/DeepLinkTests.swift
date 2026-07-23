import Testing
import Foundation
@testable import TimeOfLife

@Suite("DeepLink parsing")
struct DeepLinkTests {

    @Test("valid deep link timeoflife://verify?code=123456 parses to otpEntry route")
    func validDeepLink() {
        let url = URL(string: "timeoflife://verify?code=123456")!
        let route = DeepLink.parse(url: url)
        #expect(route == .otpEntry(email: ""))
    }

    @Test("valid deep link extracts code correctly")
    func validDeepLinkExtractsCode() {
        let url = URL(string: "timeoflife://verify?code=123456")!
        #expect(DeepLink.code(from: url) == "123456")
    }

    @Test("legacy auth/verify deep link parses to otpEntry route")
    func legacyAuthVerifyDeepLink() {
        let url = URL(string: "timeoflife://auth/verify?code=123456")!
        let route = DeepLink.parse(url: url)
        #expect(route == .otpEntry(email: ""))
    }

    @Test("legacy auth/verify deep link extracts code correctly")
    func legacyAuthVerifyExtractsCode() {
        let url = URL(string: "timeoflife://auth/verify?code=123456")!
        #expect(DeepLink.code(from: url) == "123456")
    }

    @Test("auth host without /verify path is rejected")
    func authHostWithoutVerifyPath() {
        // Must not over-match: `timeoflife://auth?code=…` is not a verify link.
        #expect(DeepLink.parse(url: URL(string: "timeoflife://auth?code=123456")!) == nil)
        #expect(DeepLink.code(from: URL(string: "timeoflife://auth?code=123456")!) == nil)
        #expect(DeepLink.parse(url: URL(string: "timeoflife://auth/confirm?code=123456")!) == nil)
    }

    @Test("auth/verify deep link with missing code returns nil")
    func authVerifyMissingCode() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://auth/verify")!) == nil)
        #expect(DeepLink.parse(url: URL(string: "timeoflife://auth/verify?code=")!) == nil)
    }

    @Test("auth/verify deep link with extra params still works")
    func authVerifyExtraParams() {
        let url = URL(string: "timeoflife://auth/verify?code=999999&source=email&lang=en")!
        #expect(DeepLink.parse(url: url) == .otpEntry(email: ""))
        #expect(DeepLink.code(from: url) == "999999")
    }

    @Test("deep link with missing code returns nil")
    func missingCode() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify")!) == nil)
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify?code=")!) == nil)
    }

    @Test("deep link with wrong host returns nil")
    func wrongHost() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://other?code=123456")!) == nil)
        #expect(DeepLink.code(from: URL(string: "timeoflife://other?code=123456")!) == nil)
    }

    @Test("deep link with wrong scheme returns nil")
    func wrongScheme() {
        #expect(DeepLink.parse(url: URL(string: "https://verify?code=123456")!) == nil)
        #expect(DeepLink.code(from: URL(string: "https://verify?code=123456")!) == nil)
    }

    @Test("deep link with extra params still works")
    func extraParams() {
        let url = URL(string: "timeoflife://verify?code=999999&source=email&lang=en")!
        #expect(DeepLink.parse(url: url) == .otpEntry(email: ""))
        #expect(DeepLink.code(from: url) == "999999")
    }

    @Test("code extractor only matches the verify host")
    func codeExtractorHost() {
        #expect(DeepLink.code(from: URL(string: "timeoflife://verify?code=999999")!) == "999999")
        #expect(DeepLink.code(from: URL(string: "timeoflife://other?code=1")!) == nil)
        #expect(DeepLink.code(from: URL(string: "https://verify?code=1")!) == nil)
    }

    @Test("AppRoute equality for otp-entry routes")
    func routeEquality() {
        #expect(AppRoute.otpEntry(email: "a") == .otpEntry(email: "a"))
        #expect(AppRoute.otpEntry(email: "a") != .otpEntry(email: "b"))
        #expect(AppRoute.otpEntry(email: "a") != .emailEntry)
        #expect(AppRoute.emailEntry != .signedIn)
    }
}
