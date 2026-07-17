import Testing
import Foundation
@testable import TimeOfLife

@Suite("DeepLink parsing")
struct DeepLinkTests {
    @Test("verify link parses to route")
    func verifyLink() {
        let url = URL(string: "timeoflife://verify?token=abc123")!
        #expect(DeepLink.parse(url: url) == .verifyEmail(token: "abc123"))
    }

    @Test("reset link parses to route")
    func resetLink() {
        let url = URL(string: "timeoflife://reset?token=xyz")!
        #expect(DeepLink.parse(url: url) == .resetPassword(token: "xyz"))
    }

    @Test("wrong scheme is ignored")
    func wrongScheme() {
        let url = URL(string: "https://verify?token=abc")!
        #expect(DeepLink.parse(url: url) == nil)
    }

    @Test("missing token is ignored")
    func missingToken() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify")!) == nil)
        #expect(DeepLink.parse(url: URL(string: "timeoflife://verify?token=")!) == nil)
    }

    @Test("unknown host is ignored")
    func unknownHost() {
        #expect(DeepLink.parse(url: URL(string: "timeoflife://unknown?token=x")!) == nil)
    }

    @Test("AppRoute equality for token-bearing routes")
    func routeEquality() {
        #expect(AppRoute.verifyEmail(token: "a") == .verifyEmail(token: "a"))
        #expect(AppRoute.verifyEmail(token: "a") != .verifyEmail(token: "b"))
        #expect(AppRoute.resetPassword(token: "a") != .verifyEmail(token: "a"))
    }
}